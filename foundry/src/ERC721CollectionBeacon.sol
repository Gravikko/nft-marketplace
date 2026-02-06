// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBeacon} from "openzeppelin-contracts/proxy/beacon/IBeacon.sol";
import {IMultisigTimelock} from "./interfaces/IMultisigTimelock.sol";

/// @title ERC721CollectionBeacon
/// @notice Beacon contract for ERC721Collection proxy upgrades
/// @dev Controlled by MultisigTimelock for secure upgrades
contract ERC721CollectionBeacon is IBeacon {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address private _multisigTimelock;
    address private _implementation;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MultisigTimelockSet(address indexed multisigTimelock);
    event Upgraded(address indexed implementation);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error BeaconInvalidImplementation();
    error MultisigTimelockInvalidImplementation();
    error NotMultisigTimelock();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) revert NotMultisigTimelock();
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates the beacon with initial implementation
    /// @param initialImplementation The initial implementation address
    /// @param multisigTimelock The MultisigTimelock address
    constructor(address initialImplementation, address multisigTimelock) {
        if (initialImplementation == address(0)) revert ZeroAddress();
        if (multisigTimelock == address(0)) revert ZeroAddress();
        if (initialImplementation.code.length == 0) revert BeaconInvalidImplementation();

        _implementation = initialImplementation;
        _multisigTimelock = multisigTimelock;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Upgrades the beacon to a new implementation
    /// @param newImplementation The new implementation address
    function upgradeTo(address newImplementation) external virtual onlyMultisig {
        if (newImplementation == address(0)) revert ZeroAddress();
        if (newImplementation.code.length == 0) revert BeaconInvalidImplementation();
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    /// @notice Sets a new MultisigTimelock address
    /// @param newMultisigTimelock The new MultisigTimelock address
    function setMultisigTimelock(address newMultisigTimelock) external virtual onlyMultisig {
        if (newMultisigTimelock == address(0)) revert ZeroAddress();
        if (newMultisigTimelock.code.length == 0) revert MultisigTimelockInvalidImplementation();
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
    }

    /// @notice Returns the MultisigTimelock address
    function getMultisigTimelock() external view returns (address) {
        return _multisigTimelock;
    }

    /// @notice Returns the current implementation address
    function implementation() external view virtual returns (address) {
        return _implementation;
    }
}
