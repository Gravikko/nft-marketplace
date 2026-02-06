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

/// @title Deploy All Contracts With Auto-Configuration
/// @notice Deploys and configures entire NFT Marketplace system
/// @dev For local networks (chainid 31337): single-step deployment with immediate configuration
/// @dev For real networks: use environment variable DEPLOYMENT_PHASE:
///      - DEPLOYMENT_PHASE=1: Deploy contracts and queue configuration
///      - DEPLOYMENT_PHASE=2: Execute queued configuration (run after waiting ~5 minutes)
contract DeployAllWithConfig is Script {
    struct Deployment {
        address multisigTimelock;
        address factory;
        address marketplace;
        address auction;
        address staking;
        address vrfAdapter;
        address erc721CollectionImpl;
        address beacon;
        address swapAdapter;
    }

    struct Config {
        address deployer;
        address[] owners;
        uint256[] ownerPrivateKeys;
        uint256 minApprovals;
        address weth;
        address vrfCoordinator;
        uint256 vrfSubscriptionId;
        bytes32 vrfKeyHash;
        uint32 vrfCallbackGasLimit;
        uint16 vrfRequestConfirmations;
        uint256 marketplaceFeeAmount;
        uint256 auctionFeeAmount;
        uint256 stakingRewardAmount;
    }

    // Delay for network deployments (accounts for block time differences)
    uint256 internal constant EXECUTION_DELAY = 5 minutes;
    uint256 internal constant GRACE_PERIOD = 1 days;

    // Storage for queueing transactions (to avoid stack too deep)
    bytes32[] internal _txIds;
    uint256 internal _execTimestamp;

    function run() external returns (Deployment memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load owners from env
        uint256 ownerCount = vm.envOr("OWNER_COUNT", uint256(3));
        address[] memory owners = new address[](ownerCount);
        uint256[] memory ownerPrivateKeys = new uint256[](ownerCount);

        for (uint256 i = 0; i < ownerCount; i++) {
            string memory addrKey = string(abi.encodePacked("OWNER_", vm.toString(i + 1)));
            string memory pkKey = string(abi.encodePacked("OWNER_", vm.toString(i + 1), "_PRIVATE_KEY"));
            owners[i] = vm.envAddress(addrKey);
            ownerPrivateKeys[i] = vm.envUint(pkKey);
        }

        Config memory config = Config({
            deployer: deployer,
            owners: owners,
            ownerPrivateKeys: ownerPrivateKeys,
            minApprovals: vm.envOr("MIN_APPROVALS", uint256(2)),
            weth: vm.envAddress("WETH_ADDRESS"),
            vrfCoordinator: vm.envAddress("VRF_COORDINATOR"),
            vrfSubscriptionId: vm.envUint("VRF_SUBSCRIPTION_ID"),
            vrfKeyHash: vm.envBytes32("VRF_KEY_HASH"),
            vrfCallbackGasLimit: uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000))),
            vrfRequestConfirmations: uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3))),
            marketplaceFeeAmount: vm.envOr("MARKETPLACE_FEE", uint256(250)),
            auctionFeeAmount: vm.envOr("AUCTION_FEE", uint256(250)),
            stakingRewardAmount: vm.envOr("STAKING_REWARD", uint256(1e12))
        });

        // Check if this is a local network
        bool isLocalNetwork = block.chainid == 31337;

        if (isLocalNetwork) {
            return _deployAndConfigureLocal(config, deployerPrivateKey);
        }

        // For real networks, check deployment phase
        uint256 phase = vm.envOr("DEPLOYMENT_PHASE", uint256(1));

        if (phase == 1) {
            return _deployAndQueueConfiguration(config, deployerPrivateKey);
        } else if (phase == 2) {
            return _executeConfiguration(config);
        } else {
            revert("Invalid DEPLOYMENT_PHASE. Use 1 or 2.");
        }
    }

    /*//////////////////////////////////////////////////////////////
                         LOCAL NETWORK DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function _deployAndConfigureLocal(
        Config memory config,
        uint256 deployerPrivateKey
    ) internal returns (Deployment memory d) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Local Deployment");
        console.log("==============================================\n");
        console.log("Deployer:", config.deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy all contracts
        d = _deployContracts(config);

        // Configure immediately (local network has consistent timestamps)
        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);

        console.log("\n--- Configuring contracts ---\n");

        // Configure Factory
        _queueConfirmExecuteLocal(multisig, d.factory, abi.encodeCall(Factory.setCollectionBeaconAddress, (d.beacon)), "Factory.setCollectionBeaconAddress", config);
        _queueConfirmExecuteLocal(multisig, d.factory, abi.encodeCall(Factory.setVRFAdapter, (d.vrfAdapter)), "Factory.setVRFAdapter", config);
        _queueConfirmExecuteLocal(multisig, d.factory, abi.encodeCall(Factory.setMarketplaceAddress, (d.marketplace)), "Factory.setMarketplaceAddress", config);
        _queueConfirmExecuteLocal(multisig, d.factory, abi.encodeCall(Factory.activateFactory, ()), "Factory.activateFactory", config);

        // Configure Marketplace
        _queueConfirmExecuteLocal(multisig, d.marketplace, abi.encodeCall(MarketplaceNFT.setFactoryAddress, (d.factory)), "Marketplace.setFactoryAddress", config);
        _queueConfirmExecuteLocal(multisig, d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeAmount, (config.marketplaceFeeAmount)), "Marketplace.setMarketplaceFeeAmount", config);
        _queueConfirmExecuteLocal(multisig, d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeReceiver, (config.deployer)), "Marketplace.setMarketplaceFeeReceiver", config);
        _queueConfirmExecuteLocal(multisig, d.marketplace, abi.encodeCall(MarketplaceNFT.activateMarketplace, ()), "Marketplace.activateMarketplace", config);

        // Configure Auction
        _queueConfirmExecuteLocal(multisig, d.auction, abi.encodeCall(Auction.setFactoryAddress, (d.factory)), "Auction.setFactoryAddress", config);
        _queueConfirmExecuteLocal(multisig, d.auction, abi.encodeCall(Auction.setAuctionFeeAmount, (config.auctionFeeAmount)), "Auction.setAuctionFeeAmount", config);
        _queueConfirmExecuteLocal(multisig, d.auction, abi.encodeCall(Auction.setAuctionFeeReceiver, (config.deployer)), "Auction.setAuctionFeeReceiver", config);
        _queueConfirmExecuteLocal(multisig, d.auction, abi.encodeCall(Auction.activateAuction, ()), "Auction.activateAuction", config);

        // Configure Staking
        _queueConfirmExecuteLocal(multisig, d.staking, abi.encodeCall(StakingNFT.setFactoryAddress, (d.factory)), "Staking.setFactoryAddress", config);
        _queueConfirmExecuteLocal(multisig, d.staking, abi.encodeCall(StakingNFT.setRewardAmount, (config.stakingRewardAmount)), "Staking.setRewardAmount", config);
        _queueConfirmExecuteLocal(multisig, d.staking, abi.encodeCall(StakingNFT.activateStaking, ()), "Staking.activateStaking", config);

        vm.stopBroadcast();

        _printSummary(d, config);
        return d;
    }

    function _queueConfirmExecuteLocal(
        MultisigTimelock multisig,
        address target,
        bytes memory data,
        string memory description,
        Config memory config
    ) internal {
        bytes32 txId = multisig.addToQueue(target, data, 0, block.timestamp, GRACE_PERIOD, keccak256(bytes(description)));

        vm.stopBroadcast();

        for (uint256 i = 0; i < config.minApprovals; i++) {
            vm.broadcast(config.ownerPrivateKeys[i]);
            multisig.confirm(txId);
        }

        vm.broadcast(config.ownerPrivateKeys[0]);
        multisig.executeTransaction(txId);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        console.log("  [OK]", description);
    }

    /*//////////////////////////////////////////////////////////////
                      NETWORK DEPLOYMENT - PHASE 1
    //////////////////////////////////////////////////////////////*/

    function _deployAndQueueConfiguration(
        Config memory config,
        uint256 deployerPrivateKey
    ) internal returns (Deployment memory d) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Network Deployment");
        console.log("  PHASE 1: Deploy & Queue Configuration");
        console.log("==============================================\n");
        console.log("Deployer:", config.deployer);

        // Calculate execution timestamp and store in storage
        _execTimestamp = block.timestamp + EXECUTION_DELAY;
        console.log("\nExecution will be possible after timestamp:", _execTimestamp);
        console.log("(approximately 5 minutes from now)\n");

        vm.startBroadcast(deployerPrivateKey);
        d = _deployContracts(config);
        vm.stopBroadcast();

        // Queue all configuration transactions
        console.log("\n--- Queuing configuration transactions ---\n");
        _queueFactoryTxs(d);
        _queueMarketplaceTxs(d, config);
        _queueAuctionTxs(d, config);
        _queueStakingTxs(d, config);

        // Confirm all transactions
        _confirmAllTransactions(d.multisigTimelock, config);

        // Save deployment addresses and txIds to file for phase 2
        _saveDeploymentData(d);

        _printPhase1Complete();
        return d;
    }

    function _queueFactoryTxs(Deployment memory d) internal {
        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _txIds.push(multisig.addToQueue(d.factory, abi.encodeCall(Factory.setCollectionBeaconAddress, (d.beacon)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setCollectionBeaconAddress")));
        _txIds.push(multisig.addToQueue(d.factory, abi.encodeCall(Factory.setVRFAdapter, (d.vrfAdapter)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setVRFAdapter")));
        _txIds.push(multisig.addToQueue(d.factory, abi.encodeCall(Factory.setMarketplaceAddress, (d.marketplace)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setMarketplaceAddress")));
        _txIds.push(multisig.addToQueue(d.factory, abi.encodeCall(Factory.activateFactory, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.activateFactory")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Factory configuration (4 transactions)");
    }

    function _queueMarketplaceTxs(Deployment memory d, Config memory config) internal {
        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _txIds.push(multisig.addToQueue(d.marketplace, abi.encodeCall(MarketplaceNFT.setFactoryAddress, (d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeAmount, (config.marketplaceFeeAmount)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setMarketplaceFeeAmount")));
        _txIds.push(multisig.addToQueue(d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeReceiver, (config.deployer)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setMarketplaceFeeReceiver")));
        _txIds.push(multisig.addToQueue(d.marketplace, abi.encodeCall(MarketplaceNFT.activateMarketplace, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.activateMarketplace")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Marketplace configuration (4 transactions)");
    }

    function _queueAuctionTxs(Deployment memory d, Config memory config) internal {
        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _txIds.push(multisig.addToQueue(d.auction, abi.encodeCall(Auction.setFactoryAddress, (d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(d.auction, abi.encodeCall(Auction.setAuctionFeeAmount, (config.auctionFeeAmount)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setAuctionFeeAmount")));
        _txIds.push(multisig.addToQueue(d.auction, abi.encodeCall(Auction.setAuctionFeeReceiver, (config.deployer)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setAuctionFeeReceiver")));
        _txIds.push(multisig.addToQueue(d.auction, abi.encodeCall(Auction.activateAuction, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.activateAuction")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Auction configuration (4 transactions)");
    }

    function _queueStakingTxs(Deployment memory d, Config memory config) internal {
        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _txIds.push(multisig.addToQueue(d.staking, abi.encodeCall(StakingNFT.setFactoryAddress, (d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(d.staking, abi.encodeCall(StakingNFT.setRewardAmount, (config.stakingRewardAmount)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.setRewardAmount")));
        _txIds.push(multisig.addToQueue(d.staking, abi.encodeCall(StakingNFT.activateStaking, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.activateStaking")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Staking configuration (3 transactions)");
    }

    function _confirmAllTransactions(address multisigAddr, Config memory config) internal {
        MultisigTimelock multisig = MultisigTimelock(multisigAddr);
        console.log("\n--- Confirming transactions ---\n");
        for (uint256 i = 0; i < config.minApprovals; i++) {
            vm.startBroadcast(config.ownerPrivateKeys[i]);
            for (uint256 j = 0; j < _txIds.length; j++) {
                multisig.confirm(_txIds[j]);
            }
            vm.stopBroadcast();
            console.log("  Owner", i + 1, "confirmed all transactions");
        }
    }

    function _printPhase1Complete() internal pure {
        console.log("\n==============================================");
        console.log("  PHASE 1 COMPLETE");
        console.log("==============================================\n");
        console.log("Contracts deployed and configuration queued.");
        console.log("\nNEXT STEPS:");
        console.log("1. Wait approximately 5 minutes");
        console.log("2. Run phase 2 to execute configuration:");
        console.log("");
        console.log("   DEPLOYMENT_PHASE=2 forge script script/deploy/DeployAllWithConfig.s.sol \\");
        console.log("     --rpc-url $RPC_URL --broadcast");
        console.log("");
    }

    function _saveDeploymentData(Deployment memory d) internal {
        // Save to environment-style format for easy loading
        string memory data = string(abi.encodePacked(
            "# Deployment data - generated by DeployAllWithConfig Phase 1\n",
            "DEPLOYED_MULTISIG=", vm.toString(d.multisigTimelock), "\n",
            "DEPLOYED_FACTORY=", vm.toString(d.factory), "\n",
            "DEPLOYED_MARKETPLACE=", vm.toString(d.marketplace), "\n",
            "DEPLOYED_AUCTION=", vm.toString(d.auction), "\n",
            "DEPLOYED_STAKING=", vm.toString(d.staking), "\n",
            "DEPLOYED_VRF_ADAPTER=", vm.toString(d.vrfAdapter), "\n",
            "DEPLOYED_BEACON=", vm.toString(d.beacon), "\n",
            "DEPLOYED_SWAP_ADAPTER=", vm.toString(d.swapAdapter), "\n",
            "DEPLOYED_ERC721_IMPL=", vm.toString(d.erc721CollectionImpl), "\n",
            "EXECUTION_TIMESTAMP=", vm.toString(_execTimestamp), "\n"
        ));

        // Add transaction IDs
        for (uint256 i = 0; i < _txIds.length; i++) {
            data = string(abi.encodePacked(data, "TX_ID_", vm.toString(i), "=", vm.toString(_txIds[i]), "\n"));
        }

        vm.writeFile("deployment-phase1.env", data);
        console.log("\nDeployment data saved to: deployment-phase1.env");
    }

    /*//////////////////////////////////////////////////////////////
                      NETWORK DEPLOYMENT - PHASE 2
    //////////////////////////////////////////////////////////////*/

    function _executeConfiguration(Config memory config) internal returns (Deployment memory d) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Network Deployment");
        console.log("  PHASE 2: Execute Configuration");
        console.log("==============================================\n");

        // Load deployment data from phase 1
        d.multisigTimelock = vm.envAddress("DEPLOYED_MULTISIG");
        d.factory = vm.envAddress("DEPLOYED_FACTORY");
        d.marketplace = vm.envAddress("DEPLOYED_MARKETPLACE");
        d.auction = vm.envAddress("DEPLOYED_AUCTION");
        d.staking = vm.envAddress("DEPLOYED_STAKING");
        d.vrfAdapter = vm.envAddress("DEPLOYED_VRF_ADAPTER");
        d.beacon = vm.envAddress("DEPLOYED_BEACON");
        d.swapAdapter = vm.envAddress("DEPLOYED_SWAP_ADAPTER");
        d.erc721CollectionImpl = vm.envAddress("DEPLOYED_ERC721_IMPL");

        uint256 executionTimestamp = vm.envUint("EXECUTION_TIMESTAMP");

        console.log("MultisigTimelock:", d.multisigTimelock);
        console.log("Execution timestamp:", executionTimestamp);
        console.log("Current timestamp:", block.timestamp);

        if (block.timestamp < executionTimestamp) {
            uint256 waitTime = executionTimestamp - block.timestamp;
            console.log("\nWARNING: Execution window not yet open!");
            console.log("Please wait approximately", waitTime, "seconds and try again.");
            revert("TooEarly: execution window not open yet");
        }

        MultisigTimelock multisig = MultisigTimelock(d.multisigTimelock);

        // Load and execute all transaction IDs
        console.log("\n--- Executing transactions ---\n");

        vm.startBroadcast(config.ownerPrivateKeys[0]);

        for (uint256 i = 0; i < 15; i++) {
            string memory key = string(abi.encodePacked("TX_ID_", vm.toString(i)));
            bytes32 txId = vm.envBytes32(key);

            if (multisig.isQueued(txId)) {
                multisig.executeTransaction(txId);
                console.log("  [EXECUTED] Transaction", i);
            } else {
                console.log("  [SKIPPED] Transaction", i, "- not queued or already executed");
            }
        }

        vm.stopBroadcast();

        console.log("\n==============================================");
        console.log("  PHASE 2 COMPLETE - Deployment Finished!");
        console.log("==============================================\n");

        _printSummary(d, config);
        return d;
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deployContracts(Config memory config) internal returns (Deployment memory d) {
        console.log("--- Deploying contracts ---\n");

        // 1. MultisigTimelock with configured owners
        address multisigImpl = address(new MultisigTimelock());
        d.multisigTimelock = address(
            new ERC1967Proxy(
                multisigImpl,
                abi.encodeCall(MultisigTimelock.initialize, (config.owners, config.minApprovals, 7 days))
            )
        );
        console.log("1. MultisigTimelock:", d.multisigTimelock);
        console.log("   Owners:", config.owners.length);
        console.log("   Min Approvals:", config.minApprovals);

        // 2. ERC721Collection implementation
        d.erc721CollectionImpl = address(new ERC721Collection());
        console.log("2. ERC721Collection impl:", d.erc721CollectionImpl);

        // 3. SwapAdapter
        d.swapAdapter = address(new SwapAdapter(config.weth));
        console.log("3. SwapAdapter:", d.swapAdapter);

        // 4. VRFAdapter
        address vrfAdapterImpl = address(new VRFAdapter());
        d.vrfAdapter = address(
            new ERC1967Proxy(
                vrfAdapterImpl,
                abi.encodeCall(
                    VRFAdapter.initialize,
                    (config.vrfCoordinator, config.vrfSubscriptionId, config.vrfKeyHash, config.vrfCallbackGasLimit, config.vrfRequestConfirmations)
                )
            )
        );
        console.log("4. VRFAdapter:", d.vrfAdapter);

        // 5. Beacon
        d.beacon = address(new ERC721CollectionBeacon(d.erc721CollectionImpl, d.multisigTimelock));
        console.log("5. Beacon:", d.beacon);

        // 6. Factory
        address factoryImpl = address(new Factory());
        d.factory = address(
            new ERC1967Proxy(factoryImpl, abi.encodeCall(Factory.initialize, (d.multisigTimelock)))
        );
        console.log("6. Factory:", d.factory);

        // 7. Marketplace
        address marketplaceImpl = address(new MarketplaceNFT());
        d.marketplace = address(
            new ERC1967Proxy(
                marketplaceImpl,
                abi.encodeCall(MarketplaceNFT.initialize, (d.multisigTimelock, config.weth))
            )
        );
        console.log("7. Marketplace:", d.marketplace);

        // 8. Auction
        address auctionImpl = address(new Auction());
        d.auction = address(
            new ERC1967Proxy(auctionImpl, abi.encodeCall(Auction.initialize, (d.multisigTimelock)))
        );
        console.log("8. Auction:", d.auction);

        // 9. Staking
        address stakingImpl = address(new StakingNFT());
        d.staking = address(
            new ERC1967Proxy(stakingImpl, abi.encodeCall(StakingNFT.initialize, (d.multisigTimelock)))
        );
        console.log("9. Staking:", d.staking);
    }

    function _printSummary(Deployment memory d, Config memory config) internal pure {
        console.log("\n==============================================");
        console.log("  Deployment Summary");
        console.log("==============================================\n");

        console.log("DEPLOYED ADDRESSES:");
        console.log("-------------------");
        console.log("MultisigTimelock:", d.multisigTimelock);
        console.log("Factory:", d.factory);
        console.log("Marketplace:", d.marketplace);
        console.log("Auction:", d.auction);
        console.log("Staking:", d.staking);
        console.log("VRFAdapter:", d.vrfAdapter);
        console.log("Beacon:", d.beacon);
        console.log("SwapAdapter:", d.swapAdapter);
        console.log("ERC721Collection impl:", d.erc721CollectionImpl);

        console.log("\nMULTISIG CONFIGURATION:");
        console.log("-----------------------");
        console.log("Min Approvals:", config.minApprovals);
        console.log("Owners:");
        for (uint256 i = 0; i < config.owners.length; i++) {
            console.log("  ", i + 1, ":", config.owners[i]);
        }

        console.log("\nCONTRACT CONFIGURATION:");
        console.log("-----------------------");
        console.log("WETH:", config.weth);
        console.log("VRF Coordinator:", config.vrfCoordinator);
        console.log("VRF Subscription ID:", config.vrfSubscriptionId);
        console.log("Marketplace Fee:", config.marketplaceFeeAmount, "bps");
        console.log("Auction Fee:", config.auctionFeeAmount, "bps");

        console.log("\nNEXT STEPS:");
        console.log("-----------");
        console.log("1. Add VRFAdapter to Chainlink VRF subscription as consumer");
        console.log("2. Verify contracts on Etherscan");
    }
}
