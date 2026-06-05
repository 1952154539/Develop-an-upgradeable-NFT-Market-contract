# Develop an Upgradeable NFT Market Contract

A production-ready upgradeable NFT marketplace using the UUPS (Universal Upgradeable Proxy Standard) proxy pattern with OpenZeppelin v5.6.1.

## Overview

This project demonstrates how to build, test, deploy, and upgrade NFT market smart contracts on Ethereum. It includes:

- **Upgradeable ERC721 contract** — SimpleNFT with UUPS upgrade support
- **NFT Market V1** — Core marketplace (list, buy, cancel)
- **NFT Market V2** — Adds EIP-712 offline signature listing (setApprovalForAll once, list via signature)
- **Comprehensive tests** — Including upgrade state consistency tests
- **Sepolia testnet deployment**

## Architecture

```
User ---> Proxy (ERC1967Proxy) ---> Implementation V1 (NFTMarketV1)
                                    |
                                [upgrade]
                                    |
                                    v
                               Implementation V2 (NFTMarketV2)
```

### Key Concepts

- **Proxy Contract (ERC1967Proxy)**: Stores all state, delegates calls to implementation
- **Implementation Contract (V1/V2)**: Contains the business logic, stateless
- **UUPS Pattern**: The upgrade mechanism is in the implementation, more gas-efficient
- **Storage Gap**: Reserved storage slots ensure V2 can safely add new state variables

## Contract Addresses (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| **Market Proxy** (current: V2) | `0xba6c32c379a434a467BAc9679F0424338dfA23e9` |
| Market V1 Implementation | `0x8D841194981aB8881C6E419aD439AaC4cC6ee666` |
| Market V2 Implementation | `0x370419eF2153BE6EF117E5AA5FBD781cC175f652` |
| **NFT Proxy** | `0x2379d5980E5a29bbeA91B3756740956Bea3A6119` |
| NFT Implementation | `0x82e4f357Ebc5D4C78cF6F32d5fbb661D9C01e655` |
| Payment Token (BaseERC20) | `0x9f598DCDa4b7798a9E4740d48E14140B0f15B218` |

> **Note**: Users interact with the **Proxy** addresses. Implementation addresses are for reference and verification.

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install & Build

```bash
git clone https://github.com/1952154539/Develop-an-upgradeable-NFT-Market-contract.git
cd Develop-an-upgradeable-NFT-Market-contract

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test -vvv
```

### Deploy to Sepolia

```bash
export PRIVATE_KEY=your_private_key
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export ETHERSCAN_API_KEY=your_etherscan_api_key

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

## Smart Contracts

### SimpleNFT.sol (Upgradeable ERC721)

UUPS-upgradeable ERC721 with minting and token URI support.

```solidity
function mint(address to, string memory uri) public returns (uint256);
function tokenURI(uint256 tokenId) public view override returns (string memory);
function initialize(string memory name, string memory symbol) public initializer;
```

### NFTMarketV1.sol — Basic Marketplace

Core marketplace with ERC20 payment support.

```solidity
function list(address nftContract, uint256 tokenId, uint256 price) external returns (uint256);
function buyNFT(uint256 listingId) external;
function cancelListing(uint256 listingId) external;
function getListing(uint256 listingId) external view returns (Listing memory);
```

### NFTMarketV2.sol — Signature-Based Listing

Extends V1 with EIP-712 offline signature listing. Users call `setApprovalForAll` once, then list each NFT using just a signature (no on-chain transaction needed for listing).

```solidity
function listWithSignature(
    address nftContract, uint256 tokenId, uint256 price,
    uint256 deadline, uint8 v, bytes32 r, bytes32 s
) external returns (uint256);
function nonces(address user) external view returns (uint256);
```

**EIP-712 Type**:
```
NFTListing(address seller,address nftContract,uint256 tokenId,uint256 price,uint256 deadline,uint256 nonce)
```

**Signature Flow**:
1. User calls `nft.setApprovalForAll(marketProxy, true)` — one-time approval
2. Off-chain: sign `{tokenId, price, deadline, nonce}` using EIP-712
3. Anyone calls `listWithSignature(...)` with the signature — creates listing

## Test Results

```
Ran 18 tests: 18 passed, 0 failed

V1 Tests (9):
  ✓ test_ListNFT
  ✓ test_RevertIfNotOwner
  ✓ test_RevertIfPriceZero
  ✓ test_BuyNFT
  ✓ test_RevertBuyOwnNFT
  ✓ test_RevertBuyInactiveListing
  ✓ test_CancelListing
  ✓ test_RevertCancelNotSeller
  ✓ test_MultipleListings

Upgrade Tests (9):
  ✓ test_V1_ListAndBuy
  ✓ test_V1_ListAndCancel
  ✓ test_Upgrade_StateConsistency
  ✓ test_V2_SignatureListing
  ✓ test_V2_SignatureListingThenBuy
  ✓ test_V2_RevertExpiredSignature
  ✓ test_V2_RevertInvalidSignature
  ✓ test_V2_RevertReplaySignature
  ✓ test_V2_MultipleSignatureListings
```

The `test_Upgrade_StateConsistency` test verifies that all listing data, payment token address, and counters remain intact after upgrading from V1 to V2.

## How Upgrade Works

### Step 1: Deploy V1

```solidity
// Deploy implementation (stateless, only code)
NFTMarketV1 v1Impl = new NFTMarketV1();

// Deploy proxy (holds state) with initialization
bytes memory initData = abi.encodeCall(NFTMarketV1.initialize, (paymentToken));
ERC1967Proxy proxy = new ERC1967Proxy(address(v1Impl), initData);
```

### Step 2: Upgrade to V2

```solidity
// Deploy new implementation
NFTMarketV2 v2Impl = new NFTMarketV2();

// Upgrade proxy — all state preserved!
NFTMarketV1(address(proxy)).upgradeToAndCall(address(v2Impl), "");

// Initialize V2-specific state
NFTMarketV2(address(proxy)).initializeV2();
```

**Key**: The proxy address stays the same. All state (listings, balances, approvals) is preserved in the proxy's storage. Users continue interacting with the same proxy address.

### Storage Layout Safety

V1 reserves a `__gap` of 50 storage slots. V2 uses 1 slot for `_nonces` mapping, leaving 49 gap slots for future upgrades.

```solidity
// V1
uint256[50] private __gap;

// V2 (inherits V1, adds:)
mapping(address => uint256) private _nonces;
uint256[49] private __gap;
```

## Technology Stack

- **Solidity** ^0.8.24
- **Foundry** (forge, cast)
- **OpenZeppelin** v5.6.1 (contracts + contracts-upgradeable)
- **EIP-712** typed structured data signing
- **UUPS Proxy** (ERC-1967)

## License

MIT
