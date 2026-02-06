// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DeployAll} from "./DeployAll.s.sol";

/// @title Deploy to Local Anvil
/// @notice Deploys entire system to local Anvil with mock configurations
/// @dev Run: anvil (in terminal 1)
/// @dev Run: forge script script/deploy/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast (in terminal 2)
contract DeployLocal is Script {
    // Mock WETH for local testing
    address constant MOCK_WETH = address(0x1234567890123456789012345678901234567890);

    function run() external {
        // Create config for local deployment
        DeployAll.Config memory config;

        // MultisigTimelock owners (Anvil accounts 0, 1, 2)
        config.owners = new address[](3);
        config.owners[0] = vm.addr(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        config.owners[1] = vm.addr(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d);
        config.owners[2] = vm.addr(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a);

        config.minApprovals = 2;
        config.maxDelay = 7 days;

        // Deploy mock WETH first
        vm.startBroadcast();
        MockWETH weth = new MockWETH();
        vm.stopBroadcast();

        config.weth = address(weth);

        // Deploy mock VRF Coordinator
        vm.startBroadcast();
        MockVRFCoordinator vrfCoordinator = new MockVRFCoordinator();
        vm.stopBroadcast();

        config.vrfCoordinator = address(vrfCoordinator);
        config.vrfSubscriptionId = 1;
        config.vrfKeyHash = bytes32(uint256(1));
        config.vrfCallbackGasLimit = 500000;
        config.vrfRequestConfirmations = 3;

        // Fee config
        config.marketplaceFeeAmount = 250; // 2.5%
        config.marketplaceFeeReceiver = config.owners[0];
        config.auctionFeeAmount = 250; // 2.5%
        config.auctionFeeReceiver = config.owners[0];
        config.stakingRewardAmount = 1e12; // wei per second

        // Deploy all contracts
        DeployAll deployer_script = new DeployAll();
        DeployAll.Deployment memory d = deployer_script.deploy(config);

        // Print summary
        console.log("\n========================================");
        console.log("  Local Deployment Summary");
        console.log("========================================");
        console.log("Mock WETH:", address(weth));
        console.log("Mock VRF Coordinator:", address(vrfCoordinator));
        console.log("\nMain contracts (proxies):");
        console.log("  MultisigTimelock:", d.multisigTimelock);
        console.log("  Factory:", d.factory);
        console.log("  Marketplace:", d.marketplace);
        console.log("  Auction:", d.auction);
        console.log("  Staking:", d.staking);
        console.log("  VRFAdapter:", d.vrfAdapter);
        console.log("  Beacon:", d.beacon);
        console.log("  SwapAdapter:", d.swapAdapter);
    }
}

/// @dev Simple mock WETH for local testing
contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);
        return true;
    }
}

/// @dev Simple mock VRF Coordinator for local testing
contract MockVRFCoordinator {
    uint256 private _requestId;

    function requestRandomWords(bytes memory) external returns (uint256) {
        return ++_requestId;
    }
}
