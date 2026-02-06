// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VRFAdapter} from "../../src/VRFAdapter.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy VRFAdapter
/// @notice Deploys VRFAdapter with UUPS proxy for Chainlink VRF v2.5
contract DeployVRFAdapter is Script {
    // Chainlink VRF Coordinators
    address constant VRF_COORDINATOR_MAINNET = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    address constant VRF_COORDINATOR_SEPOLIA = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    address constant VRF_COORDINATOR_ARBITRUM = 0x3C0Ca683b403E37668AE3DC4FB62F4B29B6f7a3e;

    function run() external returns (address proxy, address implementation) {
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));

        return deploy(vrfCoordinator, subscriptionId, keyHash, callbackGasLimit, requestConfirmations);
    }

    function deploy(
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) public returns (address proxy, address implementation) {
        require(vrfCoordinator != address(0), "VRF Coordinator address required");

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new VRFAdapter());
        console.log("VRFAdapter implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            VRFAdapter.initialize.selector,
            vrfCoordinator,
            subscriptionId,
            keyHash,
            callbackGasLimit,
            requestConfirmations
        );
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("VRFAdapter proxy:", proxy);

        vm.stopBroadcast();
    }
}
