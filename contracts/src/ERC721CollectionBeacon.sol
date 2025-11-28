// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBeacon} from "openzeppelin-contracts/proxy/beacon/IBeacon.sol";

interface IMultisigTimelock {
    function verifyCurrentTransaction() external view;
}

contract ERC721CollectionBeacon is 
    IBeacon
{
    address private _multisigTimelock;
    address private _implementation;

    /* Events */
    event MultisigTimelockSet(address indexed multisigTimelock);
    event Upgraded(address indexed implementation);

    /* Errors */
    error BeaconInvalidImplementation();
    error MultisigTimelockInvalidImplementation();
    error NotMultisigTimelock();
    error ZeroAddress();

    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) {
            revert NotMultisigTimelock();
        }
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
        _;
    }

    /**
     * @dev Sets the address of the initial implementation and multisigTimelock
     * @param implementation_ The initial implementation address
     * @param multisigTimelock The initial multisigTimelock address
     */
    constructor (address implementation_, address multisigTimelock) {
        if (implementation_ == address(0)) revert ZeroAddress();
        if (multisigTimelock == address(0)) revert ZeroAddress();
        if (implementation_.code.length == 0) revert BeaconInvalidImplementation();

        _implementation = implementation_;
        _multisigTimelock = multisigTimelock;
    }
 
    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the multisig timelock (via approved transaction).
     * - `newImplementation` must be a contract.
     */
    function upgradeTo(address newImplementation) external virtual onlyMultisig {
        if (newImplementation == address(0)) revert ZeroAddress();
        if (newImplementation.code.length == 0) revert BeaconInvalidImplementation();
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Upgrades multisigTimelock address
     */
    function setMultisigTimelock(address newMultisigTimelock) external virtual onlyMultisig {
        if (newMultisigTimelock == address(0)) revert ZeroAddress();
        if (newMultisigTimelock.code.length == 0) revert MultisigTimelockInvalidImplementation();
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
    }

    /**
     * @dev Get the multisigTimelock address
     */
    function getMultisigTimelock() external view returns(address) {
        return _multisigTimelock;
    }

    /**
     * @dev Returns the current implementation address
     */
    function implementation() external view virtual returns (address) {
        return _implementation;
    }
}