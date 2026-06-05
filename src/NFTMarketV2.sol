// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./NFTMarketV1.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTMarketV2 is NFTMarketV1 {
    bytes32 private constant LISTING_TYPEHASH =
        keccak256(
            "NFTListing(address seller,address nftContract,uint256 tokenId,uint256 price,uint256 deadline,uint256 nonce)"
        );

    mapping(address => uint256) private _nonces;

    event SignatureListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    );

    function initializeV2() public reinitializer(2) {}

    function listWithSignature(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256) {
        require(block.timestamp <= deadline, "Signature expired");
        require(price > 0, "Price must be greater than 0");
        require(nftContract != address(0), "Invalid NFT contract");

        IERC721 nft = IERC721(nftContract);
        address seller = nft.ownerOf(tokenId);
        require(seller != address(0), "Token does not exist");
        require(
            nft.isApprovedForAll(seller, address(this)) ||
                nft.getApproved(tokenId) == address(this),
            "Market not approved"
        );

        _verifySignature(seller, nftContract, tokenId, price, deadline, v, r, s);

        uint256 listingId = listingCounter++;
        listings[listingId] = Listing({
            seller: seller,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit NFTListed(listingId, seller, nftContract, tokenId, price);
        emit SignatureListed(listingId, seller, nftContract, tokenId, price, deadline);

        return listingId;
    }

    function _verifySignature(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonce = _nonces[seller]++;
        bytes32 structHash = keccak256(
            abi.encode(LISTING_TYPEHASH, seller, nftContract, tokenId, price, deadline, nonce)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ecrecover(digest, v, r, s);
        require(signer == seller, "Invalid signature");
    }

    function nonces(address user) external view returns (uint256) {
        return _nonces[user];
    }

    uint256[49] private __gap;
}
