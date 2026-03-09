import { useAccount } from 'wagmi'
import {useUserCollections, useCollectionAddress} from "../hooks/useFactory" 
import {useSupply} from "../hooks/useCollection";
interface CollectionCardProps {
    collectionId: number;
}
export function CollectionCard({collectionId} : CollectionCardProps) {
    const collectionAddress = useCollectionAddress(collectionId);
    const {supply, isLoading, isError} = useSupply(collectionAddress);
}

function CollectionsPage() {
  const account = useAccount();
  const {data: collectionIds, isLoading} = useUserCollections(account.address);

  return (
    <div>
      <h1>My Collections</h1>
      {collectionIds?.map((id) => (
        <CollectionCard key={id} collectionId={id} />
      ))}
    </div>
  );
  

 
}

export default CollectionsPage;
