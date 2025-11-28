// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../../Base.t.sol";
import {Factory} from "../../../src/Factory.sol";
import {DeployHelpers} from "../../helpers/DeployHelpers.s.sol";
import {FactoryHelper} from "../../helpers/FactoryHelper.sol";

/// @title Factory Collection Creation Tests
/// @notice Tests for collection creation functionality
contract Factory_CollectionCreationTest is FactoryHelper {
    Factory public factory;
    address multisig;

    // Events
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        address indexed collectionAddress,
        string name,
        string symbol
    );

    function setUp() public override {
        super.setUp();

        allDeployments memory allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        factory = allContracts.factory;
    }

    // ============ Successful Collection Creation Tests ============

    function test_CreateCollection_Success() public {
        (uint256 collectionId, address collectionAddress) = createCollection(factory, USER1);

        assertEq(collectionId, 1);
        assertTrue(collectionAddress != address(0));
        assertEq(factory.getCollectionOwnerById(collectionId), USER1);
        assertEq(factory.getCollectionAddressById(collectionId), collectionAddress);
        assertEq(factory.getCollectionIdByAddress(collectionAddress), collectionId);
    }

    function test_CreateCollection_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit CollectionCreated(
            1,
            USER1,
            address(0),
            "Test Collection",
            "TEST"
        );

        createCollection(factory, USER1);
    }

    function test_CreateCollectionDelayedRevealType() public {
        Factory.CreateCollectionParams memory params = getDefaultCollectionParamsWithRevealType(USER1, "delayed");
        
        (uint256 collectionId, address collectionAddress) = createCollectionWithParams(factory, USER1, params);

        assertEq(collectionId, 1);
        assertTrue(collectionAddress != address(0));
    }

    function test_MultipleCollectionsPerUser() public {
        createCollection(factory, USER1);
        createCollection(factory, USER1);
        createCollection(factory, USER1);

        uint256[] memory collections = factory.getAllAddressCollectionIds(USER1);
        assertEq(collections.length, 3);
        assertEq(collections[0], 1);
        assertEq(collections[1], 2);
        assertEq(collections[2], 3);
    }

    // ============ Factory State Revert Tests ============

    function test_RevertWhen_CreateCollectionFactoryStopped() public {
        vm.prank(multisig);
        factory.stopFactory();

        vm.prank(USER1);
        vm.expectRevert(Factory.FactoryIsStopped.selector);
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        factory.createCollection(params);
    }

    function test_RevertWhen_CreateCollectionWithoutVRFAdapter() public {
        vm.prank(multisig);
        factory.setVRFAdapter(address(0));

        vm.prank(USER1);
        vm.expectRevert(Factory.NoVRFAdapterSet.selector);
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        factory.createCollection(params);
    }

    function test_RevertWhen_CreateCollectionWithoutBeacon() public {
        bytes32 beaconSlot = bytes32(uint256(2));
        vm.store(address(factory), beaconSlot, bytes32(uint256(0)));

        vm.prank(USER1);
        vm.expectRevert(Factory.NoBeaconAddressSet.selector);
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        factory.createCollection(params);
    }

    function test_RevertWhen_CreateCollectionWithoutMarketplace() public {
        bytes32 marketplaceSlot = bytes32(uint256(1));
        vm.store(address(factory), marketplaceSlot, bytes32(uint256(0)));

        vm.prank(USER1);
        vm.expectRevert(Factory.MarketplaceAddressIsNotSet.selector);
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        factory.createCollection(params);
    }

    // ============ Supply Validation Tests ============

    function test_RevertWhen_CreateCollectionMaxSupplyTooHigh() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.maxSupply = 20_001;

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectCollectionSupply.selector);
        factory.createCollection(params);
    }

    function test_RevertWhen_CreateCollectionMaxSupplyZero() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.maxSupply = 0;

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectCollectionSupply.selector);
        factory.createCollection(params);
    }

    function test_RevertWhen_CreateCollectionBatchMintSupplyTooHigh() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.batchMintSupply = DEFAULT_MAX_SUPPLY + 1;

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectBatchMintSupply.selector);
        factory.createCollection(params);
    }

    // ============ Reveal Type Validation Tests ============

    function test_RevertWhen_CreateCollectionInvalidRevealType() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.revealType = "invalid";

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectRevealType.selector);
        factory.createCollection(params);
    }

    // ============ Royalty Validation Tests ============

    function test_RevertWhen_CreateCollectionRoyaltyFeeTooHigh() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.royaltyFeeNumerator = 10001;

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectRoyaltyFee.selector);
        factory.createCollection(params);
    }

    // ============ Mint Price Validation Tests ============

    function test_RevertWhen_CreateCollectionMintPriceZero() public {
        Factory.CreateCollectionParams memory params = getCollectionParamsForRevert(USER1);
        params.mintPrice = 0;

        vm.prank(USER1);
        vm.expectRevert(Factory.IncorrectMintPrice.selector);
        factory.createCollection(params);
    }
}
