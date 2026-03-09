import { useReadContract, useWriteContract } from "wagmi";
import CollectionABI from "../contracts/abis/ERC721Collection.json";

export function useSupply(collectionAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: collectionAddress,
    abi: CollectionABI,
    functionName: "getSupply",
  });
}

export function useRemainingSupply(collectionAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: collectionAddress,
    abi: CollectionABI,
    functionName: "remainingSupply",
  });
}

export function useMintPrice(collectionAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: collectionAddress,
    abi: CollectionABI,
    functionName: "mintPrice",
  });
}

export function useCollectionSettings(collectionAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: collectionAddress,
    abi: CollectionABI,
    functionName: "getCollectionSettings",
  });
}

export function useMint() {
  return useWriteContract();
}
