import { useReadContract, useWriteContract } from "wagmi";
import StakingABI from "../contracts/abis/Staking.json";
import { ADDRESSES } from "../contracts/addresses";

export function useStaker(collectionId: number, tokenId: number) {
  return useReadContract({
    address: ADDRESSES.staking,
    abi: StakingABI,
    functionName: "getStaker",
    args: [collectionId, tokenId],
  });
}

export function useUserStakedTokens(user: `0x${string}` | undefined, collectionId: number) {
  return useReadContract({
    address: ADDRESSES.staking,
    abi: StakingABI,
    functionName: "getUserStakedTokens",
    args: user ? [user, collectionId] : undefined,
  });
}

export function useStakedTimestamp(collectionId: number, tokenId: number) {
  return useReadContract({
    address: ADDRESSES.staking,
    abi: StakingABI,
    functionName: "getStakedTimestamp",
    args: [collectionId, tokenId],
  });
}

export function useStake() {
  return useWriteContract();
}

export function useUnstakeNFT() {
  return useWriteContract();
}
