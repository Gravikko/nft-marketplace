import { useReadContract, useWriteContract } from "wagmi";
import MarketplaceABI from "../contracts/abis/Marketplace.json";
import { ADDRESSES } from "../contracts/addresses";

export function useRoyaltyAndFeeInfo(
  collectionAddress: `0x${string}` | undefined,
  tokenId: number,
  price: bigint,
) {
  return useReadContract({
    address: ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: "getAllRoyaltyAndFeeInfo",
    args: collectionAddress ? [collectionAddress, tokenId, price] : undefined,
  });
}

export function useExecuteOrder() {
  return useWriteContract();
}

export function useExecuteOffer() {
  return useWriteContract();
}

export function useCancelOrder() {
  return useWriteContract();
}

export function useCancelOffer() {
  return useWriteContract();
}

export function useBuyUnmintedToken() {
  return useWriteContract();
}
