// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMultisigTimelock
/// @notice Interface for MultisigTimelock verification
interface IMultisigTimelock {
    /// @notice Verifies that the current call is part of an approved multisig transaction
    /// @dev Reverts if not called during an active multisig transaction execution
    function verifyCurrentTransaction() external view;
}
