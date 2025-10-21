# NFT Marketplace

A pet-project NFT marketplace built with Solidity + Foundry for contracts and React + TypeScript + Vite for the frontend.

## Project Structure

```
├── contracts/          # Solidity smart contracts (Foundry)
├── frontend/          # React + TypeScript + Vite
├── scripts/           # Deployment scripts
└── README.md
```

## Tech Stack

- **Smart Contracts:** Solidity + Foundry
- **Frontend:** React + TypeScript + Vite
- **Wallet Integration:** wagmi/viem
- **Target Networks:** Ethereum testnets and L2s

## Getting Started

```bash
# Install dependencies
npm install

# Start development
npm run dev
```

## 🔧 Environment Setup

Create `.env.local`:
```env
VITE_RPC_URL=your_rpc_url
VITE_CHAIN_ID=your_chain_id
```

## 📋 Planned Features

- Wallet-first authentication
- NFT minting and trading
- User profiles and inventory
- Creator royalties
- Multi-network support

---

Built for learning and prototyping NFT marketplaces.
