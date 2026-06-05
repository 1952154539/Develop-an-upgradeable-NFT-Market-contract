// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BaseERC20.sol";
import "../src/SimpleNFT.sol";
import "../src/NFTMarketV1.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NFTMarketV1Test is Test {
    BaseERC20 public paymentToken;
    SimpleNFT public nft;
    NFTMarketV1 public market;

    address public owner = address(0x1);
    address public seller = address(0x2);
    address public buyer = address(0x3);

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
        ERC1967Proxy marketProxy = new ERC1967Proxy(address(marketImpl), marketInitData);
        market = NFTMarketV1(address(marketProxy));

        paymentToken.transfer(buyer, 10000 * 1e18);

        vm.stopPrank();

        vm.startPrank(seller);
        nft.mint(seller, "ipfs://token1");
        nft.setApprovalForAll(address(market), true);
        vm.stopPrank();
    }

    function test_ListNFT() public {
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nft), 1, 100 * 1e18);
        vm.stopPrank();

        assertEq(listingId, 0);
        NFTMarketV1.Listing memory listing = market.getListing(0);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(nft));
        assertEq(listing.tokenId, 1);
        assertEq(listing.price, 100 * 1e18);
        assertTrue(listing.active);
    }

    function test_RevertIfNotOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("Not the owner");
        market.list(address(nft), 1, 100 * 1e18);
        vm.stopPrank();
    }

    function test_RevertIfPriceZero() public {
        vm.startPrank(seller);
        vm.expectRevert("Price must be greater than 0");
        market.list(address(nft), 1, 0);
        vm.stopPrank();
    }

    function test_BuyNFT() public {
        vm.startPrank(seller);
        market.list(address(nft), 1, 100 * 1e18);
        vm.stopPrank();

        uint256 sellerBalBefore = paymentToken.balanceOf(seller);

        vm.startPrank(buyer);
        paymentToken.approve(address(market), 100 * 1e18);
        market.buyNFT(0);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), buyer);
        assertEq(paymentToken.balanceOf(seller), sellerBalBefore + 100 * 1e18);

        NFTMarketV1.Listing memory listing = market.getListing(0);
        assertFalse(listing.active);
    }

    function test_RevertBuyOwnNFT() public {
        vm.startPrank(seller);
        market.list(address(nft), 1, 100 * 1e18);
        paymentToken.approve(address(market), 100 * 1e18);
        vm.expectRevert("Cannot buy own NFT");
        market.buyNFT(0);
        vm.stopPrank();
    }

    function test_RevertBuyInactiveListing() public {
        vm.startPrank(seller);
        market.list(address(nft), 1, 100 * 1e18);
        market.cancelListing(0);
        vm.stopPrank();

        vm.startPrank(buyer);
        paymentToken.approve(address(market), 100 * 1e18);
        vm.expectRevert("Listing not active");
        market.buyNFT(0);
        vm.stopPrank();
    }

    function test_CancelListing() public {
        vm.startPrank(seller);
        market.list(address(nft), 1, 100 * 1e18);
        market.cancelListing(0);
        vm.stopPrank();

        NFTMarketV1.Listing memory listing = market.getListing(0);
        assertFalse(listing.active);
    }

    function test_RevertCancelNotSeller() public {
        vm.startPrank(seller);
        market.list(address(nft), 1, 100 * 1e18);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Not the seller");
        market.cancelListing(0);
        vm.stopPrank();
    }

    function test_MultipleListings() public {
        vm.startPrank(seller);
        nft.mint(seller, "ipfs://token2");
        nft.mint(seller, "ipfs://token3");

        uint256 id0 = market.list(address(nft), 1, 100 * 1e18);
        uint256 id1 = market.list(address(nft), 2, 200 * 1e18);
        uint256 id2 = market.list(address(nft), 3, 300 * 1e18);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(market.listingCounter(), 3);
    }
}
