// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../../Base.t.sol";
import {Factory} from "../../../src/Factory.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployHelpers} from "../../helpers/DeployHelpers.s.sol";
import {FactoryHelper} from "../../helpers/FactoryHelper.sol";
import {MarketplaceNFT} from "../../../src/Marketplace.sol";
import {ERC721CollectionBeacon} from "../../../src/ERC721CollectionBeacon.sol";

/// @title Factory Setup Tests
/// @notice Tests for Factory initialization, access control, and configuration
contract Factory_SetupTest is FactoryHelper {
    Factory public factory;
    ERC721CollectionBeacon public beacon;
    MarketplaceNFT public marketplace;
    address multisig;

    // Events
    event FactoryIsActive();
    event FactorySetStopped();
    event MultisigTimelockSet(address indexed multisigTimelock);
    event NewMarketplaceAddressSet(address indexed marketplace);
    event VRFAdapterSet(address indexed vrfAdapter);
    event BeaconSet(address indexed beacon);

    function setUp() public override {
        super.setUp();

        allDeployments memory allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        beacon = allContracts.beacon;
        marketplace = allContracts.marketplace;
        factory = allContracts.factory;
    }

    // ============ Initialization Tests ============

    function test_Initialize() public {
        assertEq(factory.getBeaconAddress(), address(beacon));
        assertTrue(factory.isFactoryActive());
        assertEq(factory.getMultisigTimelock(), multisig);
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        Factory newImpl = new Factory();
        bytes memory initData = abi.encodeWithSelector(
            Factory.initialize.selector,
            address(0)
        );

        vm.expectRevert(Factory.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    // ============ Access Control Tests ============

    function test_RevertWhen_NotMultisigCallsActivateFactory() public {
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.activateFactory();
    }

    function test_RevertWhen_NotMultisigCallsStopFactory() public {
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.stopFactory();
    }

    function test_RevertWhen_UserTriesToSetMarketplace() public {
        vm.prank(USER1);
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.setMarketplaceAddress(address(marketplace));
    }

    function test_RevertWhen_UserTriesToSetVRFAdapter() public {
        vm.prank(USER1);
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.setVRFAdapter(VRF_ADAPTER);
    }

    function test_RevertWhen_UserTriesToSetBeacon() public {
        vm.prank(USER1);
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.setCollectionBeaconAddress(address(0x9999));
    }

    function test_RevertWhen_UserTriesToSetMultisigTimelock() public {
        vm.prank(USER1);
        vm.expectRevert(Factory.NotAMultisigTimelock.selector);
        factory.setMultisigTimelock(address(0x9999));
    }

    // ============ Configuration Tests ============

    function test_SetMarketplaceAddress() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.expectEmit(true, false, false, false);
        emit NewMarketplaceAddressSet(address(marketplace));
        
        vm.prank(multisig);
        newFactory.setMarketplaceAddress(address(marketplace));
        
        assertEq(newFactory.getMarketplaceAddress(), address(marketplace));
    }

    function test_RevertWhen_SetMarketplaceAddressWithZeroAddress() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.prank(multisig);
        vm.expectRevert(Factory.ZeroAddress.selector);
        newFactory.setMarketplaceAddress(address(0));
    }

    function test_SetVRFAdapter() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.expectEmit(true, false, false, false);
        emit VRFAdapterSet(VRF_ADAPTER);
        
        vm.prank(multisig);
        newFactory.setVRFAdapter(VRF_ADAPTER);
    }

    function test_GetBeaconAddress() public {
        assertEq(factory.getBeaconAddress(), address(beacon));
    }

    function test_RevertWhen_BeaconAlreadySet() public {
        vm.prank(multisig);
        vm.expectRevert(Factory.BeaconIsAlreadySet.selector);
        factory.setCollectionBeaconAddress(address(0x9999));
    }

    function test_RevertWhen_SetBeaconAddressWithZeroAddress() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.prank(multisig);
        vm.expectRevert(Factory.ZeroAddress.selector);
        newFactory.setCollectionBeaconAddress(address(0));
    }

    function test_SetMultisigTimelock() public {
        address newMultisig = address(0x9999);
        
        vm.expectEmit(true, false, false, false);
        emit MultisigTimelockSet(newMultisig);
        
        vm.prank(multisig);
        factory.setMultisigTimelock(newMultisig);
        
        assertEq(factory.getMultisigTimelock(), newMultisig);
    }

    function test_ActivateFactory() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.startPrank(multisig);
        newFactory.setMarketplaceAddress(address(marketplace));
        newFactory.setCollectionBeaconAddress(address(beacon));
        newFactory.setVRFAdapter(VRF_ADAPTER);
        
        vm.expectEmit(true, false, false, false);
        emit FactoryIsActive();
        newFactory.activateFactory();
        
        assertTrue(newFactory.isFactoryActive());
        vm.stopPrank();
    }

    function test_StopFactory() public {
        vm.expectEmit(true, false, false, false);
        emit FactorySetStopped();
        
        vm.prank(multisig);
        factory.stopFactory();
        
        assertFalse(factory.isFactoryActive());
    }

    function test_ActivateFactoryAfterStopping() public {
        vm.startPrank(multisig);
        factory.stopFactory();
        
        vm.expectEmit(true, false, false, false);
        emit FactoryIsActive();
        factory.activateFactory();
        
        assertTrue(factory.isFactoryActive());
        vm.stopPrank();
    }

    function test_RevertWhen_ActivateFactoryWithoutMarketplace() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.expectRevert(Factory.MarketplaceAddressIsNotSet.selector);
        vm.prank(multisig);
        newFactory.activateFactory();
    }

    function test_RevertWhen_ActivateFactoryWithoutBeacon() public {
        Factory newFactory = deployFactory(multisig);
        
        vm.startPrank(multisig);
        newFactory.setMarketplaceAddress(address(marketplace));
        
        vm.expectRevert(Factory.NoBeaconAddressSet.selector);
        newFactory.activateFactory();
        vm.stopPrank();
    }

    function test_RevertWhen_ActivateFactoryAlreadyActive() public {
        vm.prank(multisig);
        vm.expectRevert(Factory.FactoryIsActiveAlready.selector);
        factory.activateFactory();
    }

    function test_RevertWhen_StopFactoryAlreadyStopped() public {
        vm.prank(multisig);
        factory.stopFactory();
        
        vm.prank(multisig);
        vm.expectRevert(Factory.FactoryIsStoppedAlready.selector);
        factory.stopFactory();
    }
}

