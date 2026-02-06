// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {Factory} from "../../src/Factory.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {StakingNFT} from "../../src/Staking.sol";

abstract contract StakingTestHelper is DeployHelpers {
    allDeployments public allContracts;

    MarketplaceNFT public marketplace;
    Factory public factory;
    StakingNFT public staking;
    address public multisig;

    function setUp() public virtual override {
        super.setUp();

        allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        marketplace = allContracts.marketplace;
        factory = allContracts.factory;
        staking = allContracts.stakingNFT;
    }

    function stakingCreateCollectionAndMintToken(address user)
        internal
        returns (
            uint256 collectionId,
            address collectionAddress,
            uint256 tokenId,
            ERC721Collection collection
        )
    {
        (collectionId, collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        collection = ERC721Collection(collectionAddress);

        vm.prank(user);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        tokenId = collection.getNextTokenId() - 1;
    }

    function setInitialValues()
        internal
        returns (
            uint256 collectionId,
            address collectionAddress,
            uint256 tokenId,
            ERC721Collection collection
        )
    {
        (collectionId, collectionAddress, tokenId, collection) =
            stakingCreateCollectionAndMintToken(USER1);

        vm.prank(multisig);
        staking.setRewardAmount(DEFAULT_REWARD_AMOUNT);
        vm.deal(address(staking), 100 ether);

        vm.prank(USER1);
        collection.setApprovalForAll(address(staking), true);
    }
}


