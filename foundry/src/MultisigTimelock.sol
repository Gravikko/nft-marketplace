// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

/// @title MultisigTimelock
/// @notice Multisig wallet with timelock for executing governance transactions
/// @dev Requires multiple owner approvals and a time delay before execution
contract MultisigTimelock is Initializable, ReentrancyGuard, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant MIN_GRACE_PERIOD = 1 days;

    uint256 private _minApprovals;
    uint256 private _maxDelay;
    address[] private _owners;
    bytes32 private _currentExecutingTxId;

    mapping(address => bool) private _isOwner;
    mapping(bytes32 => QueuedTransaction) private _queuedTransactions;
    mapping(bytes32 => mapping(address => bool)) private _approvals;
    mapping(bytes32 => bool) private _queue;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Cancelled(bytes32 txId);
    event ConfirmationCancelled(bytes32 txId, address owner);
    event Confirmed(bytes32 txId, address owner);
    event Executed(bytes32 txId);
    event OwnerAdded(address newOwner);
    event OwnerRemoved(address pastOwner);
    event Queued(bytes32 txId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AddressIsNotAnOwner();
    error AddressIsOwnerAlready();
    error AlreadyQueued();
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

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMultisig() {
        if (!_isOwner[msg.sender]) {
            revert NotAnOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the multisig timelock
    /// @param owners Array of initial owner addresses
    /// @param minApprovals Minimum number of approvals required
    /// @param maxDelay Maximum delay before execution is possible
    function initialize(
        address[] memory owners,
        uint256 minApprovals,
        uint256 maxDelay
    ) external initializer {
        __MultisigTimelock_init(owners, minApprovals, maxDelay);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a transaction to the queue
    /// @param _target Target contract address
    /// @param _data Transaction calldata
    /// @param _value ETH value to send
    /// @param _timestamp Execution timestamp
    /// @param _gracePeriod Time window for execution
    /// @param _txType Transaction type identifier
    /// @return txHash The transaction hash
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

        txHash = keccak256(abi.encodePacked(_target, _data, _value, _timestamp));

        if (_queue[txHash]) revert AlreadyQueued();

        _queue[txHash] = true;

        _queuedTransactions[txHash] = QueuedTransaction({
            target: _target,
            data: _data,
            value: _value,
            timestamp: _timestamp,
            gracePeriod: _gracePeriod,
            approvalCount: 0,
            executed: false,
            txType: _txType
        });

        emit Queued(txHash);
        return txHash;
    }

    /// @notice Confirms a queued transaction
    /// @param _txId The transaction hash
    function confirm(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();
        if (_approvals[_txId][msg.sender]) revert TxAlreadyConfirmedByThisAddress();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();

        transaction.approvalCount++;
        _approvals[_txId][msg.sender] = true;

        emit Confirmed(_txId, msg.sender);
    }

    /// @notice Cancels a confirmation for a transaction
    /// @param _txId The transaction hash
    function cancelConfirmation(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();
        if (!_approvals[_txId][msg.sender]) revert TxIsNotConfirmedByThisAddress();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();

        transaction.approvalCount--;
        _approvals[_txId][msg.sender] = false;

        emit ConfirmationCancelled(_txId, msg.sender);
    }

    /// @notice Executes a confirmed transaction
    /// @param _txId The transaction hash
    function executeTransaction(bytes32 _txId) external payable nonReentrant {
        if (!_queue[_txId]) revert TxNotQueued();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];

        if (transaction.executed) revert TxAlreadyExecuted();
        if (block.timestamp < transaction.timestamp) revert TooEarly();
        if (block.timestamp > transaction.timestamp + transaction.gracePeriod) revert TxExpired();
        if (transaction.approvalCount < _minApprovals) revert NotEnoughApprovals();

        address target = transaction.target;
        bytes memory data = transaction.data;
        uint256 value = transaction.value;

        _currentExecutingTxId = _txId;

        (bool success,) = target.call{value: value}(data);

        if (!success) {
            _currentExecutingTxId = bytes32(0);
            revert CallFailed();
        }

        transaction.executed = true;
        _currentExecutingTxId = bytes32(0);
        delete _queue[_txId];
        delete _queuedTransactions[_txId];

        emit Executed(_txId);
    }

    /// @notice Cancels a queued transaction
    /// @param _txId The transaction hash
    function cancelTransaction(bytes32 _txId) external onlyMultisig {
        if (!_queue[_txId]) revert TxNotQueued();

        QueuedTransaction storage transaction = _queuedTransactions[_txId];
        if (transaction.executed) revert TxAlreadyExecuted();
        if (transaction.timestamp <= block.timestamp) revert ExecutionWindowIsStarted();

        delete _queue[_txId];
        delete _queuedTransactions[_txId];

        emit Cancelled(_txId);
    }

    /// @notice Adds a new owner
    /// @param newOwner The new owner address
    function addOwner(address newOwner) external {
        verifyCurrentTransaction();
        if (msg.sender != address(this)) revert NoRightsToChangeOwners();
        if (newOwner == address(0)) revert ZeroAddressCanNotBeOwner();
        if (_isOwner[newOwner]) revert AddressIsOwnerAlready();

        _isOwner[newOwner] = true;
        _owners.push(newOwner);

        emit OwnerAdded(newOwner);
    }

    /// @notice Removes an owner
    /// @param pastOwner The owner to remove
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
                emit OwnerRemoved(pastOwner);
                return;
            }
        }
        revert OwnerNotFound();
    }

    /// @notice Swaps an owner for a new one
    /// @param newOwner The new owner address
    /// @param pastOwner The owner to replace
    function swapOwner(address newOwner, address pastOwner) external {
        verifyCurrentTransaction();
        if (msg.sender != address(this)) revert NoRightsToChangeOwners();
        if (newOwner == address(0)) revert ZeroAddressCanNotBeOwner();
        if (_isOwner[newOwner]) revert AddressIsOwnerAlready();
        if (!_isOwner[pastOwner]) revert AddressIsNotAnOwner();
        if (newOwner == pastOwner) revert DuplicatedOwners();

        _isOwner[newOwner] = true;
        _owners.push(newOwner);
        emit OwnerAdded(newOwner);

        for (uint256 i = 0; i < _owners.length; ++i) {
            if (_owners[i] == pastOwner) {
                _owners[i] = _owners[_owners.length - 1];
                _owners.pop();
                delete _isOwner[pastOwner];
                emit OwnerRemoved(pastOwner);
                return;
            }
        }
        revert OwnerNotFound();
    }

    /// @notice Checks if a transaction is queued
    /// @param _txId The transaction hash
    function isQueued(bytes32 _txId) external view returns (bool) {
        return _queue[_txId];
    }

    /// @notice Returns all owners
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    /// @notice Returns transaction details
    /// @param _txId The transaction hash
    function getTransactionDetails(bytes32 _txId) external view returns (QueuedTransaction memory) {
        return _queuedTransactions[_txId];
    }

    /// @notice Checks if an owner has approved a transaction
    /// @param _txId The transaction hash
    /// @param _owner The owner address
    function hasApproved(bytes32 _txId, address _owner) external view returns (bool) {
        return _approvals[_txId][_owner];
    }

    /// @notice Checks if an address is an owner
    /// @param _address The address to check
    function isOwner(address _address) external view returns (bool) {
        return _isOwner[_address];
    }

    /// @notice Returns the minimum approvals required
    function getMinApprovals() external view returns (uint256) {
        return _minApprovals;
    }

    /// @notice Returns the maximum delay
    function getMaxDelay() external view returns (uint256) {
        return _maxDelay;
    }

    /// @notice Returns the number of owners
    function getOwnerCount() external view returns (uint256) {
        return _owners.length;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the current executing transaction is legitimate
    /// @dev Called by external contracts to verify multisig authorization
    function verifyCurrentTransaction() public view {
        if (_currentExecutingTxId == bytes32(0)) revert UnauthorizedUpgrade();
        if (!_queue[_currentExecutingTxId]) revert TxNotQueued();

        QueuedTransaction storage txn = _queuedTransactions[_currentExecutingTxId];
        if (txn.approvalCount < _minApprovals) revert NotEnoughApprovals();
        if (txn.executed) revert TxAlreadyExecuted();
        if (txn.target != msg.sender) revert UnauthorizedUpgrade();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Initializes the multisig state
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

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override {
        verifyCurrentTransaction();
    }
}
