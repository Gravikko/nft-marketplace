// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingNFT} from "../../../src/Staking.sol";
import {StakingTestHelper} from "../../helpers/StakingTestHelper.sol";
import {Factory} from "../../../src/Factory.sol";

contract StakingAdminTest is StakingTestHelper {
    function test_RevertWhen_StakingIsAlreadyActive() public {
        vm.expectRevert(StakingNFT.StakingAlreadyActive.selector);
        vm.prank(multisig);
        staking.activateStaking();
    }

    function test_RevertWhen_StakingStoppedAlready() public {
        vm.startPrank(multisig);
        staking.stopStaking();
        vm.expectRevert(StakingNFT.StakingAlreadyStopped.selector);
        staking.stopStaking();
        vm.stopPrank();
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        StakingNFT newStaking = new StakingNFT();

        bytes memory initData =
            abi.encodeWithSelector(StakingNFT.initialize.selector, address(0));

        vm.expectRevert(StakingNFT.ZeroAddress.selector);
        new ERC1967Proxy(address(newStaking), initData);
    }

    function test_RevertWhen_ActivateStakingWithoutFactory() public {
        StakingNFT newStaking = deployStakingNFT(multisig);

        vm.expectRevert(StakingNFT.NoFactoryAddress.selector);
        vm.prank(multisig);
        newStaking.activateStaking();
    }

    function test_IsStakingActive_ToggleFlow() public {
        assertEq(staking.isStakingActive(), true);

        vm.expectEmit(false, false, false, false);
        emit StakingNFT.StakingStopped();
        vm.prank(multisig);
        staking.stopStaking();
        assertEq(staking.isStakingActive(), false);

        vm.expectEmit(false, false, false, false);
        emit StakingNFT.StakingActivated();
        vm.prank(multisig);
        staking.activateStaking();
        assertEq(staking.isStakingActive(), true);
    }

    function test_RevertWhen_ZeroAddress_OnAdminSetters() public {
        vm.startPrank(multisig);

        vm.expectRevert(StakingNFT.ZeroAddress.selector);
        staking.setMultisigTimelock(address(0));

        vm.expectRevert(StakingNFT.ZeroAddress.selector);
        staking.setFactoryAddress(address(0));

        vm.stopPrank();
    }

    function test_SetRewardAmount_UpdatesStateAndEmitsEvent(uint256 newReward) public {
        vm.expectEmit(true, false, false, false);
        emit StakingNFT.RewardAmountSet(newReward);

        vm.prank(multisig);
        staking.setRewardAmount(newReward);

        assertEq(staking.getRewardAmount(), newReward);
    }

    function test_SetFactoryAddress_UpdatesStateAndEmitsEvent() public {
        Factory newFactory = deployFactory(multisig);

        vm.expectEmit(true, false, false, false);
        emit StakingNFT.FactoryAddressSet(address(newFactory));

        vm.prank(multisig);
        staking.setFactoryAddress(address(newFactory));

        assertEq(staking.getFactoryAddress(), address(newFactory));
    }

    function test_SetMultisigTimelock_EmitsEvent() public {
        address newMultisig = address(0x9999);
        vm.deal(newMultisig, 1 ether);

        vm.expectEmit(true, false, false, false);
        emit StakingNFT.MultisigTimelockSet(newMultisig);

        vm.prank(multisig);
        staking.setMultisigTimelock(newMultisig);
    }

    function test_RevertWhen_NotMultisigCallsMultisigFunction() public {
        vm.expectRevert(StakingNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        staking.setRewardAmount(1 ether);

        vm.expectRevert(StakingNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        staking.setFactoryAddress(address(0x123));

        vm.expectRevert(StakingNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        staking.setMultisigTimelock(address(0x123));

        vm.expectRevert(StakingNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        staking.stopStaking();

        vm.expectRevert(StakingNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        staking.activateStaking();
    }
}


