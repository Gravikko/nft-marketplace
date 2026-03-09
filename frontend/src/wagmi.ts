import { sepolia } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";

export const config = getDefaultConfig({
  appName: "NFT Marketplace",
  projectId: "PROJECT_ID",
  chains: [sepolia],
});
