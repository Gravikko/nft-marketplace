// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {ERC721Collection} from "./ERC721Collection.sol";

/// @title Interface for MultisigTimelock verification
interface IMultisigTimelock {
    function verifyCurrentTransaction() external view;
}

/// @title An NFT Creation contract with multiple choices of reveal types
/// @notice This is an upgradeable ERC721 collection with royalties support

contract Factory is 
    Initializable, 
    UUPSUpgradeable
{
    uint256 private _collectionsIdCounter;
    uint256 public constant MAX_SUPPLY = 20_000;
    address private _marketplace; 
    address private _beacon;
    address private _vrfAdapter;
    address private _multisigTimelock;
    bool private _isFactoryActive;
    mapping(uint256 => address) public collectionIdToOwner;
    mapping(uint256 => address) public collectionIdToAddress;
    mapping(address => uint256) public collectionAddressToId;
    mapping(address => uint256[]) public userCollections;

    /* Events */
    event BeaconSet(address indexed beacon);
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        address indexed collectionAddress,
        string name,
        string symbol
    );
    event FactoryIsActive();
    event FactoryIsStopped();
    event MultisigTimelockSet(address indexed multisigTimelock);
    event NewMarketplaceAddressSet(address indexed marketplace);
    event VRFAdapterSet(address indexed vrfAdapter);

    /* Errors */
    error AddressHasNoCollections();
    error BeaconIsAlreadySet();
    error CollectionDoesNotExist();
    error FactoryIsActiveAlready();
    error FactoryIsStopped();
    error FactoryIsStoppedAlready();
    error IncorrectBatchMintSupply();
    error IncorrectCollectionSupply();
    error IncorrectMintPrice();
    error IncorrectRevealType();
    error IncorrectRoyaltyFee();
    error MarketplaceAddressIsNotSet();
    error MultisigTimelockNotSet();
    error NoBeaconAddressSet();
    error NoVRFAdapterSet();
    error NotAMultisigTimelock();
    error NotMultisigTimelock();
    error ZeroAddress();

    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) {
            revert NotAMultisigTimelock();
        }
        // Verify that this call is part of an approved multisig transaction
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
        _;
    }

    constructor() {
        _disableInitializers();
    }    

    /**
     * Initializer
     */
    function initialize(address multisigTimelock) external initializer {
        _collectionsIdCounter = 1;
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
    }

    /**
     * @dev Set new MultisigTimelock address
     */
    function setMultisigTimelock(address newMultisigTimelock) external onlyMultisig {
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
    }

    /**
     * @dev Set new VRF Adapter address
     */
    function setVRFAdapter(address newVRFAdapter) external onlyMultisig {
        _vrfAdapter = newVRFAdapter;
        emit VRFAdapterSet(newVRFAdapter);
    }

    /**
     * @dev Set new marketplace address
     */
    function setMarketplaceAddress(address marketplaceAddress) external onlyMultisig {
        if (marketplaceAddress == address(0)) revert ZeroAddress();
        _marketplace = marketplaceAddress;
        emit NewMarketplaceAddressSet(marketplaceAddress);
    }
 
    /**
     * @dev Set beacon address
     */
    function setCollectionBeaconAddress(address beaconAddress) external onlyMultisig {
        if (_beacon != address(0)) revert BeaconIsAlreadySet();
        if (beaconAddress == address(0)) revert ZeroAddress();
        _beacon = beaconAddress;
        emit BeaconSet(beaconAddress);
    }

    function createCollection(
        string memory name,
        string memory symbol, 
        string memory revealType,
        string memory baseURI,
        string memory _placeholderURI,
        address royaltyReceiver,
        uint96 royaltyFeeNumerator,
        uint256 maxSupply,
        uint256 mintPrice,
        uint256 batchMintSupply
    ) external returns (uint256 collectionId, address collectionAddress) {
        if (!_isFactoryActive) revert FactoryIsStopped();
        if (_vrfAdapter == address(0)) revert NoVRFAdapterSet();
        if (_beacon == address(0)) revert NoBeaconAddressSet();
        if (_marketplace == address(0)) revert MarketplaceAddressIsNotSet();
        if (maxSupply > MAX_SUPPLY || maxSupply == 0) revert IncorrectCollectionSupply();
        if (mintPrice == 0) revert IncorrectMintPrice();
        if (batchMintSupply > maxSupply) revert IncorrectBatchMintSupply();
        if (keccak256(bytes(revealType)) != keccak256(bytes("instant")) && 
            keccak256(bytes(revealType)) != keccak256(bytes("delayed"))) {
            revert IncorrectRevealType();
        }
        if (royaltyFeeNumerator > 10000) revert IncorrectRoyaltyFee();  // Max 100%

        collectionId = _collectionsIdCounter;
        unchecked {
            _collectionsIdCounter++;
        }

        bytes memory initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            name,
            symbol,
            revealType,
            baseURI,
            _placeholderURI,
            royaltyReceiver,
            royaltyFeeNumerator,
            maxSupply,
            mintPrice,
            batchMintSupply,
            _vrfAdapter
        );

        BeaconProxy proxy = new BeaconProxy(_beacon, initData);
        collectionAddress = address(proxy);

        userCollections[msg.sender].push(collectionId);
        collectionAddressToId[collectionAddress] = collectionId;
        collectionIdToOwner[collectionId] = msg.sender;
        collectionIdToAddress[collectionId] = collectionAddress;

        emit CollectionCreated(
            collectionId,
            msg.sender,
            collectionAddress,
            name,
            symbol
        );

        return (collectionId, collectionAddress);
    }

    /**
     * @dev Set Factory active
     */
    function activateFactory() external onlyMultisig {
        if (_isFactoryActive) revert FactoryIsActiveAlready();
        if (_marketplace == address(0)) revert MarketplaceAddressIsNotSet();
        if (_beacon == address(0)) revert NoBeaconAddressSet();
        _isFactoryActive = true;
        emit FactoryIsActive();
    }

    /**
     * @dev Set Factory stopped
     */
    function stopFactory() external onlyMultisig {
        if (!_isFactoryActive) revert FactoryIsStoppedAlready();
        _isFactoryActive = false;
        emit FactoryIsStopped();
    }


    /**
     * @dev Get beacon address
     */
    function getBeaconAddress() external view returns (address) {
        return _beacon;
    }

    /**
     * @dev Check Factory status
     */
    function isFactoryActive() external view returns (bool) {
        return _isFactoryActive;
    }
    /**
     * @dev Get collection owner
     */
    function getCollectionOwnerById(uint256 collectionId) public view returns (address) {
        if (collectionId == 0 || collectionId >= _collectionsIdCounter) revert CollectionDoesNotExist();
        return collectionIdToOwner[collectionId];
    }

    /**
     * @dev get collection id by proxy's address
     */
    function getCollectionIdByAddress(address collectionAddress) public view returns (uint256) {
        if (collectionAddress == address(0)) revert ZeroAddress();
        if (collectionAddressToId[collectionAddress] == 0) revert CollectionDoesNotExist();
        return collectionAddressToId[collectionAddress];
    }   

    /**
     * @dev get collection's proxy address by id
     */
    function getCollectionAddressById(uint256 collectionId) public view returns (address) {
        if (collectionId == 0 || collectionId >= _collectionsIdCounter) revert CollectionDoesNotExist();
        if (collectionIdToAddress[collectionId] == address(0)) revert ZeroAddress();
        return collectionIdToAddress[collectionId];
    }

    /**
     * @dev Get all address collection ids
     */
    function getAllAddressCollectionIds(address userAddress) 
        public
        view
        returns (uint256[] memory) {
        if (userAddress == address(0)) revert ZeroAddress();
        if (userCollections[userAddress].length == 0) revert AddressHasNoCollections();
        return userCollections[userAddress];
    }

    /**
     * @dev Returns the number of collections a user has
     */
    function getAddressCollectionAmount(address userAddress) public view returns (uint256) {
        if (userAddress == address(0)) revert ZeroAddress();
        return userCollections[userAddress].length;
    }

    /**
     * @dev Authorized upgrade. Required by UUPSUpgrade
     */
    function _authorizeUpgrade(address) internal override onlyMultisig {}
}