// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Contracts
import {MultisigTimelock} from "../../src/MultisigTimelock.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {ERC721CollectionBeacon} from "../../src/ERC721CollectionBeacon.sol";
import {SwapAdapter} from "../../src/SwapAdapter.sol";
import {VRFAdapter} from "../../src/VRFAdapter.sol";
import {Factory} from "../../src/Factory.sol";
import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {Auction} from "../../src/Auction.sol";
import {StakingNFT} from "../../src/Staking.sol";

/// @title Deploy All Contracts
/// @notice Deploys entire NFT Marketplace system in correct order
contract DeployAll is Script {
    // Deployment result struct
    struct Deployment {
        // Proxies (main addresses to interact with)
        address multisigTimelock;
        address factory;
        address marketplace;
        address auction;
        address staking;
        address vrfAdapter;
        // Non-proxy contracts
        address erc721CollectionImpl;
        address beacon;
        address swapAdapter;
        // Implementations (for verification)
        address multisigTimelockImpl;
        address factoryImpl;
        address marketplaceImpl;
        address auctionImpl;
        address stakingImpl;
        address vrfAdapterImpl;
    }

    // Configuration struct
    struct Config {
        // MultisigTimelock config
        address[] owners;
        uint256 minApprovals;
        uint256 maxDelay;
        // External addresses
        address weth;
        address vrfCoordinator;
        // VRF config
        uint256 vrfSubscriptionId;
        bytes32 vrfKeyHash;
        uint32 vrfCallbackGasLimit;
        uint16 vrfRequestConfirmations;
        // Fee config
        uint256 marketplaceFeeAmount;
        address marketplaceFeeReceiver;
        uint256 auctionFeeAmount;
        address auctionFeeReceiver;
        uint256 stakingRewardAmount;
    }

    function run() external returns (Deployment memory) {
        Config memory config = _loadConfig();
        return deploy(config);
    }

    function deploy(Config memory config) public returns (Deployment memory d) {
        console.log("========================================");
        console.log("  NFT Marketplace Deployment Started");
        console.log("========================================\n");

        vm.startBroadcast();

        // ============================================
        // PHASE 1: Base contracts (no dependencies)
        // ============================================
        console.log("PHASE 1: Deploying base contracts...\n");

        // 1. MultisigTimelock
        d.multisigTimelockImpl = address(new MultisigTimelock());
        d.multisigTimelock = address(
            new ERC1967Proxy(
                d.multisigTimelockImpl,
                abi.encodeWithSelector(
                    MultisigTimelock.initialize.selector,
                    config.owners,
                    config.minApprovals,
                    config.maxDelay
                )
            )
        );
        console.log("1. MultisigTimelock proxy:", d.multisigTimelock);

        // 2. ERC721Collection implementation
        d.erc721CollectionImpl = address(new ERC721Collection());
        console.log("2. ERC721Collection impl:", d.erc721CollectionImpl);

        // 3. SwapAdapter
        d.swapAdapter = address(new SwapAdapter(config.weth));
        console.log("3. SwapAdapter:", d.swapAdapter);

        // 4. VRFAdapter
        d.vrfAdapterImpl = address(new VRFAdapter());
        d.vrfAdapter = address(
            new ERC1967Proxy(
                d.vrfAdapterImpl,
                abi.encodeWithSelector(
                    VRFAdapter.initialize.selector,
                    config.vrfCoordinator,
                    config.vrfSubscriptionId,
                    config.vrfKeyHash,
                    config.vrfCallbackGasLimit,
                    config.vrfRequestConfirmations
                )
            )
        );
        console.log("4. VRFAdapter proxy:", d.vrfAdapter);

        // ============================================
        // PHASE 2: Beacon and Factory
        // ============================================
        console.log("\nPHASE 2: Deploying beacon and factory...\n");

        // 5. ERC721CollectionBeacon
        d.beacon = address(new ERC721CollectionBeacon(d.erc721CollectionImpl, d.multisigTimelock));
        console.log("5. ERC721CollectionBeacon:", d.beacon);

        // 6. Factory
        d.factoryImpl = address(new Factory());
        d.factory = address(
            new ERC1967Proxy(
                d.factoryImpl,
                abi.encodeWithSelector(Factory.initialize.selector, d.multisigTimelock)
            )
        );
        console.log("6. Factory proxy:", d.factory);

        // ============================================
        // PHASE 3: Marketplace, Auction, Staking
        // ============================================
        console.log("\nPHASE 3: Deploying marketplace, auction, staking...\n");

        // 7. Marketplace
        d.marketplaceImpl = address(new MarketplaceNFT());
        d.marketplace = address(
            new ERC1967Proxy(
                d.marketplaceImpl,
                abi.encodeWithSelector(
                    MarketplaceNFT.initialize.selector,
                    d.multisigTimelock,
                    config.weth
                )
            )
        );
        console.log("7. Marketplace proxy:", d.marketplace);

        // 8. Auction
        d.auctionImpl = address(new Auction());
        d.auction = address(
            new ERC1967Proxy(
                d.auctionImpl,
                abi.encodeWithSelector(Auction.initialize.selector, d.multisigTimelock)
            )
        );
        console.log("8. Auction proxy:", d.auction);

        // 9. Staking
        d.stakingImpl = address(new StakingNFT());
        d.staking = address(
            new ERC1967Proxy(
                d.stakingImpl,
                abi.encodeWithSelector(StakingNFT.initialize.selector, d.multisigTimelock)
            )
        );
        console.log("9. Staking proxy:", d.staking);

        vm.stopBroadcast();

        // ============================================
        // PHASE 4: Configuration (requires multisig)
        // ============================================
        console.log("\n========================================");
        console.log("  Deployment Complete!");
        console.log("========================================\n");

        _printConfigurationInstructions(d, config);

        return d;
    }

    function _loadConfig() internal view returns (Config memory config) {
        // Load owners from env or use defaults for testing
        uint256 ownerCount = vm.envOr("OWNER_COUNT", uint256(3));
        config.owners = new address[](ownerCount);

        for (uint256 i = 0; i < ownerCount; i++) {
            string memory key = string(abi.encodePacked("OWNER_", vm.toString(i + 1)));
            config.owners[i] = vm.envOr(key, vm.addr(i + 1));
        }

        // MultisigTimelock config
        config.minApprovals = vm.envOr("MIN_APPROVALS", uint256(2));
        config.maxDelay = vm.envOr("MAX_DELAY", uint256(7 days));

        // External addresses
        config.weth = vm.envAddress("WETH_ADDRESS");
        config.vrfCoordinator = vm.envAddress("VRF_COORDINATOR");

        // VRF config
        config.vrfSubscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        config.vrfKeyHash = vm.envBytes32("VRF_KEY_HASH");
        config.vrfCallbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000)));
        config.vrfRequestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));

        // Fee config
        config.marketplaceFeeAmount = vm.envOr("MARKETPLACE_FEE", uint256(250)); // 2.5%
        config.marketplaceFeeReceiver = vm.envOr("MARKETPLACE_FEE_RECEIVER", config.owners[0]);
        config.auctionFeeAmount = vm.envOr("AUCTION_FEE", uint256(250)); // 2.5%
        config.auctionFeeReceiver = vm.envOr("AUCTION_FEE_RECEIVER", config.owners[0]);
        config.stakingRewardAmount = vm.envOr("STAKING_REWARD", uint256(1e12)); // per second
    }

    function _printConfigurationInstructions(Deployment memory d, Config memory config) internal pure {
        console.log("PHASE 4: Manual Configuration Required");
        console.log("--------------------------------------");
        console.log("The following transactions must be executed via MultisigTimelock:\n");

        console.log("1. Configure Factory:");
        console.log("   - setCollectionBeaconAddress(%s)", d.beacon);
        console.log("   - setVRFAdapter(%s)", d.vrfAdapter);
        console.log("   - setMarketplaceAddress(%s)", d.marketplace);
        console.log("   - activateFactory()\n");

        console.log("2. Configure Marketplace:");
        console.log("   - setFactoryAddress(%s)", d.factory);
        console.log("   - setMarketplaceFeeAmount(%s)", config.marketplaceFeeAmount);
        console.log("   - setMarketplaceFeeReceiver(%s)", config.marketplaceFeeReceiver);
        console.log("   - activateMarketplace()\n");

        console.log("3. Configure Auction:");
        console.log("   - setFactoryAddress(%s)", d.factory);
        console.log("   - setAuctionFeeAmount(%s)", config.auctionFeeAmount);
        console.log("   - setAuctionFeeReceiver(%s)", config.auctionFeeReceiver);
        console.log("   - activateAuction()\n");

        console.log("4. Configure Staking:");
        console.log("   - setFactoryAddress(%s)", d.factory);
        console.log("   - setRewardAmount(%s)", config.stakingRewardAmount);
        console.log("   - activateStaking()\n");

        console.log("5. Add VRF consumer to Chainlink subscription");
        console.log("   - VRFAdapter address: %s\n", d.vrfAdapter);
    }
}
