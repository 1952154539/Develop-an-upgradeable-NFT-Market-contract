// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BaseERC20.sol";
import "../src/SimpleNFT.sol";
import "../src/NFTMarketV1.sol";
import "../src/NFTMarketV2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1. Deploy BaseERC20 (payment token)
        BaseERC20 paymentToken = new BaseERC20();
        console.log("BaseERC20 deployed at:", address(paymentToken));

        // 2. Deploy SimpleNFT implementation
        SimpleNFT nftImpl = new SimpleNFT();
        console.log("SimpleNFT implementation at:", address(nftImpl));

        // 3. Deploy SimpleNFT proxy
        bytes memory nftInitData = abi.encodeCall(SimpleNFT.initialize, ("Upgradeable NFT", "UNFT"));
        ERC1967Proxy nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        SimpleNFT nft = SimpleNFT(address(nftProxy));
        console.log("SimpleNFT proxy at:", address(nftProxy));

        // 4. Deploy NFTMarketV1 implementation
        NFTMarketV1 marketV1Impl = new NFTMarketV1();
        console.log("NFTMarketV1 implementation at:", address(marketV1Impl));

        // 5. Deploy NFTMarketV1 proxy
        bytes memory marketInitData = abi.encodeCall(
            NFTMarketV1.initialize, (address(paymentToken))
        );
        ERC1967Proxy marketProxy = new ERC1967Proxy(address(marketV1Impl), marketInitData);
        NFTMarketV1 marketV1 = NFTMarketV1(address(marketProxy));
        console.log("NFTMarketV1 proxy at:", address(marketProxy));

        // 6. Deploy NFTMarketV2 implementation (for upgrade)
        NFTMarketV2 marketV2Impl = new NFTMarketV2();
        console.log("NFTMarketV2 implementation at:", address(marketV2Impl));

        // 7. Upgrade proxy to V2
        marketV1.upgradeToAndCall(address(marketV2Impl), "");
        console.log("Upgraded market proxy to V2 implementation");

        // 8. Call initializeV2
        NFTMarketV2(address(marketProxy)).initializeV2();
        console.log("NFTMarketV2 initialized");

        // 9. Mint a test NFT
        nft.mint(deployer, "ipfs://QmTest/test-metadata.json");
        console.log("Minted NFT #1 to deployer");

        vm.stopBroadcast();

        // Output summary
        console.log("\n=== Deployment Summary ===");
        console.log("Payment Token (BaseERC20):", address(paymentToken));
        console.log("NFT Implementation:", address(nftImpl));
        console.log("NFT Proxy:", address(nftProxy));
        console.log("Market V1 Implementation:", address(marketV1Impl));
        console.log("Market V2 Implementation:", address(marketV2Impl));
        console.log("Market Proxy (current V2):", address(marketProxy));
    }
}
