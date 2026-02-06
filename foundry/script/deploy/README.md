# NFT Marketplace Deployment Scripts

## Quick Start

### Local Development (Anvil)

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy
forge script script/deploy/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet/Mainnet Deployment

1. Copy and configure environment:
```bash
cp .env.example .env
# Edit .env with your values
```

2. Deploy all contracts:
```bash
source .env
forge script script/deploy/DeployAll.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## Deployment Order

The scripts deploy contracts in this order:

### Phase 1: Base Contracts
1. **MultisigTimelock** - Governance/admin control
2. **ERC721Collection** - Implementation (template for collections)
3. **SwapAdapter** - ETH/WETH utility
4. **VRFAdapter** - Chainlink VRF integration

### Phase 2: Beacon & Factory
5. **ERC721CollectionBeacon** - Points to ERC721Collection impl
6. **Factory** - Creates new collections

### Phase 3: Trading Contracts
7. **Marketplace** - Order/offer trading
8. **Auction** - Time-based auctions
9. **Staking** - NFT staking for rewards

### Phase 4: Configuration (Manual via MultisigTimelock)
After deployment, configure via MultisigTimelock transactions:

```solidity
// Factory
Factory.setBeaconAddress(beacon)
Factory.setVRFAdapter(vrfAdapter)
Factory.setMarketplaceAddress(marketplace)
Factory.activateFactory()

// Marketplace
Marketplace.setMarketplaceFeeAmount(250)  // 2.5%
Marketplace.setMarketplaceFeeReceiver(receiver)
Marketplace.activateMarketplace()

// Auction
Auction.setFactoryAddress(factory)
Auction.setAuctionFeeAmount(250)  // 2.5%
Auction.setAuctionFeeReceiver(receiver)
Auction.activateAuction()

// Staking
Staking.setFactoryAddress(factory)
Staking.setRewardAmount(rewardPerSecond)
Staking.activateStaking()
```

## Individual Deployment Scripts

Deploy contracts individually:

```bash
# MultisigTimelock
forge script script/deploy/DeployMultisigTimelock.s.sol --rpc-url $RPC_URL --broadcast

# Factory (requires MULTISIG_TIMELOCK env var)
MULTISIG_TIMELOCK=0x... forge script script/deploy/DeployFactory.s.sol --rpc-url $RPC_URL --broadcast

# etc.
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `RPC_URL` | Network RPC endpoint | `https://eth-sepolia...` |
| `PRIVATE_KEY` | Deployer private key | `abc123...` |
| `OWNER_COUNT` | Number of multisig owners | `3` |
| `OWNER_1..N` | Owner addresses | `0x...` |
| `MIN_APPROVALS` | Required approvals | `2` |
| `WETH_ADDRESS` | WETH contract address | `0x7b799...` |
| `VRF_COORDINATOR` | Chainlink VRF coordinator | `0x9DdfaCa...` |
| `VRF_SUBSCRIPTION_ID` | Chainlink subscription ID | `1234` |
| `VRF_KEY_HASH` | VRF key hash | `0x787d74...` |

See `.env.example` for full list.

## Network Addresses

### WETH
| Network | Address |
|---------|---------|
| Mainnet | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| Sepolia | `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` |
| Arbitrum | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` |
| Base | `0x4200000000000000000000000000000000000006` |

### Chainlink VRF v2.5 Coordinator
| Network | Address |
|---------|---------|
| Mainnet | `0xD7f86b4b8Cae7D942340FF628F82735b7a20893a` |
| Sepolia | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| Arbitrum | `0x3C0Ca683b403E37668AE3DC4FB62F4B29B6f7a3e` |

## Contract Verification

Add `--verify` flag and set `ETHERSCAN_API_KEY`:

```bash
ETHERSCAN_API_KEY=xxx forge script script/deploy/DeployAll.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## Post-Deployment Checklist

- [ ] All contracts deployed successfully
- [ ] Factory configured with beacon, VRF adapter, marketplace
- [ ] Factory activated
- [ ] Marketplace fees set and activated
- [ ] Auction configured with factory and fees, activated
- [ ] Staking configured with factory and rewards, activated
- [ ] VRFAdapter added as consumer to Chainlink subscription
- [ ] Contract addresses verified on Etherscan
- [ ] MultisigTimelock owners confirmed
