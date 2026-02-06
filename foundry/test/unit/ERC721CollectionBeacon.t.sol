
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {DeployHelpers} from "../helpers/DeployHelpers.s.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {ERC721CollectionBeacon} from "../../src/ERC721CollectionBeacon.sol";
import {MockMultisigTimelock, MockVRFAdapter} from "../helpers/Mocks.sol";

contract ERC721CollectionBeaconTest is DeployHelpers {
    allDeployments public allContracts;

    address public multisig;
    ERC721CollectionBeacon public beacon;

    function setUp() public override {
        super.setUp();

        allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        beacon = allContracts.beacon;
    }

    function test_Constructor() public {
        assertEq(multisig, beacon.getMultisigTimelock());
        assertEq(address(allContracts.erc721Collection), beacon.implementation());
    }

    function test_RevertWhen_Constructor() public {
        vm.expectRevert(ERC721CollectionBeacon.ZeroAddress.selector);
        ERC721CollectionBeacon newBeacon = new ERC721CollectionBeacon(address(0), multisig);

        vm.expectRevert(ERC721CollectionBeacon.ZeroAddress.selector);
        newBeacon = new ERC721CollectionBeacon(address(allContracts.erc721Collection), address(0));

        vm.expectRevert(ERC721CollectionBeacon.BeaconInvalidImplementation.selector);
        newBeacon = new ERC721CollectionBeacon(address(0x999), multisig);
    }


    function test_UpgradeTo() public {
        ERC721Collection newImplementation = deployERC721CollectionImpl();
        vm.prank(multisig);
        beacon.upgradeTo(address(newImplementation));
        assertEq(beacon.implementation(), address(newImplementation));
    }

    function test_RevertWhen_UpgradeTo() public {
        vm.expectRevert(ERC721CollectionBeacon.NotMultisigTimelock.selector);
        vm.prank(address(0x111));
        beacon.upgradeTo(address(0));

        vm.expectRevert(ERC721CollectionBeacon.ZeroAddress.selector);
        vm.prank(multisig);
        beacon.upgradeTo(address(0));

        vm.expectRevert(ERC721CollectionBeacon.BeaconInvalidImplementation.selector);
        vm.prank(multisig);
        beacon.upgradeTo(address(0x999));
    }

    function test_SetMultisigTimelock() public {
        MockMultisigTimelock newMultisig = new MockMultisigTimelock();
        vm.prank(multisig);
        beacon.setMultisigTimelock(address(newMultisig));
        assertEq(beacon.getMultisigTimelock(), address(newMultisig));
    }

    function test_RevertWhen_SetMultisigTimelock() public {
        vm.expectRevert(ERC721CollectionBeacon.NotMultisigTimelock.selector);
        vm.prank(address(0x111));
        beacon.setMultisigTimelock(address(0));

        vm.expectRevert(ERC721CollectionBeacon.ZeroAddress.selector);
        vm.prank(multisig);
        beacon.setMultisigTimelock(address(0));

        vm.expectRevert(ERC721CollectionBeacon.MultisigTimelockInvalidImplementation.selector);
        vm.prank(multisig);
        beacon.setMultisigTimelock(address(0x999));
    }
    
    function test_GetMultisigTimelock() public {
        ERC721CollectionBeacon newBeacon = new ERC721CollectionBeacon(address(allContracts.erc721Collection), multisig);
        assertEq(newBeacon.getMultisigTimelock(), multisig);
    }
        
    function test_implementation() public {
        ERC721CollectionBeacon newBeacon = new ERC721CollectionBeacon(address(allContracts.erc721Collection), multisig);
        assertEq(newBeacon.implementation(), address(allContracts.erc721Collection)); 
    }
}