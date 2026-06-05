// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BaseERC20.sol";
import "../src/SimpleNFT.sol";
import "../src/NFTMarketV1.sol";
import "../src/NFTMarketV2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UpgradeTest is Test {
    BaseERC20 public paymentToken;
    SimpleNFT public nft;
    ERC1967Proxy public marketProxy;
    NFTMarketV1 public marketV1;
    NFTMarketV2 public marketV2;

    address public owner = address(0x1);

    // Use a proper private key and derive the address
    uint256 public sellerKey = 0xabc123;
    address public seller = vm.addr(0xabc123);

    address public buyer = address(0x3);

    bytes32 constant LISTING_TYPEHASH = keccak256(
        "NFTListing(address seller,address nftContract,uint256 tokenId,uint256 price,uint256 deadline,uint256 nonce)"
    );

    bytes32 constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    function setUp() public {
        vm.startPrank(owner);

        paymentToken = new BaseERC20();

        SimpleNFT nftImpl = new SimpleNFT();
        bytes memory nftInitData = abi.encodeCall(SimpleNFT.initialize, ("Simple NFT", "SNFT"));
        ERC1967Proxy nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        nft = SimpleNFT(address(nftProxy));

        NFTMarketV1 marketImpl = new NFTMarketV1();
        bytes memory marketInitData = abi.encodeCall(
            NFTMarketV1.initialize, (address(paymentToken))
        );
        marketProxy = new ERC1967Proxy(address(marketImpl), marketInitData);
        marketV1 = NFTMarketV1(address(marketProxy));

        paymentToken.transfer(buyer, 10000 * 1e18);
        paymentToken.transfer(seller, 1000 * 1e18);

        vm.stopPrank();

        vm.startPrank(seller);
        nft.mint(seller, "ipfs://token1");
        nft.mint(seller, "ipfs://token2");
        nft.setApprovalForAll(address(marketV1), true);
        vm.stopPrank();
    }

    // ==================== V1 Tests (pre-upgrade) ====================

    function test_V1_ListAndBuy() public {
        vm.startPrank(seller);
        marketV1.list(address(nft), 1, 100 * 1e18);
        vm.stopPrank();

        uint256 sellerBalBefore = paymentToken.balanceOf(seller);

        vm.startPrank(buyer);
        paymentToken.approve(address(marketV1), 100 * 1e18);
        marketV1.buyNFT(0);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), buyer);
        assertEq(paymentToken.balanceOf(seller), sellerBalBefore + 100 * 1e18);
    }

    function test_V1_ListAndCancel() public {
        vm.startPrank(seller);
        uint256 listingId = marketV1.list(address(nft), 1, 100 * 1e18);
        marketV1.cancelListing(listingId);
        vm.stopPrank();

        NFTMarketV1.Listing memory listing = marketV1.getListing(0);
        assertFalse(listing.active);
    }

    // ==================== Upgrade Test ====================

    function test_Upgrade_StateConsistency() public {
        // List NFTs in V1
        vm.startPrank(seller);
        uint256 id0 = marketV1.list(address(nft), 1, 100 * 1e18);
        uint256 id1 = marketV1.list(address(nft), 2, 200 * 1e18);
        vm.stopPrank();

        // Record V1 state
        NFTMarketV1.Listing memory listing0Before = marketV1.getListing(id0);
        NFTMarketV1.Listing memory listing1Before = marketV1.getListing(id1);
        uint256 counterBefore = marketV1.listingCounter();
        address paymentTokenBefore = address(marketV1.paymentToken());

        // Upgrade to V2
        vm.startPrank(owner);
        NFTMarketV2 marketV2Impl = new NFTMarketV2();
        marketV1.upgradeToAndCall(address(marketV2Impl), "");
        marketV2 = NFTMarketV2(address(marketProxy));
        marketV2.initializeV2();
        vm.stopPrank();

        // Verify state preserved
        assertEq(marketV2.listingCounter(), counterBefore);
        assertEq(address(marketV2.paymentToken()), paymentTokenBefore);

        NFTMarketV1.Listing memory listing0After = marketV2.getListing(id0);
        assertEq(listing0After.seller, listing0Before.seller);
        assertEq(listing0After.nftContract, listing0Before.nftContract);
        assertEq(listing0After.tokenId, listing0Before.tokenId);
        assertEq(listing0After.price, listing0Before.price);
        assertTrue(listing0After.active);

        NFTMarketV1.Listing memory listing1After = marketV2.getListing(id1);
        assertEq(listing1After.seller, listing1Before.seller);
        assertEq(listing1After.tokenId, listing1Before.tokenId);
        assertEq(listing1After.price, listing1Before.price);
        assertTrue(listing1After.active);

        // Buy a V1 listing after upgrade
        vm.startPrank(buyer);
        paymentToken.approve(address(marketV2), 100 * 1e18);
        marketV2.buyNFT(id0);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), buyer);
        assertFalse(marketV2.getListing(id0).active);
        assertTrue(marketV2.getListing(id1).active);
    }

    // ==================== V2 Signature Tests ====================

    function _upgradeToV2() internal {
        vm.startPrank(owner);
        NFTMarketV2 impl = new NFTMarketV2();
        marketV1.upgradeToAndCall(address(impl), "");
        marketV2 = NFTMarketV2(address(marketProxy));
        marketV2.initializeV2();
        vm.stopPrank();
    }

    function test_V2_SignatureListing() public {
        _upgradeToV2();

        uint256 tokenId = 1;
        uint256 price = 100 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes32 digest = _buildDigest(
            address(marketV2), seller, address(nft), tokenId, price, deadline, nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerKey, digest);

        vm.startPrank(buyer);
        uint256 listingId = marketV2.listWithSignature(
            address(nft), tokenId, price, deadline, v, r, s
        );
        vm.stopPrank();

        assertEq(listingId, 0);
        assertEq(marketV2.listingCounter(), 1);

        NFTMarketV2.Listing memory listing = marketV2.getListing(0);
        assertEq(listing.seller, seller);
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, price);
        assertTrue(listing.active);

        assertEq(marketV2.nonces(seller), 1);
    }

    function test_V2_SignatureListingThenBuy() public {
        _upgradeToV2();

        uint256 tokenId = 1;
        uint256 price = 100 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _buildDigest(
            address(marketV2), seller, address(nft), tokenId, price, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerKey, digest);

        vm.prank(buyer);
        marketV2.listWithSignature(address(nft), tokenId, price, deadline, v, r, s);

        uint256 sellerBalBefore = paymentToken.balanceOf(seller);

        vm.startPrank(buyer);
        paymentToken.approve(address(marketV2), price);
        marketV2.buyNFT(0);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(paymentToken.balanceOf(seller), sellerBalBefore + price);
    }

    function test_V2_RevertExpiredSignature() public {
        _upgradeToV2();

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _buildDigest(
            address(marketV2), seller, address(nft), 1, 100 * 1e18, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerKey, digest);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(buyer);
        vm.expectRevert("Signature expired");
        marketV2.listWithSignature(address(nft), 1, 100 * 1e18, deadline, v, r, s);
    }

    function test_V2_RevertInvalidSignature() public {
        _upgradeToV2();

        address otherUser = address(0x4);
        uint256 otherKey = 0xdef456;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _buildDigest(
            address(marketV2), otherUser, address(nft), 1, 100 * 1e18, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherKey, digest);

        vm.prank(buyer);
        vm.expectRevert("Invalid signature");
        marketV2.listWithSignature(address(nft), 1, 100 * 1e18, deadline, v, r, s);
    }

    function test_V2_RevertReplaySignature() public {
        _upgradeToV2();

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _buildDigest(
            address(marketV2), seller, address(nft), 1, 100 * 1e18, deadline, 0
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerKey, digest);

        // First use works
        vm.prank(buyer);
        marketV2.listWithSignature(address(nft), 1, 100 * 1e18, deadline, v, r, s);

        // Replay fails (nonce changed)
        vm.prank(buyer);
        vm.expectRevert("Invalid signature");
        marketV2.listWithSignature(address(nft), 1, 100 * 1e18, deadline, v, r, s);
    }

    function test_V2_MultipleSignatureListings() public {
        _upgradeToV2();

        uint256 deadline = block.timestamp + 1 hours;

        // List token 1 with nonce=0
        bytes32 digest1 = _buildDigest(
            address(marketV2), seller, address(nft), 1, 100 * 1e18, deadline, 0
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(sellerKey, digest1);

        vm.prank(buyer);
        marketV2.listWithSignature(address(nft), 1, 100 * 1e18, deadline, v1, r1, s1);

        // List token 2 with nonce=1
        bytes32 digest2 = _buildDigest(
            address(marketV2), seller, address(nft), 2, 200 * 1e18, deadline, 1
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(sellerKey, digest2);

        vm.prank(buyer);
        marketV2.listWithSignature(address(nft), 2, 200 * 1e18, deadline, v2, r2, s2);

        assertEq(marketV2.listingCounter(), 2);
        assertEq(marketV2.nonces(seller), 2);

        NFTMarketV2.Listing memory l1 = marketV2.getListing(0);
        assertEq(l1.tokenId, 1);
        assertEq(l1.price, 100 * 1e18);

        NFTMarketV2.Listing memory l2 = marketV2.getListing(1);
        assertEq(l2.tokenId, 2);
        assertEq(l2.price, 200 * 1e18);
    }

    // ==================== Helper ====================

    function _buildDigest(
        address verifyingContract,
        address sellerAddr,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256("NFTMarket"),
                keccak256("1"),
                block.chainid,
                verifyingContract
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(LISTING_TYPEHASH, sellerAddr, nftContract, tokenId, price, deadline, nonce)
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
