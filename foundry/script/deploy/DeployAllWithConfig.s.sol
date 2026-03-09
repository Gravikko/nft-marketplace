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

    // Delay for network deployments (accounts for block time differences)
    uint256 internal constant EXECUTION_DELAY = 30 minutes;
    uint256 internal constant GRACE_PERIOD = 1 days;

    // ========== STORAGE CONFIG (avoids stack too deep) ==========
    address internal _deployer;
    uint256 internal _deployerPk;
    address[] internal _owners;
    uint256[] internal _ownerPks;
    uint256 internal _minApprovals;
    address internal _weth;
    address internal _vrfCoordinator;
    uint256 internal _vrfSubscriptionId;
    bytes32 internal _vrfKeyHash;
    uint32 internal _vrfCallbackGasLimit;
    uint16 internal _vrfRequestConfirmations;
    uint256 internal _marketplaceFee;
    uint256 internal _auctionFee;
    uint256 internal _stakingReward;

    // Storage for queueing transactions
    bytes32[] internal _txIds;
    uint256 internal _execTimestamp;

    // Storage for deployment addresses (used across functions)
    Deployment internal _d;

    function run() external returns (Deployment memory) {
        _loadConfig();

        bool isLocalNetwork = block.chainid == 31337;

        if (isLocalNetwork) {
            return _deployAndConfigureLocal();
        }

        uint256 phase = vm.envOr("DEPLOYMENT_PHASE", uint256(1));

        if (phase == 1) {
            return _deployAndQueueConfiguration();
        } else if (phase == 2) {
            return _executeConfiguration();
        } else {
            revert("Invalid DEPLOYMENT_PHASE. Use 1 or 2.");
        }
    }

    function _loadConfig() internal {
        _deployerPk = vm.envUint("PRIVATE_KEY");
        _deployer = vm.addr(_deployerPk);

        uint256 ownerCount = vm.envOr("OWNER_COUNT", uint256(3));
        for (uint256 i = 0; i < ownerCount; i++) {
            string memory addrKey = string(abi.encodePacked("OWNER_", vm.toString(i + 1)));
            string memory pkKey = string(abi.encodePacked("OWNER_", vm.toString(i + 1), "_PRIVATE_KEY"));
            _owners.push(vm.envAddress(addrKey));
            _ownerPks.push(vm.envUint(pkKey));
        }

        _minApprovals = vm.envOr("MIN_APPROVALS", uint256(2));
        _weth = vm.envAddress("WETH_ADDRESS");
        _vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        _vrfSubscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        _vrfKeyHash = vm.envBytes32("VRF_KEY_HASH");
        _vrfCallbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000)));
        _vrfRequestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        _marketplaceFee = vm.envOr("MARKETPLACE_FEE", uint256(250));
        _auctionFee = vm.envOr("AUCTION_FEE", uint256(250));
        _stakingReward = vm.envOr("STAKING_REWARD", uint256(1e12));
    }

    /*//////////////////////////////////////////////////////////////
                         LOCAL NETWORK DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function _deployAndConfigureLocal() internal returns (Deployment memory) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Local Deployment");
        console.log("==============================================\n");
        console.log("Deployer:", _deployer);

        vm.startBroadcast(_deployerPk);
        _deployAllContracts();

        console.log("\n--- Configuring contracts ---\n");

        // Configure Factory
        _queueConfirmExecLocal(_d.factory, abi.encodeCall(Factory.setCollectionBeaconAddress, (_d.beacon)), "Factory.setCollectionBeaconAddress");
        _queueConfirmExecLocal(_d.factory, abi.encodeCall(Factory.setVRFAdapter, (_d.vrfAdapter)), "Factory.setVRFAdapter");
        _queueConfirmExecLocal(_d.factory, abi.encodeCall(Factory.setMarketplaceAddress, (_d.marketplace)), "Factory.setMarketplaceAddress");
        _queueConfirmExecLocal(_d.factory, abi.encodeCall(Factory.activateFactory, ()), "Factory.activateFactory");

        // Configure Marketplace
        _queueConfirmExecLocal(_d.marketplace, abi.encodeCall(MarketplaceNFT.setFactoryAddress, (_d.factory)), "Marketplace.setFactoryAddress");
        _queueConfirmExecLocal(_d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeAmount, (_marketplaceFee)), "Marketplace.setMarketplaceFeeAmount");
        _queueConfirmExecLocal(_d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeReceiver, (_deployer)), "Marketplace.setMarketplaceFeeReceiver");
        _queueConfirmExecLocal(_d.marketplace, abi.encodeCall(MarketplaceNFT.activateMarketplace, ()), "Marketplace.activateMarketplace");

        // Configure Auction
        _queueConfirmExecLocal(_d.auction, abi.encodeCall(Auction.setFactoryAddress, (_d.factory)), "Auction.setFactoryAddress");
        _queueConfirmExecLocal(_d.auction, abi.encodeCall(Auction.setAuctionFeeAmount, (_auctionFee)), "Auction.setAuctionFeeAmount");
        _queueConfirmExecLocal(_d.auction, abi.encodeCall(Auction.setAuctionFeeReceiver, (_deployer)), "Auction.setAuctionFeeReceiver");
        _queueConfirmExecLocal(_d.auction, abi.encodeCall(Auction.activateAuction, ()), "Auction.activateAuction");

        // Configure Staking
        _queueConfirmExecLocal(_d.staking, abi.encodeCall(StakingNFT.setFactoryAddress, (_d.factory)), "Staking.setFactoryAddress");
        _queueConfirmExecLocal(_d.staking, abi.encodeCall(StakingNFT.setRewardAmount, (_stakingReward)), "Staking.setRewardAmount");
        _queueConfirmExecLocal(_d.staking, abi.encodeCall(StakingNFT.activateStaking, ()), "Staking.activateStaking");

        vm.stopBroadcast();

        _printSummary();
        return _d;
    }

    function _queueConfirmExecLocal(
        address target,
        bytes memory data,
        string memory description
    ) internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        bytes32 txId = multisig.addToQueue(target, data, 0, block.timestamp, GRACE_PERIOD, keccak256(bytes(description)));

        vm.stopBroadcast();

        for (uint256 i = 0; i < _minApprovals; i++) {
            vm.broadcast(_ownerPks[i]);
            multisig.confirm(txId);
        }

        vm.broadcast(_ownerPks[0]);
        multisig.executeTransaction(txId);

        vm.startBroadcast(_deployerPk);

        console.log("  [OK]", description);
    }

    /*//////////////////////////////////////////////////////////////
                      NETWORK DEPLOYMENT - PHASE 1
    //////////////////////////////////////////////////////////////*/

    function _deployAndQueueConfiguration() internal returns (Deployment memory) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Network Deployment");
        console.log("  PHASE 1: Deploy & Queue Configuration");
        console.log("==============================================\n");
        console.log("Deployer:", _deployer);

        _execTimestamp = block.timestamp + EXECUTION_DELAY;
        console.log("\nExecution will be possible after timestamp:", _execTimestamp);
        console.log("(approximately 5 minutes from now)\n");

        vm.startBroadcast(_deployerPk);
        _deployAllContracts();
        vm.stopBroadcast();

        // Queue all configuration transactions
        console.log("\n--- Queuing configuration transactions ---\n");
        _queueFactoryTxs();
        _queueMarketplaceTxs();
        _queueAuctionTxs();
        _queueStakingTxs();

        // Confirm all transactions
        _confirmAllTransactions();

        // Save deployment data for phase 2
        _saveDeploymentData();

        _printPhase1Complete();
        return _d;
    }

    function _queueFactoryTxs() internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        vm.startBroadcast(_deployerPk);
        _txIds.push(multisig.addToQueue(_d.factory, abi.encodeCall(Factory.setCollectionBeaconAddress, (_d.beacon)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setCollectionBeaconAddress")));
        _txIds.push(multisig.addToQueue(_d.factory, abi.encodeCall(Factory.setVRFAdapter, (_d.vrfAdapter)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setVRFAdapter")));
        _txIds.push(multisig.addToQueue(_d.factory, abi.encodeCall(Factory.setMarketplaceAddress, (_d.marketplace)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.setMarketplaceAddress")));
        _txIds.push(multisig.addToQueue(_d.factory, abi.encodeCall(Factory.activateFactory, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Factory.activateFactory")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Factory configuration (4 transactions)");
    }

    function _queueMarketplaceTxs() internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        vm.startBroadcast(_deployerPk);
        _txIds.push(multisig.addToQueue(_d.marketplace, abi.encodeCall(MarketplaceNFT.setFactoryAddress, (_d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(_d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeAmount, (_marketplaceFee)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setMarketplaceFeeAmount")));
        _txIds.push(multisig.addToQueue(_d.marketplace, abi.encodeCall(MarketplaceNFT.setMarketplaceFeeReceiver, (_deployer)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.setMarketplaceFeeReceiver")));
        _txIds.push(multisig.addToQueue(_d.marketplace, abi.encodeCall(MarketplaceNFT.activateMarketplace, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Marketplace.activateMarketplace")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Marketplace configuration (4 transactions)");
    }

    function _queueAuctionTxs() internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        vm.startBroadcast(_deployerPk);
        _txIds.push(multisig.addToQueue(_d.auction, abi.encodeCall(Auction.setFactoryAddress, (_d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(_d.auction, abi.encodeCall(Auction.setAuctionFeeAmount, (_auctionFee)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setAuctionFeeAmount")));
        _txIds.push(multisig.addToQueue(_d.auction, abi.encodeCall(Auction.setAuctionFeeReceiver, (_deployer)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.setAuctionFeeReceiver")));
        _txIds.push(multisig.addToQueue(_d.auction, abi.encodeCall(Auction.activateAuction, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Auction.activateAuction")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Auction configuration (4 transactions)");
    }

    function _queueStakingTxs() internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        vm.startBroadcast(_deployerPk);
        _txIds.push(multisig.addToQueue(_d.staking, abi.encodeCall(StakingNFT.setFactoryAddress, (_d.factory)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.setFactoryAddress")));
        _txIds.push(multisig.addToQueue(_d.staking, abi.encodeCall(StakingNFT.setRewardAmount, (_stakingReward)), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.setRewardAmount")));
        _txIds.push(multisig.addToQueue(_d.staking, abi.encodeCall(StakingNFT.activateStaking, ()), 0, _execTimestamp, GRACE_PERIOD, keccak256("Staking.activateStaking")));
        vm.stopBroadcast();
        console.log("  [QUEUED] Staking configuration (3 transactions)");
    }

    function _confirmAllTransactions() internal {
        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);
        console.log("\n--- Confirming transactions ---\n");
        for (uint256 i = 0; i < _minApprovals; i++) {
            vm.startBroadcast(_ownerPks[i]);
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

    function _saveDeploymentData() internal {
        string memory data = string(abi.encodePacked(
            "# Deployment data - generated by DeployAllWithConfig Phase 1\n",
            "DEPLOYED_MULTISIG=", vm.toString(_d.multisigTimelock), "\n",
            "DEPLOYED_FACTORY=", vm.toString(_d.factory), "\n",
            "DEPLOYED_MARKETPLACE=", vm.toString(_d.marketplace), "\n"
        ));
        data = string(abi.encodePacked(
            data,
            "DEPLOYED_AUCTION=", vm.toString(_d.auction), "\n",
            "DEPLOYED_STAKING=", vm.toString(_d.staking), "\n",
            "DEPLOYED_VRF_ADAPTER=", vm.toString(_d.vrfAdapter), "\n"
        ));
        data = string(abi.encodePacked(
            data,
            "DEPLOYED_BEACON=", vm.toString(_d.beacon), "\n",
            "DEPLOYED_SWAP_ADAPTER=", vm.toString(_d.swapAdapter), "\n",
            "DEPLOYED_ERC721_IMPL=", vm.toString(_d.erc721CollectionImpl), "\n",
            "EXECUTION_TIMESTAMP=", vm.toString(_execTimestamp), "\n"
        ));

        for (uint256 i = 0; i < _txIds.length; i++) {
            data = string(abi.encodePacked(data, "TX_ID_", vm.toString(i), "=", vm.toString(_txIds[i]), "\n"));
        }

        vm.writeFile("deployment-phase1.env", data);
        console.log("\nDeployment data saved to: deployment-phase1.env");
    }

    /*//////////////////////////////////////////////////////////////
                      NETWORK DEPLOYMENT - PHASE 2
    //////////////////////////////////////////////////////////////*/

    function _executeConfiguration() internal returns (Deployment memory) {
        console.log("==============================================");
        console.log("  NFT Marketplace - Network Deployment");
        console.log("  PHASE 2: Execute Configuration");
        console.log("==============================================\n");

        _d.multisigTimelock = vm.envAddress("DEPLOYED_MULTISIG");
        _d.factory = vm.envAddress("DEPLOYED_FACTORY");
        _d.marketplace = vm.envAddress("DEPLOYED_MARKETPLACE");
        _d.auction = vm.envAddress("DEPLOYED_AUCTION");
        _d.staking = vm.envAddress("DEPLOYED_STAKING");
        _d.vrfAdapter = vm.envAddress("DEPLOYED_VRF_ADAPTER");
        _d.beacon = vm.envAddress("DEPLOYED_BEACON");
        _d.swapAdapter = vm.envAddress("DEPLOYED_SWAP_ADAPTER");
        _d.erc721CollectionImpl = vm.envAddress("DEPLOYED_ERC721_IMPL");

        uint256 executionTimestamp = vm.envUint("EXECUTION_TIMESTAMP");

        console.log("MultisigTimelock:", _d.multisigTimelock);
        console.log("Execution timestamp:", executionTimestamp);
        console.log("Current timestamp:", block.timestamp);

        if (block.timestamp < executionTimestamp) {
            uint256 waitTime = executionTimestamp - block.timestamp;
            console.log("\nWARNING: Execution window not yet open!");
            console.log("Please wait approximately", waitTime, "seconds and try again.");
            revert("TooEarly: execution window not open yet");
        }

        MultisigTimelock multisig = MultisigTimelock(_d.multisigTimelock);

        console.log("\n--- Executing transactions ---\n");

        vm.startBroadcast(_ownerPks[0]);

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

        _printSummary();
        return _d;
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deployAllContracts() internal {
        console.log("--- Deploying contracts ---\n");

        // 1. MultisigTimelock
        {
            address impl = address(new MultisigTimelock());
            _d.multisigTimelock = address(
                new ERC1967Proxy(impl, abi.encodeCall(MultisigTimelock.initialize, (_owners, _minApprovals, 7 days)))
            );
        }
        console.log("1. MultisigTimelock:", _d.multisigTimelock);

        // 2. ERC721Collection implementation
        _d.erc721CollectionImpl = address(new ERC721Collection());
        console.log("2. ERC721Collection impl:", _d.erc721CollectionImpl);

        // 3. SwapAdapter
        _d.swapAdapter = address(new SwapAdapter(_weth));
        console.log("3. SwapAdapter:", _d.swapAdapter);

        // 4. VRFAdapter
        {
            address impl = address(new VRFAdapter());
            _d.vrfAdapter = address(
                new ERC1967Proxy(
                    impl,
                    abi.encodeCall(VRFAdapter.initialize, (_vrfCoordinator, _vrfSubscriptionId, _vrfKeyHash, _vrfCallbackGasLimit, _vrfRequestConfirmations))
                )
            );
        }
        console.log("4. VRFAdapter:", _d.vrfAdapter);

        // 5. Beacon
        _d.beacon = address(new ERC721CollectionBeacon(_d.erc721CollectionImpl, _d.multisigTimelock));
        console.log("5. Beacon:", _d.beacon);

        // 6. Factory
        {
            address impl = address(new Factory());
            _d.factory = address(new ERC1967Proxy(impl, abi.encodeCall(Factory.initialize, (_d.multisigTimelock))));
        }
        console.log("6. Factory:", _d.factory);

        // 7. Marketplace
        {
            address impl = address(new MarketplaceNFT());
            _d.marketplace = address(
                new ERC1967Proxy(impl, abi.encodeCall(MarketplaceNFT.initialize, (_d.multisigTimelock, _weth)))
            );
        }
        console.log("7. Marketplace:", _d.marketplace);

        // 8. Auction
        {
            address impl = address(new Auction());
            _d.auction = address(new ERC1967Proxy(impl, abi.encodeCall(Auction.initialize, (_d.multisigTimelock))));
        }
        console.log("8. Auction:", _d.auction);

        // 9. Staking
        {
            address impl = address(new StakingNFT());
            _d.staking = address(new ERC1967Proxy(impl, abi.encodeCall(StakingNFT.initialize, (_d.multisigTimelock))));
        }
        console.log("9. Staking:", _d.staking);
    }

    function _printSummary() internal view {
        console.log("\n==============================================");
        console.log("  Deployment Summary");
        console.log("==============================================\n");

        console.log("DEPLOYED ADDRESSES:");
        console.log("-------------------");
        console.log("MultisigTimelock:", _d.multisigTimelock);
        console.log("Factory:", _d.factory);
        console.log("Marketplace:", _d.marketplace);
        console.log("Auction:", _d.auction);
        console.log("Staking:", _d.staking);
        console.log("VRFAdapter:", _d.vrfAdapter);
        console.log("Beacon:", _d.beacon);
        console.log("SwapAdapter:", _d.swapAdapter);
        console.log("ERC721Collection impl:", _d.erc721CollectionImpl);

        console.log("\nMULTISIG CONFIGURATION:");
        console.log("-----------------------");
        console.log("Min Approvals:", _minApprovals);
        console.log("Owners:");
        for (uint256 i = 0; i < _owners.length; i++) {
            console.log("  ", i + 1, ":", _owners[i]);
        }

        console.log("\nCONTRACT CONFIGURATION:");
        console.log("-----------------------");
        console.log("WETH:", _weth);
        console.log("VRF Coordinator:", _vrfCoordinator);
        console.log("VRF Subscription ID:", _vrfSubscriptionId);
        console.log("Marketplace Fee:", _marketplaceFee, "bps");
        console.log("Auction Fee:", _auctionFee, "bps");

        console.log("\nNEXT STEPS:");
        console.log("-----------");
        console.log("1. Add VRFAdapter to Chainlink VRF subscription as consumer");
        console.log("2. Verify contracts on Etherscan");
    }
}
