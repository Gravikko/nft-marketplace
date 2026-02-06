// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../../Base.t.sol";
import {Factory} from "../../../src/Factory.sol";
import {DeployHelpers} from "../../helpers/DeployHelpers.s.sol";
import {FactoryHelper} from "../../helpers/FactoryHelper.sol";
import {MarketplaceNFT} from "../../../src/Marketplace.sol";
import {ERC721CollectionBeacon} from "../../../src/ERC721CollectionBeacon.sol";

/// @title Factory Queries Tests
/// @notice Tests for view functions and fuzz testing
contract Factory_QueriesTest is FactoryHelper {
    Factory public factory;
    ERC721CollectionBeacon public beacon;
    MarketplaceNFT public marketplace;
    address multisig;

    function setUp() public override {
        super.setUp();

        allDeployments memory allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        beacon = allContracts.beacon;
        marketplace = allContracts.marketplace;
        factory = allContracts.factory;
    }

    // ============ Collection Owner Tests ============

    function test_GetCollectionOwnerById() public {
        (uint256 collectionId, ) = createCollection(factory, USER1);

        address owner = factory.getCollectionOwnerById(collectionId);
        assertEq(owner, USER1);
    }

    function test_RevertWhen_GetCollectionOwnerById_ZeroId() public {
        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionOwnerById(0);
    }

    function test_RevertWhen_GetCollectionOwnerById_InvalidId() public {
        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionOwnerById(999);
    }

    // ============ Collection Address Tests ============

    function test_GetCollectionAddressById() public {
        (uint256 collectionId, address collectionAddress) = createCollection(factory, USER1);

        address retrievedAddress = factory.getCollectionAddressById(collectionId);
        assertEq(retrievedAddress, collectionAddress);
    }

    function test_RevertWhen_GetCollectionAddressById_ZeroId() public {
        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionAddressById(0);
    }

    function test_RevertWhen_GetCollectionAddressById_InvalidId() public {
        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionAddressById(999);
    }

    // ============ Collection ID Tests ============

    function test_GetCollectionIdByAddress() public {
        (, address collectionAddress) = createCollection(factory, USER1);

        uint256 collectionId = factory.getCollectionIdByAddress(collectionAddress);
        assertEq(collectionId, 1);
    }

    function test_RevertWhen_GetCollectionIdByAddress_ZeroAddress() public {
        vm.expectRevert(Factory.ZeroAddress.selector);
        factory.getCollectionIdByAddress(address(0));
    }

    function test_RevertWhen_GetCollectionIdByAddress_NonExistent() public {
        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionIdByAddress(address(0x9999));
    }

    // ============ User Collections Tests ============

    function test_GetAllAddressCollectionIds() public {
        (uint256 collectionId, ) = createCollection(factory, USER1);

        uint256[] memory userCollections = factory.getAllAddressCollectionIds(USER1);
        assertEq(userCollections.length, 1);
        assertEq(userCollections[0], collectionId);
    }

    function test_GetAllAddressCollectionIds_MultipleCollections() public {
        createCollection(factory, USER1);
        createCollection(factory, USER1);
        createCollection(factory, USER1);

        uint256[] memory collections = factory.getAllAddressCollectionIds(USER1);
        assertEq(collections.length, 3);
        assertEq(collections[0], 1);
        assertEq(collections[1], 2);
        assertEq(collections[2], 3);
    }

    function test_RevertWhen_GetAllAddressCollectionIds_ZeroAddress() public {
        vm.expectRevert(Factory.ZeroAddress.selector);
        factory.getAllAddressCollectionIds(address(0));
    }

    function test_RevertWhen_GetAllAddressCollectionIds_NoCollections() public {
        vm.expectRevert(Factory.AddressHasNoCollections.selector);
        factory.getAllAddressCollectionIds(USER2);
    }

    // ============ Collection Amount Tests ============

    function test_GetAddressCollectionAmount() public {
        createCollection(factory, USER1);

        uint256 amount = factory.getAddressCollectionAmount(USER1);
        assertEq(amount, 1);
    }

    function test_GetAddressCollectionAmount_MultipleCollections() public {
        createCollection(factory, USER1);
        createCollection(factory, USER1);
        createCollection(factory, USER1);

        uint256 amount = factory.getAddressCollectionAmount(USER1);
        assertEq(amount, 3);
    }

    function test_GetAddressCollectionAmount_NoCollections() public {
        uint256 amount = factory.getAddressCollectionAmount(USER2);
        assertEq(amount, 0);
    }

    function test_RevertWhen_GetAddressCollectionAmount_ZeroAddress() public {
        vm.expectRevert(Factory.ZeroAddress.selector);
        factory.getAddressCollectionAmount(address(0));
    }

    // ============ Factory Status Tests ============

    function test_IsFactoryActive() public {
        assertTrue(factory.isFactoryActive());
    }

    function test_IsFactoryActive_AfterStopping() public {
        vm.prank(multisig);
        factory.stopFactory();

        assertFalse(factory.isFactoryActive());
    }

    // ============ Beacon Address Tests ============

    function test_GetBeaconAddress() public {
        address beaconAddress = factory.getBeaconAddress();
        assertEq(beaconAddress, address(beacon));
    }

    // ============ Multisig Timelock Tests ============

    function test_GetMultisigTimelock() public {
        address retrievedMultisig = factory.getMultisigTimelock();
        assertEq(retrievedMultisig, multisig);
    }

    // ============ Marketplace Address Tests ============

    function test_GetMarketplaceAddress() public {
        address marketplaceAddress = factory.getMarketplaceAddress();
        assertEq(marketplaceAddress, address(marketplace));
    }

    // ============ Fuzz Tests ============

    function testFuzz_SetMultisigTimelock(address newMultisig) public {
        vm.assume(newMultisig != address(0));
        vm.assume(newMultisig != multisig);

        vm.prank(multisig);
        factory.setMultisigTimelock(newMultisig);

        assertEq(factory.getMultisigTimelock(), newMultisig);
    }

    function testFuzz_SetVRFAdapter(address vrfAdapter) public {
        vm.assume(vrfAdapter != address(0));

        vm.prank(multisig);
        factory.setVRFAdapter(vrfAdapter);
    }

    function testFuzz_CreateCollection_ValidParams(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 mintPrice,
        uint96 royaltyFeeNumerator
    ) public {
        vm.assume(maxSupply > 0 && maxSupply <= factory.MAX_SUPPLY());
        vm.assume(mintPrice > 0);
        vm.assume(royaltyFeeNumerator <= 10000);
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(symbol).length > 0);

        uint256 batchMintSupply = maxSupply > 10 ? 10 : maxSupply;

        Factory.CreateCollectionParams memory params = Factory.CreateCollectionParams({
            name: name,
            symbol: symbol,
            revealType: "instant",
            baseURI: "baseURI",
            placeholderURI: "placeholderURI",
            royaltyReceiver: USER1,
            royaltyFeeNumerator: royaltyFeeNumerator,
            maxSupply: maxSupply,
            mintPrice: mintPrice,
            batchMintSupply: batchMintSupply
        });

        (uint256 collectionId, address collectionAddress) = createCollectionWithParams(factory, USER1, params);

        assertTrue(collectionId > 0);
        assertTrue(collectionAddress != address(0));
        assertEq(factory.getCollectionOwnerById(collectionId), USER1);
    }

    function testFuzz_GetCollectionOwnerById_InvalidId(uint256 invalidId) public {
        vm.assume(invalidId == 0 || invalidId >= 1000);

        vm.expectRevert(Factory.CollectionDoesNotExist.selector);
        factory.getCollectionOwnerById(invalidId);
    }

    function testFuzz_GetAddressCollectionAmount(address user) public {
        vm.assume(user != address(0));

        uint256 amount = factory.getAddressCollectionAmount(user);
        assertGe(amount, 0);
    }
}

