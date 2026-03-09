# Frontend Plan

## Step 1 — Project Setup
Vite + React + TypeScript + wagmi + viem + RainbowKit. Wallet connection working.

## Step 2 — Contract Integration
ABIs, deployed addresses, typed hooks for read/write calls.

## Step 3 — On-Chain Pages
Pages that work by reading/writing contract state directly:
- Create Collection (Factory)
- Collection View + Mint (ERC721Collection)
- Staking Dashboard (Staking)
- Auction (create, bid, finalize)

## Step 4 — Order Book Backend
Simple API to store/serve signed EIP-712 orders and offers.

## Step 5 — Marketplace Pages
Browse listings, buy (execute order), make/accept offers. Depends on Step 4.

## Step 6 — Polish
Error handling, loading states, responsive design, UX improvements.

---

**Current step: 1**
