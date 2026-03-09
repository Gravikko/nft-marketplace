import { useReadContract, useWriteContract } from "wagmi";
import AuctionABI from "../contracts/abis/Auction.json";
import { ADDRESSES } from "../contracts/addresses";

export function useAuctionInfo(auctionId: number) {
  return useReadContract({
    address: ADDRESSES.auction,
    abi: AuctionABI,
    functionName: "getAuctionInfo",
    args: [auctionId],
  });
}

export function useMaximumBid(auctionId: number) {
  return useReadContract({
    address: ADDRESSES.auction,
    abi: AuctionABI,
    functionName: "getMaximumBid",
    args: [auctionId],
  });
}

export function useNextBidAmount(auctionId: number) {
  return useReadContract({
    address: ADDRESSES.auction,
    abi: AuctionABI,
    functionName: "getNextBidAmount",
    args: [auctionId],
  });
}

export function usePutTokenOnAuction() {
  return useWriteContract();
}

export function useMakeABid() {
  return useWriteContract();
}

export function useFinalizeAuction() {
  return useWriteContract();
}

export function useCancelAuction() {
  return useWriteContract();
}

export function useWithdrawAuctionBid() {
  return useWriteContract();
}
