// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelpers} from "../helpers/DeployHelpers.s.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MultisigTimelock} from "../../src/MultisigTimelock.sol";

contract MultisigTimelockTest is DeployHelpers {

    address public constant OWNER1 = address(0x5001);
    address public constant OWNER2 = address(0x5002);
    address public constant OWNER3 = address(0x5003);

    uint256 public constant MIN_APPROVALS_AMOUNT = 2;
    uint256 public constant MAX_DELAY = 1000 seconds;

    bytes public constant DEFAULT_DATA = bytes("");
    uint256 public constant DEFAULT_VALUE = 0;
    uint256 public constant DEFAULT_DELAY = 0;
    uint256 public constant DEFAULT_GRACE_PERIOD = 1 days;
    address public constant DEFAULT_TARGET_ADDRESS = address(0);
    bytes32 public constant DEFAULT_TX_TYPE = keccak256("GENERIC_TX");

    MultisigTimelock multisig;

    function setUp() public override {
        super.setUp();

        vm.label(OWNER1, "owner1");
        vm.label(OWNER2, "owner2");
        vm.label(OWNER3, "owner3");

        address[] memory owners = new address[](3);
        owners[0] = OWNER1;
        owners[1] = OWNER2;
        owners[2] = OWNER3;

        MultisigTimelock multisigImpl = new MultisigTimelock();

        bytes memory initData = abi.encodeWithSelector(
            MultisigTimelock.initialize.selector,
            owners,
            MIN_APPROVALS_AMOUNT,
            MAX_DELAY
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(multisigImpl),
            initData
        );

        multisig = MultisigTimelock(payable(address(proxy)));
    }

    /// helpers

    function addToQueueDefaultTx() internal returns (bytes32 txHash) {
        vm.prank(OWNER1);
        txHash = multisig.addToQueue(
            DEFAULT_TARGET_ADDRESS,
            DEFAULT_DATA,
            DEFAULT_VALUE,
            block.timestamp,
            DEFAULT_GRACE_PERIOD,
            DEFAULT_TX_TYPE
        );
    }

    /// Queue and confirm a transaction for a given target/data
    function _queueAndConfirm(
        address target,
        bytes memory data
    ) internal returns (bytes32 txHash) {
        vm.prank(OWNER1);
        txHash = multisig.addToQueue(
            target,
            data,
            DEFAULT_VALUE,
            block.timestamp,
            DEFAULT_GRACE_PERIOD,
            DEFAULT_TX_TYPE
        );

        vm.prank(OWNER1);
        multisig.confirm(txHash);
        vm.prank(OWNER2);
        multisig.confirm(txHash);
    }


    /// main tests

    function test_AddToQueue() public {
        bytes32 txId = addToQueueDefaultTx();

        MultisigTimelock.QueuedTransaction memory queuedTx = multisig.getTransactionDetails(txId);

        assertEq(multisig.isQueued(txId), true);
        assertEq(queuedTx.target, DEFAULT_TARGET_ADDRESS);
        assertEq(queuedTx.data, DEFAULT_DATA);
        assertEq(queuedTx.value, DEFAULT_VALUE);
        assertEq(queuedTx.timestamp, block.timestamp);
        assertEq(queuedTx.gracePeriod, DEFAULT_GRACE_PERIOD);
        assertEq(queuedTx.approvalCount, 0);
        assertEq(queuedTx.executed, false);
        assertEq(queuedTx.txType, DEFAULT_TX_TYPE);
    }

    function test_RevertWhen_AddToQueue() public {
        bytes32 txHash;
        vm.startPrank(OWNER1);
        vm.expectRevert(MultisigTimelock.InvalidGracePeriod.selector);
        txHash = multisig.addToQueue(
            DEFAULT_TARGET_ADDRESS,
            DEFAULT_DATA,
            DEFAULT_VALUE,
            block.timestamp,
            DEFAULT_GRACE_PERIOD - 1,
            DEFAULT_TX_TYPE
        );

        vm.expectRevert(MultisigTimelock.DelayTooLong.selector);
        txHash = multisig.addToQueue(
            DEFAULT_TARGET_ADDRESS,
            DEFAULT_DATA,
            DEFAULT_VALUE,
            block.timestamp + MAX_DELAY + 1,
            DEFAULT_GRACE_PERIOD,
            DEFAULT_TX_TYPE
        );

        vm.warp(block.timestamp);
        vm.expectRevert(MultisigTimelock.TooEarly.selector);
        txHash = multisig.addToQueue(
            DEFAULT_TARGET_ADDRESS,
            DEFAULT_DATA,
            DEFAULT_VALUE,
            block.timestamp - 1,
            DEFAULT_GRACE_PERIOD,
            DEFAULT_TX_TYPE
        );

        vm.stopPrank();
        txHash = addToQueueDefaultTx();
        vm.expectRevert(MultisigTimelock.AlreadyQueued.selector);
        txHash = addToQueueDefaultTx();
        

    }

    function test_ConfirmTx() public {
        bytes32 txHash = addToQueueDefaultTx();

        vm.prank(OWNER1);
        multisig.confirm(txHash);
        vm.prank(OWNER2);
        multisig.confirm(txHash);
        vm.prank(OWNER3);
        multisig.confirm(txHash);

        MultisigTimelock.QueuedTransaction memory queuedTx = multisig.getTransactionDetails(txHash);
        assertEq(queuedTx.approvalCount, 3);

        assertEq(multisig.hasApproved(txHash, OWNER1), true);
        assertEq(multisig.hasApproved(txHash, OWNER2), true);
        assertEq(multisig.hasApproved(txHash, OWNER3), true);
    }

    function test_RevertWhen_ConfirmTx() public {
        vm.expectRevert(MultisigTimelock.TxNotQueued.selector);
        vm.prank(OWNER1);
        multisig.confirm(0);

        bytes32 txHash = addToQueueDefaultTx();

        vm.expectRevert(MultisigTimelock.NotAnOwner.selector);
        vm.prank(USER1);
        multisig.confirm(txHash);

        vm.startPrank(OWNER1);
        multisig.confirm(txHash);

        vm.expectRevert(MultisigTimelock.TxAlreadyConfirmedByThisAddress.selector);
        multisig.confirm(txHash);

        vm.stopPrank();

        vm.startPrank(OWNER2);
        multisig.confirm(txHash);
        multisig.executeTransaction(txHash);

        vm.stopPrank();
    }

    function test_CancelConfirmation() public {
        bytes32 txHash = addToQueueDefaultTx();
        vm.prank(OWNER1);
        multisig.confirm(txHash);
        // Cancel confirmation from OWNER1
        vm.prank(OWNER1);
        multisig.cancelConfirmation(txHash);
        MultisigTimelock.QueuedTransaction memory queuedTx = multisig.getTransactionDetails(txHash);

        assertEq(multisig.hasApproved(txHash, OWNER1), false);
        assertEq(queuedTx.approvalCount, 0);
        assertEq(multisig.hasApproved(txHash, OWNER2), false);
    }

    function test_RevertWhen_CancelConfirmation() public {

        vm.expectRevert(MultisigTimelock.TxNotQueued.selector);
        vm.prank(OWNER1);
        multisig.cancelConfirmation(0);

        bytes32 txHash = addToQueueDefaultTx();

        vm.expectRevert(MultisigTimelock.NotAnOwner.selector);
        vm.prank(USER1);
        multisig.cancelConfirmation(txHash);

        vm.expectRevert(MultisigTimelock.TxIsNotConfirmedByThisAddress.selector);
        vm.prank(OWNER1);
        multisig.cancelConfirmation(txHash);

        vm.prank(OWNER1);
        multisig.confirm(txHash);
        vm.startPrank(OWNER2);
        multisig.confirm(txHash);
        multisig.executeTransaction(txHash);
    }

    function test_ExecuteTx_clearsQueue() public {
        bytes32 txHash = addToQueueDefaultTx();
        
        vm.prank(OWNER1);
        multisig.confirm(txHash);
        vm.prank(OWNER2);
        multisig.confirm(txHash);

        // Execute the transaction
        vm.prank(OWNER1);
        multisig.executeTransaction(txHash);

        assertEq(multisig.isQueued(txHash), false);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.TxNotQueued.selector);
        multisig.executeTransaction(txHash);
    }

    function test_RevertWhen_ExecuteTx() public {

        bytes32 txHash = addToQueueDefaultTx();

        vm.startPrank(OWNER1);

        vm.expectRevert(MultisigTimelock.NotEnoughApprovals.selector);
        multisig.executeTransaction(txHash);

        vm.warp(0);

        vm.expectRevert(MultisigTimelock.TooEarly.selector);
        multisig.executeTransaction(txHash);
        
        vm.warp(block.timestamp + 365 days);

        vm.expectRevert(MultisigTimelock.TxExpired.selector);
        multisig.executeTransaction(txHash);

        vm.warp(block.timestamp);

        vm.stopPrank();
    }

    function test_CancelTx() public {
        bytes32 txHash = addToQueueDefaultTx();

        vm.warp(0);

        vm.prank(OWNER1);
        multisig.cancelTransaction(txHash);

        assertEq(multisig.isQueued(txHash), false);
    }

    function test_RevertWhen_CancelTx() public {
        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.TxNotQueued.selector);
        multisig.cancelTransaction(0);

        bytes32 txHash = addToQueueDefaultTx();
        vm.warp(DEFAULT_GRACE_PERIOD + 1);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.ExecutionWindowIsStarted.selector);
        multisig.cancelTransaction(txHash);
    }

    /// owner management tests

    function test_AddOwner() public {
        address newOwner = address(0x6001);
        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.addOwner.selector,
            newOwner
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        multisig.executeTransaction(txHash);

        assertEq(multisig.isOwner(newOwner), true);
        assertEq(multisig.getOwnerCount(), 4);
    }

    function test_RevertWhen_AddOwner_ZeroAddress() public {
        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.addOwner.selector,
            address(0)
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txHash);
    }

    function test_RevertWhen_AddOwner_AlreadyOwner() public {
        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.addOwner.selector,
            OWNER1
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txHash);
    }

    function test_DeleteOwner() public {
        // delete OWNER3
        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.deleteOwner.selector,
            OWNER3
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        multisig.executeTransaction(txHash);

        assertEq(multisig.isOwner(OWNER3), false);
        assertEq(multisig.getOwnerCount(), 2);
    }

    function test_RevertWhen_DeleteOwner_NotOwner() public {
        address nonOwner = USER1;
        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.deleteOwner.selector,
            nonOwner
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txHash);
    }

    function test_RevertWhen_DeleteOwner_MinApprovalsConstraint() public {
        // First delete OWNER3 so we have 2 owners left (equal to MIN_APPROVALS_AMOUNT)
        bytes memory dataDeleteOwner3 = abi.encodeWithSelector(
            MultisigTimelock.deleteOwner.selector,
            OWNER3
        );
        bytes32 txDelete = _queueAndConfirm(address(multisig), dataDeleteOwner3);
        vm.prank(OWNER1);
        multisig.executeTransaction(txDelete);

        // Now try to delete another owner -> should revert
        bytes memory dataDeleteOwner2 = abi.encodeWithSelector(
            MultisigTimelock.deleteOwner.selector,
            OWNER2
        );
        bytes32 txHash = _queueAndConfirm(address(multisig), dataDeleteOwner2);

        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txHash);
    }

    function test_SwapOwner() public {
        address newOwner = address(0x7001);

        bytes memory data = abi.encodeWithSelector(
            MultisigTimelock.swapOwner.selector,
            newOwner,
            OWNER3
        );

        bytes32 txHash = _queueAndConfirm(address(multisig), data);

        vm.prank(OWNER1);
        multisig.executeTransaction(txHash);

        assertEq(multisig.isOwner(newOwner), true);
        assertEq(multisig.isOwner(OWNER3), false);
        assertEq(multisig.getOwnerCount(), 3);
    }

    function test_RevertWhen_SwapOwner_InvalidArgs() public {
        // new owner is zero address
        bytes memory dataZero = abi.encodeWithSelector(
            MultisigTimelock.swapOwner.selector,
            address(0),
            OWNER3
        );
        bytes32 txZero = _queueAndConfirm(address(multisig), dataZero);
        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txZero);

        // new owner already an owner
        bytes memory dataAlreadyOwner = abi.encodeWithSelector(
            MultisigTimelock.swapOwner.selector,
            OWNER1,
            OWNER3
        );
        bytes32 txAlready = _queueAndConfirm(address(multisig), dataAlreadyOwner);
        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txAlready);

        // past owner is not an owner
        bytes memory dataNotOwner = abi.encodeWithSelector(
            MultisigTimelock.swapOwner.selector,
            address(0x8001),
            USER1
        );
        bytes32 txNotOwner = _queueAndConfirm(address(multisig), dataNotOwner);
        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txNotOwner);

        // new owner equals past owner
        bytes memory dataDuplicate = abi.encodeWithSelector(
            MultisigTimelock.swapOwner.selector,
            OWNER3,
            OWNER3
        );
        bytes32 txDuplicate = _queueAndConfirm(address(multisig), dataDuplicate);
        vm.prank(OWNER1);
        vm.expectRevert(MultisigTimelock.CallFailed.selector);
        multisig.executeTransaction(txDuplicate);
    }


    ///////////// View functions


    function test_isQueued() public {
        assertEq(multisig.isQueued(0), false);
        bytes32 txHash = addToQueueDefaultTx();
        assertEq(multisig.isQueued(txHash), true);
    }

    function test_getOwners() public {
        address[] memory owner = multisig.getOwners();
        assertEq(owner[0], OWNER1);
        assertEq(owner[1], OWNER2);
        assertEq(owner[2], OWNER3);
    }

    function test_getTransactionDetails() public {
        bytes32 txHash = addToQueueDefaultTx();
        multisig.getTransactionDetails(txHash);
    }

    function test_hasApproved() public {
        bytes32 txHash = addToQueueDefaultTx();

        assertEq(multisig.hasApproved(txHash, OWNER1), false);
        
        vm.prank(OWNER1);
        multisig.confirm(txHash);

        assertEq(multisig.hasApproved(txHash, OWNER1), true);
    }

    function test_isOwner() public {
        assertEq(multisig.isOwner(OWNER1), true);
        assertEq(multisig.isOwner(USER1), false);
    }

    function test_getMinApprovals() public {
        assertEq(multisig.getMinApprovals(), 2);
    }

    function test_getMaxDelay() public {
        assertEq(multisig.getMaxDelay(), MAX_DELAY);
        
    }

    function test_getOwnerCount() public {
        assertEq(multisig.getOwnerCount(), 3);
    }
}