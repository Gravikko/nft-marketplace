// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy Marketplace
/// @notice Deploys MarketplaceNFT with UUPS proxy
contract DeployMarketplace is Script {
    function run() external returns (address proxy, address implementation) {
        address multisigTimelock = vm.envAddress("MULTISIG_TIMELOCK");
        address factory = vm.envAddress("FACTORY");
        address weth = vm.envAddress("WETH_ADDRESS");
        address swapAdapter = vm.envAddress("SWAP_ADAPTER");

        return deploy(multisigTimelock, factory, weth, swapAdapter);
    }

    function deploy(
        address multisigTimelock,
        address factory,
        address weth,
        address swapAdapter
    ) public returns (address proxy, address implementation) {
        require(multisigTimelock != address(0), "MultisigTimelock address required");
        require(factory != address(0), "Factory address required");
        require(weth != address(0), "WETH address required");
        require(swapAdapter != address(0), "SwapAdapter address required");

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new MarketplaceNFT());
        console.log("Marketplace implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            MarketplaceNFT.initialize.selector,
            multisigTimelock,
            factory,
            weth,
            swapAdapter
        );
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("Marketplace proxy:", proxy);

        vm.stopBroadcast();
    }
}
