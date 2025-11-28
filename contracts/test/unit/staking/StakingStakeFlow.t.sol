// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {StakingNFT} from "../../../src/Staking.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";
import {StakingTestHelper} from "../../helpers/StakingTestHelper.sol";

contract StakingStakeFlowTest is StakingTestHelper {
    function test_StakeNFT() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTStaked(USER1, collectionId, tokenId, block.timestamp);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        assertEq(collection.ownerOf(tokenId), address(staking));
        assertEq(staking.getStaker(collectionId, tokenId), USER1);
        assertEq(staking.checkUserStakeNFT(USER1, collectionId, tokenId), true);
    }

    function test_UnstakeNFT() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(multisig);
        staking.setRewardAmount(DEFAULT_REWARD_AMOUNT);
        vm.deal(address(staking), 100 ether);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);
        uint256 stakedTimestamp = block.timestamp;

        uint256 userBalanceBefore = USER1.balance;
        uint256 stakingTime = 10 seconds;

        vm.warp(block.timestamp + stakingTime);

        assertEq(staking.getStaker(collectionId, tokenId), USER1);
        assertEq(staking.checkUserStakeNFT(USER1, collectionId, tokenId), true);
        assertEq(staking.getStakedTimestamp(collectionId, tokenId), stakedTimestamp);
        assertEq(staking.getUserTokenStaked(USER1, collectionId).length, 1);

        uint256 stakedTokenId = staking.getUserTokenStaked(USER1, collectionId)[0];
        assertEq(stakedTokenId, tokenId);

        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTUnstaked(USER1, collectionId, tokenId, block.timestamp);

        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);

        assertEq(collection.ownerOf(tokenId), USER1);
        assertEq(staking.getStaker(collectionId, tokenId), address(0));
        assertEq(staking.checkUserStakeNFT(USER1, collectionId, tokenId), false);
        assertEq(staking.getStakedTimestamp(collectionId, tokenId), 0);
        assertEq(staking.getUserTokenStaked(USER1, collectionId).length, 0);

        uint256 expectedReward = DEFAULT_REWARD_AMOUNT * stakingTime;
        assertEq(USER1.balance, userBalanceBefore + expectedReward);
    }

    function test_RevertWhen_StakingWhileNotActive() public {
        vm.prank(multisig);
        staking.stopStaking();

        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.expectRevert(StakingNFT.StakingAlreadyStopped.selector);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);
    }

    function test_RevertWhen_StakingNFTNotOwned() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER2);
        collection.setApprovalForAll(address(staking), true);

        vm.expectRevert(StakingNFT.NotNFTOwner.selector);
        vm.prank(USER2);
        staking.stake(collectionId, tokenId);
    }

    function test_RevertWhen_StakingNFTNotApproved() public {
        (uint256 collectionId,, uint256 tokenId,) = stakingCreateCollectionAndMintToken(USER1);

        vm.expectRevert(StakingNFT.NoApprovedForStakingContract.selector);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);
    }

    function test_RevertWhen_StakingAlreadyStakedNFT() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.expectRevert(StakingNFT.NFTAlreadyStaked.selector);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);
    }

    function test_RevertWhen_UnstakingNFTNotStakedByUser() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.expectRevert(StakingNFT.NFTNotStakedByUser.selector);
        vm.prank(USER2);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_RevertWhen_UnstakingNFTNotStaked() public {
        (uint256 collectionId,, uint256 tokenId,) = stakingCreateCollectionAndMintToken(USER1);

        vm.expectRevert(StakingNFT.NFTNotStakedByUser.selector);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_RewardCalculation() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        uint256 rewardPerSecond = 1 ether;
        vm.prank(multisig);
        staking.setRewardAmount(rewardPerSecond);
        vm.deal(address(staking), 1000 ether);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        uint256 stakingDuration = 100 seconds;
        uint256 userBalanceBefore = USER1.balance;

        vm.warp(block.timestamp + stakingDuration);

        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);

        uint256 expectedReward = rewardPerSecond * stakingDuration;
        assertEq(USER1.balance, userBalanceBefore + expectedReward);
    }

    function test_RevertWhen_InsufficientContractBalanceForReward() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(multisig);
        staking.setRewardAmount(1 ether);
        vm.deal(address(staking), 1 ether);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.warp(block.timestamp + 100 seconds);

        vm.expectRevert(StakingNFT.InsufficientContractBalance.selector);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_RevertWhen_InvalidTimestamp_TimePassedZero() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) = setInitialValues();

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.expectRevert(StakingNFT.InvalidTimestamp.selector);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_RevertWhen_UnstakingWhileStakingStopped() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) = setInitialValues();

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.warp(block.timestamp + 10 seconds);

        vm.prank(multisig);
        staking.stopStaking();

        vm.expectRevert(StakingNFT.StakingAlreadyStopped.selector);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_MultipleUsersStakingDifferentTokens() public {
        (uint256 collectionId,, uint256 tokenId1, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER2);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId2 = collection.getNextTokenId() - 1;

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
        vm.prank(USER2);
        collection.setApprovalForAll(address(staking), true);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId1);
        vm.prank(USER2);
        staking.stake(collectionId, tokenId2);

        assertEq(staking.getStaker(collectionId, tokenId1), USER1);
        assertEq(staking.getStaker(collectionId, tokenId2), USER2);
        assertEq(staking.checkUserStakeNFT(USER1, collectionId, tokenId1), true);
        assertEq(staking.checkUserStakeNFT(USER2, collectionId, tokenId2), true);
        assertEq(staking.checkUserStakeNFT(USER1, collectionId, tokenId2), false);
        assertEq(staking.checkUserStakeNFT(USER2, collectionId, tokenId1), false);
    }

    function test_UnstakeAndRemoveFromArray() public {
        (uint256 collectionId,, uint256 tokenId1, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId2 = collection.getNextTokenId() - 1;

        vm.prank(multisig);
        staking.setRewardAmount(DEFAULT_REWARD_AMOUNT);
        vm.deal(address(staking), 100 ether);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId1);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId2);

        assertEq(staking.getUserTokenStaked(USER1, collectionId).length, 2);

        vm.warp(block.timestamp + 10 seconds);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId1);

        uint256[] memory remaining = staking.getUserTokenStaked(USER1, collectionId);
        assertEq(remaining.length, 1);
        assertEq(remaining[0], tokenId2);
    }

    function test_Events_EmitCorrectly() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) = setInitialValues();

        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTStaked(USER1, collectionId, tokenId, block.timestamp);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.warp(block.timestamp + 10 seconds);

        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTUnstaked(USER1, collectionId, tokenId, block.timestamp);
        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }

    function test_Stake_EmitsEventWithCorrectTimestamp() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) = setInitialValues();

        uint256 expectedTimestamp = block.timestamp;
        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTStaked(USER1, collectionId, tokenId, expectedTimestamp);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);
    }

    function test_Unstake_EmitsEventWithCorrectTimestamp() public {
        (uint256 collectionId,, uint256 tokenId, ERC721Collection collection) = setInitialValues();

        vm.prank(USER1);
        staking.stake(collectionId, tokenId);

        vm.warp(block.timestamp + 10 seconds);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit StakingNFT.NFTUnstaked(USER1, collectionId, tokenId, expectedTimestamp);

        vm.prank(USER1);
        staking.unstakeNFT(collectionId, tokenId);
    }
}


