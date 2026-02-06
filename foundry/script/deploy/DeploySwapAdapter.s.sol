// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwapAdapter} from "../../src/SwapAdapter.sol";

/// @title Deploy SwapAdapter
/// @notice Deploys SwapAdapter for ETH/WETH swaps
contract DeploySwapAdapter is Script {
    // Common WETH addresses
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;

    function run() external returns (address swapAdapter) {
        address weth = vm.envAddress("WETH_ADDRESS");
        return deploy(weth);
    }

    function deploy(address weth) public returns (address swapAdapter) {
        require(weth != address(0), "WETH address required");

        vm.startBroadcast();

        swapAdapter = address(new SwapAdapter(weth));
        console.log("SwapAdapter:", swapAdapter);

        vm.stopBroadcast();
    }
}
