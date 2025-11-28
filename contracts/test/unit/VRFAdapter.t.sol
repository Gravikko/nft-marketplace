
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {BaseTest} from "../Base.t.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VRFAdapter} from "../../src/VRFAdapter.sol";
import {MockVRFCoordinatorV2Plus, MockERC721Collection} from "../helpers/Mocks.sol";

contract VRFAdapterTest is BaseTest { 
    using stdStorage for StdStorage;
    VRFAdapter vrfAdapter;
    MockERC721Collection mockCollection;
    MockVRFCoordinatorV2Plus mockCoordinator;

    bytes32 constant KEY_HASH = bytes32(uint256(0x123));
    uint256 constant SUBSCRIPTION_ID = 1;
    uint32 constant CALLBACK_GAS_LIMIT = 500000;
    uint16 constant REQUEST_CONFIRMATIONS = 3;

    function setUp() public override {
        super.setUp(); 

        mockCoordinator = new MockVRFCoordinatorV2Plus();

        VRFAdapter impl = new VRFAdapter();

        bytes memory initData = abi.encodeWithSelector(
            VRFAdapter.initialize.selector,
            address(mockCoordinator),
            SUBSCRIPTION_ID,
            KEY_HASH,
            CALLBACK_GAS_LIMIT,
            REQUEST_CONFIRMATIONS
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        vrfAdapter = VRFAdapter(payable(address(proxy)));

        mockCollection = new MockERC721Collection();
        mockCollection.setVRFAdapter(address(vrfAdapter));
    }


    function test_Initialize() public { 
        assertEq(address(vrfAdapter.s_vrfCoordinator()), address(mockCoordinator));
    }


    function test_setVRFConfig() public {
        address newCoordinator = address(0x123);
        bytes32 newKeyHash = bytes32(uint256(0x999));
        uint256 newSubId = SUBSCRIPTION_ID + 1;
        uint32 newGasLimit = CALLBACK_GAS_LIMIT + 1;
        uint16 newConfirmations = REQUEST_CONFIRMATIONS + 1;

        vm.expectEmit(true, true, false, true);
        emit VRFAdapter.VRFConfigUpdated(newCoordinator, newSubId, newKeyHash);

        vrfAdapter.setVRFConfig(
            newCoordinator,
            newSubId,
            newKeyHash,
            newGasLimit,
            newConfirmations
        );
        
        assertEq(address(vrfAdapter.s_vrfCoordinator()), newCoordinator);
    }

    function test_RevertWhen_setVRFConfig() public {
        vm.expectRevert(VRFAdapter.ZeroAddress.selector);
        vrfAdapter.setVRFConfig(
            address(0),
            SUBSCRIPTION_ID,
            KEY_HASH,
            CALLBACK_GAS_LIMIT,
            REQUEST_CONFIRMATIONS
        );
    }

    function test_setAuthorizedCollection() public {
        vrfAdapter.setAuthorizedCollection(address(0x999), true);
        assertEq(vrfAdapter.isAuthorizedCollection(address(0x999)), true);
        vrfAdapter.setAuthorizedCollection(address(0x999), false);
        assertEq(vrfAdapter.isAuthorizedCollection(address(0x999)), false);
    }

    function test_RevertWhen_setAuthorizedCollection() public {
        vm.expectRevert(VRFAdapter.ZeroAddress.selector);
        vrfAdapter.setAuthorizedCollection(address(0), true);
    }

    function test_requestRandomness() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);

        uint256 tokenId = 123;
        uint256 requestId = mockCollection.requestReveal(tokenId);

        assertGt(requestId, 0);

        (address collection, uint256 pendingTokenId) = vrfAdapter.getPendingRequest(requestId);
        assertEq(collection, address(mockCollection));
        assertEq(pendingTokenId, tokenId);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 999;

        mockCoordinator.fulfillRequest(vrfAdapter, requestId, randomWords);

        (address clearedCollection, uint256 clearedTokenId) = vrfAdapter.getPendingRequest(requestId);
        assertEq(clearedCollection, address(0));
        assertEq(clearedTokenId, 0);
        assertEq(mockCollection.revealedTokens(tokenId), randomWords[0]);
    }

    function test_RevertWhen_requestRandomness() public {
        vm.expectRevert(VRFAdapter.UnauthorizedCollection.selector);
        vrfAdapter.requestRandomness(0);
    }

    function test_RevertWhen_requestRandomness_VRFNotConfigured() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);

        uint256 slot = stdstore.target(address(vrfAdapter)).sig("s_vrfCoordinator()").find();
        vm.store(address(vrfAdapter), bytes32(slot), bytes32(uint256(0)));

        vm.prank(address(mockCollection));
        vm.expectRevert(VRFAdapter.VRFNotConfigured.selector);
        vrfAdapter.requestRandomness(1);
    }

    function test_rawFulfillRandomWords() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);
        uint256 tokenId = 77;
        uint256 requestId = mockCollection.requestReveal(tokenId);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 555;

        vm.prank(address(mockCoordinator));
        vrfAdapter.rawFulfillRandomWords(requestId, randomWords);

        assertEq(mockCollection.revealedTokens(tokenId), randomWords[0]);
    }

    function test_RevertWhen_rawFulfillRandomWords() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);
        uint256 requestId = mockCollection.requestReveal(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;

        vm.expectRevert(VRFAdapter.OnlyCoordinatorCanFulfill.selector);
        vrfAdapter.rawFulfillRandomWords(requestId, randomWords);
    }

    /// view functcions


    function test_getPendingRequest() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);
        uint256 tokenId = 88;
        uint256 requestId = mockCollection.requestReveal(tokenId);

        (address collection, uint256 pendingTokenId) = vrfAdapter.getPendingRequest(requestId);
        assertEq(collection, address(mockCollection));
        assertEq(pendingTokenId, tokenId);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 11;
        vm.prank(address(mockCoordinator));
        vrfAdapter.rawFulfillRandomWords(requestId, randomWords);

        (address clearedCollection, uint256 clearedTokenId) = vrfAdapter.getPendingRequest(requestId);
        assertEq(clearedCollection, address(0));
        assertEq(clearedTokenId, 0);
    }


    function test_getPendingRequest_NotFoundReturnsZero() public {
        (address collection, uint256 tokenId) = vrfAdapter.getPendingRequest(999);
        assertEq(collection, address(0));
        assertEq(tokenId, 0);
    }

    /// internal

    function test_RevertWhen_fulfillRandomWords_InvalidRequest() public {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;

        vm.prank(address(mockCoordinator));
        vm.expectRevert(VRFAdapter.InvalidRequest.selector);
        vrfAdapter.rawFulfillRandomWords(999, randomWords);
    }

    function test_RevertWhen_fulfillRandomWords_DuplicateRequest() public {
        vrfAdapter.setAuthorizedCollection(address(mockCollection), true);
        uint256 requestId = mockCollection.requestReveal(5);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 77;

        vm.prank(address(mockCoordinator));
        vrfAdapter.rawFulfillRandomWords(requestId, randomWords);

        vm.prank(address(mockCoordinator));
        vm.expectRevert(VRFAdapter.InvalidRequest.selector);
        vrfAdapter.rawFulfillRandomWords(requestId, randomWords);
    }

}

