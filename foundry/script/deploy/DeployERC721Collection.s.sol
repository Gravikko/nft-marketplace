// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";

/// @title Deploy ERC721Collection Implementation
/// @notice Deploys ERC721Collection implementation (no proxy - used by beacon)
contract DeployERC721Collection is Script {
    function run() external returns (address implementation) {
        return deploy();
    }

    function deploy() public returns (address implementation) {
        vm.startBroadcast();

        implementation = address(new ERC721Collection());
        console.log("ERC721Collection implementation:", implementation);

        vm.stopBroadcast();
    }
}
