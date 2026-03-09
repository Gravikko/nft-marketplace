import { sepolia } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";

export const config = getDefaultConfig({
  appName: "NFT Marketplace",
  projectId: "73d15791c604b548d31fa5e024399266", // ← замени на свой с cloud.walletconnect.com
  chains: [sepolia],
});
