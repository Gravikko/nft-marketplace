// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 

/// @title Multisig Timelock Controller 
/// @notice Reusable multisig + timelock for upgradeable contract

contract MultisigTimelock is 
    Initializable, 
    ReentrancyGuard, 
    UUPSUpgradeable
{

    struct QueuedTransaction {
        address target;
        bytes data;
        uint256 value;
        uint256 timestamp;
        uint256 gracePeriod;
        uint256 approvalCount;
        bool executed;
        bytes32 txType;
    }

    uint256 private _minApprovals;
    uint256 private _maxDelay;
    uint256 private constant MIN_GRACE_PERIOD = 1 days;
    address[] private _owners;
    bytes32 private _currentExecutingTxId = bytes32(0);
    mapping(address => bool) private _isOwner;
    mapping(bytes32 => QueuedTransaction) private _queuedTransactions;
    mapping(bytes32 => mapping(address => bool)) private _approvals;
    mapping(bytes32 => bool) private _queue;


    /* Events */
    event Cancelled(bytes32 txId);
    event ConfirmationCancelled(bytes32 txId, address owner);
    event Confirmed(bytes32 txId, address owner);
    event Executed(bytes32 txId);
    event NewOwnerAdded(address newOwner);
    event OwnerDeleted(address pastOwner);
    event Queued(bytes32 txId);
    
    /* Errors */
    error AlreadyQueued();
    error AddressIsNotAnOwner();
    error AddressIsOwnerAlready();
    error AmountOfOwnersIsNoLessMinApprovalsNumber();
    error CallFailed();
    error DelayTooLong();
    error DuplicatedOwners();
    error ExecutionWindowIsStarted();
    error InvalidApprovalAmount();
    error InvalidGracePeriod();
    error InvalidOwner();
    error InvalidOwnersList();
    error NoRightsToChangeOwners();
    error NotAnOwner();
    error NotEnoughApprovals();
    error OwnerNotFound();
    error TooEarly();
    error TxAlreadyConfirmedByThisAddress();
    error TxAlreadyExecuted();
    error TxExpired();
    error TxIsNotConfirmedByThisAddress();
    error TxNotQueued();
    error UnauthorizedUpgrade();
    error ZeroAddressCanNotBeOwner();

    
    modifier onlyMultisig() {
        if (!_isOwner[msg.sender]) {
            revert NotAnOwner();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }    
    
    /**
     * @dev Adds to queue new Tx
     */
    function addToQueue(
        address _target,
        bytes calldata _data,
        uint256 _value,
        uint256 _timestamp,
        uint256 _gracePeriod,
        bytes32 _txType
    ) external onlyMultisig returns (bytes32 txHash) {
        if (_gracePeriod < MIN_GRACE_PERIOD) revert InvalidGracePeriod();
        if (_timestamp > block.timestamp + _maxDelay) revert DelayTooLong();
        if (_timestamp < block.timestamp) revert TooEarly();

        txHash = keccak256(abi.encodePacked(
            _target,
            _data, 
            _value,
            _timestamp
        ));

        if(_queue[txHash]) revert AlreadyQueued();

        _queue[txHash] = true;
        
        _queuedTransactions[txHash] = QueuedTransaction({
            target: _target,
            data: _data,
            value: _value,
            timestamp: _timestamp,
            gracePeriod: _gracePeriod,
            approvalCount: 0, // Start at 0, will be incremented by confirmations
            executed: false,
            txType: _txType
        });

        emit Queued(txHash);
        return txHash;
    }

    /**
     * @dev Confirm the current Tx by one of the multisig adderss
     */
    function confirm(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();
        if (_approvals[_txId][msg.sender]) revert TxAlreadyConfirmedByThisAddress();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();

        transaction.approvalCount++;
        _approvals[_txId][msg.sender] = true;
        
        emit Confirmed(_txId, msg.sender);
    }

    /**
     * @dev Cancel the confirmation of the current Tx by one of the multisig adderss
     */
    function cancelConfirmation(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();
        if (!_approvals[_txId][msg.sender]) revert TxIsNotConfirmedByThisAddress();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();

        transaction.approvalCount--;
        _approvals[_txId][msg.sender] = false;
        
        emit ConfirmationCancelled(_txId, msg.sender);
    }

    /**
     * @dev Execute current tx approved by enough amount of owners
     */
    function executeTransaction(bytes32 _txId) external payable nonReentrant {
        if (!_queue[_txId]) revert TxNotQueued();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];

        if (transaction.executed) revert TxAlreadyExecuted();
        if (block.timestamp < transaction.timestamp) revert TooEarly();
        if (block.timestamp > transaction.timestamp + transaction.gracePeriod) revert TxExpired();
        if (transaction.approvalCount < _minApprovals) revert NotEnoughApprovals();

        // Store values before deletion
        address target = transaction.target;
        bytes memory data = transaction.data;
        uint256 value = transaction.value;

        // Set executing txId BEFORE the call so checks can verify during execution
        // Note: We don't mark as executed yet because verifyCurrentTransaction()
        // verifies it's not executed, and we need that check to work during the call
        _currentExecutingTxId = _txId;
        
        // Make the call - during this call, verifyCurrentTransaction() can verify
        // the transaction is approved and not already executed
        (bool success, bytes memory response) = target.call{value: value}(data);
        
        if (!success) {
            // Clear executing txId on failure (revert will undo this, but good practice)
            _currentExecutingTxId = bytes32(0);
            revert CallFailed();
        }
        
        // Mark as executed and clean up AFTER successful call
        // nonReentrant modifier protects against reentrancy
        transaction.executed = true;
        _currentExecutingTxId = bytes32(0);
        delete _queue[_txId];
        delete _queuedTransactions[_txId];
        
        emit Executed(_txId);
    } 

    /**
     * @dev Cancel a queued Tx (Before execution window started)
     * @param _txId The transaction id to cancel
     */
    function cancelTransaction(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();
        if (transaction.timestamp <= block.timestamp) revert ExecutionWindowIsStarted();

        delete _queue[_txId];
        delete _queuedTransactions[_txId];

        emit Cancelled(_txId);
    }

    /**
     * @dev Add address to owners
     */
    function addOwner(address newOwner) external {
        verifyCurrentTransaction();
        if (msg.sender != address(this)) revert NoRightsToChangeOwners();
        if (newOwner == address(0)) revert ZeroAddressCanNotBeOwner();
        if (_isOwner[newOwner]) revert AddressIsOwnerAlready();
        _isOwner[newOwner] = true;
        _owners.push(newOwner);
        emit NewOwnerAdded(newOwner);
    }

    /**
     * @dev Delete owner from mapping
     */
    function deleteOwner(address pastOwner) external {
        verifyCurrentTransaction();
        if (msg.sender != address(this)) revert NoRightsToChangeOwners();
        if (!_isOwner[pastOwner]) revert AddressIsNotAnOwner();
        if (_owners.length <= _minApprovals) revert AmountOfOwnersIsNoLessMinApprovalsNumber();
        
        for (uint256 i = 0; i < _owners.length; ++i) {
            if (_owners[i] == pastOwner) {
                _owners[i] = _owners[_owners.length - 1];
                _owners.pop();
                delete _isOwner[pastOwner];
                emit OwnerDeleted(pastOwner);
                return;
            }
        }
        revert OwnerNotFound();
    }
    
    /**
     * @dev Add new owner and delete past owner
     */
    function swapOwner(address newOwner, address pastOwner) external {
        verifyCurrentTransaction();
        if (msg.sender != address(this)) revert NoRightsToChangeOwners();
        if (newOwner == address(0)) revert ZeroAddressCanNotBeOwner();
        if (_isOwner[newOwner]) revert AddressIsOwnerAlready();
        if (!_isOwner[pastOwner]) revert AddressIsNotAnOwner();
        if (newOwner == pastOwner) revert DuplicatedOwners();
        
        // Add new owner first
        _isOwner[newOwner] = true;
        _owners.push(newOwner);
        emit NewOwnerAdded(newOwner);
        
        // Then delete old owner
        for (uint256 i = 0; i < _owners.length; ++i) {
            if (_owners[i] == pastOwner) {
                _owners[i] = _owners[_owners.length - 1];
                _owners.pop();
                delete _isOwner[pastOwner];
                emit OwnerDeleted(pastOwner);
                return;
            }
        }
        revert OwnerNotFound();
    }

    /**
     * @dev Check if a transactions is queued
     * @param _txId The transaction ID
     */
    function isQueued(bytes32 _txId) external view returns(bool) {
        return _queue[_txId];
    }
 
    /**
     * @dev Get all owners
     */
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }
    
    /**
     * @dev Get transaction details
     * @param _txId The transaction ID
     */
    function getTransactions(bytes32 _txId) external view returns(QueuedTransaction memory transaction) {
        transaction = _queuedTransactions[_txId];
    }

    /**
     * @dev Check if an owner approved Transaction
     * @param _txId The transaction ID
     */
    function hasApproved(bytes32 _txId, address _owner) external view returns(bool) {
        return _approvals[_txId][_owner];
    }

    /**
     * @dev Check if address is owner
     */
    function isOwner(address _address) external view returns(bool) {
        return _isOwner[_address];
    }

    /**
     * @dev Get minimum approvals amount
     */
    function getMinApprovals() external view returns(uint256) {
        return _minApprovals;
    }

    /**
     * @dev Get maximum delay time
     */
    function getMaxDelay() external view returns(uint256) {
        return _maxDelay;
    }

    /**
     * @dev Get number of owners
     */
    function getOwnerCount() external view returns(uint256) {
        return _owners.length;
    }
    
    /**
     * @dev Verify that the current executing transaction is legitimate
     * @notice This function is called by external contracts (like Factory) to verify
     *         that they are being called as part of an approved multisig transaction
     */
    function verifyCurrentTransaction() public view {
        if (_currentExecutingTxId == bytes32(0)) revert UnauthorizedUpgrade();
        if (!_queue[_currentExecutingTxId]) revert TxNotQueued();

        QueuedTransaction storage tx = _queuedTransactions[_currentExecutingTxId];
        if (tx.approvalCount < _minApprovals) revert NotEnoughApprovals();
        if (tx.executed) revert TxAlreadyExecuted();
        
        // Verify that the caller is the target of the current transaction
        if (tx.target != msg.sender) revert UnauthorizedUpgrade();
    }

    /**
     * @dev Initialize the multisig timelock
     * @param owners Array of initial owners
     * @param minApprovals Minimum number for approvals required
     * @param maxDelay Maximum number before execution is possible
     */
    function __MultisigTimelock_init(
        address[] memory owners,
        uint256 minApprovals,
        uint256 maxDelay
    ) internal onlyInitializing {
        if (owners.length == 0) revert InvalidOwner();
        if (minApprovals == 0) revert InvalidApprovalAmount();
        if (minApprovals > owners.length) revert InvalidOwnersList();

        _minApprovals = minApprovals;
        _maxDelay = maxDelay;
        
        for (uint256 i = 0; i < owners.length; ++i) {
            address nextOwner = owners[i];
            if (nextOwner == address(0)) revert ZeroAddressCanNotBeOwner();
            if (_isOwner[nextOwner]) revert DuplicatedOwners();
            _isOwner[nextOwner] = true;
            _owners.push(nextOwner);
        }
    }

    /**
     * @dev Required by UUPS standard
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        verifyCurrentTransaction();
    } 
} 