# NFT Marketplace

A full-featured decentralized NFT marketplace built with Solidity (Foundry) and React (TypeScript + Vite). Supports collection creation, trading via signed orders, auctions, staking, and multisig governance.

## Features

### Collection Factory
- Create ERC721 collections with customizable royalties (ERC2981)
- Beacon proxy pattern for gas-efficient deployments
- Batch minting on collection creation
- Configurable mint prices and max supply (up to 20,000 tokens)

### NFT Reveal System
- **Instant reveal**: Pseudo-random using block data
- **Delayed reveal**: Chainlink VRF v2.5 for cryptographically secure randomness
- Placeholder URIs for unrevealed tokens

### Marketplace Trading
- **Orders**: Seller-initiated listings (ETH payment)
- **Offers**: Buyer-initiated offers (WETH payment)
- EIP-712 signed orders (off-chain signatures)
- Automatic royalty distribution (up to 10%)
- Configurable marketplace fees (up to 5%)

### Auction System
- Configurable duration (30 min to 7 days)
- Minimum bid increment (5-50%)
- Late bid extension (5 min if bid in final 5 min)
- Failed bid withdrawal for non-winners

### NFT Staking
- Stake NFTs from any collection
- Time-based ETH rewards
- Per-user staked NFT tracking

### Governance
- MultisigTimelock for all admin operations
- Configurable delays and approval thresholds
- Owner management (add/remove signers)

## Project Structure

```
nft-marketplace/
├── foundry/                    # Smart contracts (Solidity/Foundry)
│   ├── src/                    # Contract source files
│   │   ├── ERC721Collection.sol      # Upgradeable NFT with royalties & VRF
│   │   ├── Factory.sol               # Collection factory with beacon proxies
│   │   ├── Marketplace.sol           # EIP-712 signed order marketplace
│   │   ├── Auction.sol               # Time-based auction system
│   │   ├── Staking.sol               # NFT staking with rewards
│   │   ├── MultisigTimelock.sol      # Governance layer
│   │   ├── VRFAdapter.sol            # Chainlink VRF integration
│   │   ├── ERC721CollectionBeacon.sol
│   │   ├── SwapAdapter.sol           # ETH/WETH utility
│   │   └── interfaces/
│   ├── test/                   # Comprehensive test suite
│   │   ├── unit/               # Unit tests by module
│   │   └── helpers/            # Test utilities & mocks
│   ├── script/                 # Deployment scripts
│   └── lib/                    # Dependencies (OpenZeppelin, Chainlink)
├── frontend/                   # React + TypeScript + Vite (WIP)
└── pnpm-workspace.yaml         # Monorepo config
```

## Tech Stack

**Smart Contracts**
- Solidity 0.8.24
- Foundry (forge, cast, anvil)
- OpenZeppelin Upgradeable Contracts
- Chainlink VRF v2.5
- EIP-712 signatures
- ERC721 + ERC2981 standards

**Frontend**
- React 18
- TypeScript
- Vite
- wagmi/viem (planned)

## Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+
- pnpm

### Installation

```bash
# Clone and install
git clone <repo-url>
cd nft-marketplace
pnpm install

# Install Foundry dependencies
cd foundry
forge install
```

### Run Tests

```bash
cd foundry
forge test
```

### Local Development

```bash
# Start local Anvil node
anvil

# Deploy contracts (in another terminal)
cd foundry
forge script script/DeployFactory.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Environment Setup

Copy `.env.example` to `.env` and configure:

```env
# RPC & Providers
RPC_URL=your_rpc_url
ALCHEMY_API_KEY=your_key

# Contract Verification
ETHERSCAN_API_KEY=your_key

# Deployment
DEPLOYER_PRIVATE_KEY=your_key

# Frontend
VITE_APP_MARKETPLACE_ADDRESS=deployed_address
VITE_APP_CHAIN_ID=chain_id
```

## Contract Architecture

### Proxy Pattern
- **UUPS Proxies**: Factory, Marketplace, Auction, Staking, VRFAdapter
- **Beacon Proxy**: All ERC721Collection instances share implementation

### Deployment Order
1. MultisigTimelock (governance)
2. VRFAdapter (Chainlink VRF)
3. ERC721Collection implementation
4. ERC721CollectionBeacon
5. Factory
6. Marketplace (with WETH address)
7. Auction
8. Staking
9. Wire addresses via MultisigTimelock

## Key Parameters

| Parameter | Value |
|-----------|-------|
| Max Collection Supply | 20,000 tokens |
| Max Royalty Fee | 10% |
| Max Marketplace Fee | 5% |
| Max Auction Fee | 5% |
| Min Auction Duration | 30 minutes |
| Max Auction Duration | 7 days |
| Min Bid Increment | 5% |
| Min Trade Price | 1,000 wei |

## Security

- ReentrancyGuard on all sensitive functions
- EIP-712 signature verification
- Multisig + timelock for admin operations
- Zero address checks throughout
- Custom errors for gas efficiency
- Comprehensive test coverage

## Development Status

- [x] Smart contracts (complete)
- [x] Test suite (complete)
- [ ] Frontend implementation
- [ ] Subgraph indexer
- [ ] Deployment scripts for testnets

## License

MIT
