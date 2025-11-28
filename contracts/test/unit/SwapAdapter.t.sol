// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployHelpers} from "../helpers/DeployHelpers.s.sol";
import {SwapAdapter} from "../../src/SwapAdapter.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns(bool);
    function balanceOf(address) external view returns(uint256);
}

contract MockWETH is IWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function transfer(address to, uint256 value) external returns(bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }


    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract SwapAdapterTest is Test {

    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x1003);
    MockWETH public weth;
    uint256 public constant DEFAULT_BALANCE = 100 ether;
    uint256 public constant DEFAULT_WRAP_AMOUNT = 1 ether;
    uint256 public constant DEFAULT_UNWRAP_AMOUNT = 1 ether;

    SwapAdapter adapter;

    function setUp() public {
        vm.label(USER1, "user1");
        vm.label(USER2, "user2");
        vm.label(USER3, "user3");

        vm.deal(USER1, DEFAULT_BALANCE);
        vm.deal(USER2, DEFAULT_BALANCE);
        vm.deal(USER3, DEFAULT_BALANCE);

        weth = new MockWETH();
        adapter = new SwapAdapter(address(weth));
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert(SwapAdapter.ZeroAddress.selector);
        SwapAdapter newAdapter = new SwapAdapter(address(0));

        vm.startBroadcast(USER1);

        vm.expectRevert(SwapAdapter.ZeroAddress.selector);
        adapter.unwrapWETH(DEFAULT_WRAP_AMOUNT, payable(address(0)));

        vm.expectRevert(SwapAdapter.ZeroAddress.selector);
        adapter.wrapETH(address(0));

        vm.stopBroadcast();
    }

    function test_WrapUnwrapETH() public {

        uint256 user2WETHBalanceBefore = weth.balanceOf(USER2);
        uint256 user2BalanceBefore = USER2.balance;
        uint256 user1BalanceBefore = USER1.balance;

        vm.prank(USER1);
        adapter.wrapETH{value: DEFAULT_WRAP_AMOUNT}(USER2);

        uint256 user2WETHBalanceAfter = weth.balanceOf(USER2);

        assertEq(user2WETHBalanceBefore + DEFAULT_WRAP_AMOUNT, user2WETHBalanceAfter);

        // Transfer WETH to adapter (required for unwrapWETH to work)
        vm.prank(USER2);
        weth.transfer(address(adapter), DEFAULT_UNWRAP_AMOUNT);

        vm.prank(USER2);
        adapter.unwrapWETH(DEFAULT_WRAP_AMOUNT, payable(USER2));

        uint256 user2BalanceAfter = USER2.balance;
        uint256 user1BalanceAfter = USER1.balance;

        assertEq(user2BalanceBefore + DEFAULT_WRAP_AMOUNT, user2BalanceAfter);
        assertEq(user1BalanceBefore, user1BalanceAfter + DEFAULT_WRAP_AMOUNT);
    }
}