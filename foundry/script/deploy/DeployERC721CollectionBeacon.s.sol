// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC721CollectionBeacon} from "../../src/ERC721CollectionBeacon.sol";

/// @title Deploy ERC721CollectionBeacon
/// @notice Deploys beacon pointing to ERC721Collection implementation
contract DeployERC721CollectionBeacon is Script {
    function run() external returns (address beacon) {
        address implementation = vm.envAddress("ERC721_IMPLEMENTATION");
        address multisigTimelock = vm.envAddress("MULTISIG_TIMELOCK");

        return deploy(implementation, multisigTimelock);
    }

    function deploy(
        address implementation,
        address multisigTimelock
    ) public returns (address beacon) {
        require(implementation != address(0), "Implementation address required");
        require(multisigTimelock != address(0), "MultisigTimelock address required");

        vm.startBroadcast();

        beacon = address(new ERC721CollectionBeacon(implementation, multisigTimelock));
        console.log("ERC721CollectionBeacon:", beacon);

        vm.stopBroadcast();
    }
}
