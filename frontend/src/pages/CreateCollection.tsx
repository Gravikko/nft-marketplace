import { useState } from "react";
import { parseEther } from "viem";
import { useCreateCollection } from "../hooks/useFactory";
import FactoryABI from "../contracts/abis/Factory.json";
import { ADDRESSES } from "../contracts/addresses";
import "./CreateCollection.css";

function CreateCollection() {
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [revealType, setRevealType] = useState("instant");
  const [baseURI, setBaseURI] = useState("");
  const [placeholderURI, setPlaceholderURI] = useState("");
  const [royaltyReceiver, setRoyaltyReceiver] = useState("");
  const [royaltyFee, setRoyaltyFee] = useState(500);
  const [maxSupply, setMaxSupply] = useState(1000);
  const [mintPrice, setMintPrice] = useState("0.01");
  const [batchMintSupply, setBatchMintSupply] = useState(0);

  const { writeContract, isPending, isSuccess, error } = useCreateCollection();

  const handleCreate = () => {
    if (!name || !symbol || !baseURI) {
      alert("Fill in required fields");
      return;
    }
    if (maxSupply < 1 || maxSupply > 20000) {
      alert("Max supply must be 1-20000");
      return;
    }

    writeContract({
      address: ADDRESSES.factory,
      abi: FactoryABI,
      functionName: "createCollection",
      args: [
        {
          name,
          symbol,
          revealType,
          baseURI,
          placeholderURI,
          royaltyReceiver,
          royaltyFeeNumerator: royaltyFee,
          maxSupply,
          mintPrice: parseEther(mintPrice),
          batchMintSupply,
        },
      ],
    });
  };

  return (
    <div className="create-page">
      <div className="create-card">
        <h1 className="create-title">Create Collection</h1>
        <p className="create-subtitle">Deploy your own NFT collection on-chain</p>

        <div className="form-section">
          <h2 className="section-title">General</h2>

          <div className="form-row">
            <div className="form-group">
              <label>Name *</label>
              <input
                placeholder="My Cool NFTs"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="form-group">
              <label>Symbol *</label>
              <input
                placeholder="MCN"
                value={symbol}
                onChange={(e) => setSymbol(e.target.value)}
              />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Max Supply</label>
              <input
                type="number"
                value={maxSupply}
                onChange={(e) => setMaxSupply(Number(e.target.value))}
              />
              <span className="hint">1 - 20,000</span>
            </div>
            <div className="form-group">
              <label>Mint Price (ETH)</label>
              <input
                placeholder="0.01"
                value={mintPrice}
                onChange={(e) => setMintPrice(e.target.value)}
              />
            </div>
          </div>

          <div className="form-group">
            <label>Batch Mint Supply</label>
            <input
              type="number"
              value={batchMintSupply}
              onChange={(e) => setBatchMintSupply(Number(e.target.value))}
            />
            <span className="hint">Tokens pre-minted on creation (0 = none)</span>
          </div>
        </div>

        <div className="form-section">
          <h2 className="section-title">Metadata</h2>

          <div className="form-group">
            <label>Reveal Type</label>
            <select value={revealType} onChange={(e) => setRevealType(e.target.value)}>
              <option value="instant">Instant</option>
              <option value="delayed">Delayed (VRF)</option>
            </select>
          </div>

          <div className="form-group">
            <label>Base URI *</label>
            <input
              placeholder="ipfs://Qm..."
              value={baseURI}
              onChange={(e) => setBaseURI(e.target.value)}
            />
          </div>

          <div className="form-group">
            <label>Placeholder URI</label>
            <input
              placeholder="ipfs://Qm... (for delayed reveal)"
              value={placeholderURI}
              onChange={(e) => setPlaceholderURI(e.target.value)}
            />
          </div>
        </div>

        <div className="form-section">
          <h2 className="section-title">Royalties</h2>

          <div className="form-row">
            <div className="form-group">
              <label>Royalty Receiver</label>
              <input
                placeholder="0x..."
                value={royaltyReceiver}
                onChange={(e) => setRoyaltyReceiver(e.target.value)}
              />
            </div>
            <div className="form-group">
              <label>Royalty Fee</label>
              <input
                type="number"
                value={royaltyFee}
                onChange={(e) => setRoyaltyFee(Number(e.target.value))}
              />
              <span className="hint">{(royaltyFee / 100).toFixed(1)}% (basis points, max 1000)</span>
            </div>
          </div>
        </div>

        <button
          className="create-button"
          onClick={handleCreate}
          disabled={isPending}
        >
          {isPending ? "Creating..." : "Create Collection"}
        </button>

        {isSuccess && (
          <div className="message success">Collection created successfully!</div>
        )}
        {error && (
          <div className="message error">Error: {error.message}</div>
        )}
      </div>
    </div>
  );
}

export default CreateCollection;
