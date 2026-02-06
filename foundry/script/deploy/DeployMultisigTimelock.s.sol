// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MultisigTimelock} from "../../src/MultisigTimelock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy MultisigTimelock
/// @notice Deploys MultisigTimelock with UUPS proxy
contract DeployMultisigTimelock is Script {
    function run() external returns (address proxy, address implementation) {
        // Default config - override in child contracts or via environment
        address[] memory owners = new address[](3);
        owners[0] = vm.envOr("OWNER_1", vm.addr(1));
        owners[1] = vm.envOr("OWNER_2", vm.addr(2));
        owners[2] = vm.envOr("OWNER_3", vm.addr(3));

        uint256 minApprovals = vm.envOr("MIN_APPROVALS", uint256(2));
        uint256 maxDelay = vm.envOr("MAX_DELAY", uint256(7 days));

        return deploy(owners, minApprovals, maxDelay);
    }

    function deploy(
        address[] memory owners,
        uint256 minApprovals,
        uint256 maxDelay
    ) public returns (address proxy, address implementation) {
        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new MultisigTimelock());
        console.log("MultisigTimelock implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            MultisigTimelock.initialize.selector,
            owners,
            minApprovals,
            maxDelay
        );
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("MultisigTimelock proxy:", proxy);

        vm.stopBroadcast();
    }
}
