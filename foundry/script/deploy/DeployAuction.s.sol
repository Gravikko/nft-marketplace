// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Auction} from "../../src/Auction.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy Auction
/// @notice Deploys Auction with UUPS proxy
contract DeployAuction is Script {
    function run() external returns (address proxy, address implementation) {
        address multisigTimelock = vm.envAddress("MULTISIG_TIMELOCK");
        return deploy(multisigTimelock);
    }

    function deploy(address multisigTimelock) public returns (address proxy, address implementation) {
        require(multisigTimelock != address(0), "MultisigTimelock address required");

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new Auction());
        console.log("Auction implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(Auction.initialize.selector, multisigTimelock);
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("Auction proxy:", proxy);

        vm.stopBroadcast();
    }
}
