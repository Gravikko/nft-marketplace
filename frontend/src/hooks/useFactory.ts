import { useReadContract, useWriteContract } from "wagmi";
import FactoryABI from "../contracts/abis/Factory.json";
import { ADDRESSES } from "../contracts/addresses";

export function useCollectionAddress(collectionId: number) {
  return useReadContract({
    address: ADDRESSES.factory,
    abi: FactoryABI,
    functionName: "getCollectionAddressById",
    args: [collectionId],
  });
}

export function useCollectionOwner(collectionId: number) {
  return useReadContract({
    address: ADDRESSES.factory,
    abi: FactoryABI,
    functionName: "getCollectionOwnerById",
    args: [collectionId],
  });
}

export function useUserCollections(userAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: ADDRESSES.factory,
    abi: FactoryABI,
    functionName: "getAllAddressCollectionIds",
    args: userAddress ? [userAddress] : undefined,
  });
}

export function useCreateCollection() {
  return useWriteContract();
}
