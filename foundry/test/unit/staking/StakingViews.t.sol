// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {StakingNFT} from "../../../src/Staking.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";
import {StakingTestHelper} from "../../helpers/StakingTestHelper.sol";

contract StakingViewsTest is StakingTestHelper {
    function test_GetUserStakedTokens() public {
        (uint256 collectionId,, uint256 tokenId1, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId2 = collection.getNextTokenId() - 1;

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId1);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId2);

        uint256[] memory stakedTokens = staking.getUserStakedTokens(USER1, collectionId);
        assertEq(stakedTokens.length, 2);
        assertTrue(stakedTokens[0] == tokenId1 || stakedTokens[0] == tokenId2);
        assertTrue(stakedTokens[1] == tokenId1 || stakedTokens[1] == tokenId2);
    }

    function test_GetUserStakedTokens_MultipleTokensSameCollection() public {
        (uint256 collectionId,, uint256 tokenId1, ERC721Collection collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId2 = collection.getNextTokenId() - 1;
        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId3 = collection.getNextTokenId() - 1;

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);

        vm.prank(USER1);
        staking.stake(collectionId, tokenId1);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId2);
        vm.prank(USER1);
        staking.stake(collectionId, tokenId3);

        uint256[] memory stakedTokens = staking.getUserStakedTokens(USER1, collectionId);
        assertEq(stakedTokens.length, 3);

        bool found1 = false;
        bool found2 = false;
        bool found3 = false;
        for (uint256 i = 0; i < stakedTokens.length; i++) {
            if (stakedTokens[i] == tokenId1) found1 = true;
            if (stakedTokens[i] == tokenId2) found2 = true;
            if (stakedTokens[i] == tokenId3) found3 = true;
        }
        assertTrue(found1 && found2 && found3);
    }

    function test_GetStaker_InvalidCollectionId() public {
        uint256 invalidCollectionId = 99999;
        uint256 tokenId = 1;

        vm.expectRevert();
        staking.getStaker(invalidCollectionId, tokenId);
    }

    function test_CheckUserStakeNFT_InvalidCollectionId() public {
        uint256 invalidCollectionId = 99999;
        uint256 tokenId = 1;

        vm.expectRevert();
        staking.checkUserStakedNFT(USER1, invalidCollectionId, tokenId);
    }

    function test_GetUserTokenStaked_InvalidCollectionId() public {
        uint256 invalidCollectionId = 99999;

        vm.expectRevert();
        staking.getUserStakedTokens(USER1, invalidCollectionId);
    }

    function test_OnERC721Received_ReturnsCorrectSelector() public {
        bytes4 selector = staking.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }
}


