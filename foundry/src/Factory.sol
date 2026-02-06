// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BeaconProxy} from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {ERC721Collection} from "./ERC721Collection.sol";
import {IMultisigTimelock} from "./interfaces/IMultisigTimelock.sol";

/// @title Factory
/// @notice Creates and manages ERC721 NFT collections via beacon proxy pattern
/// @dev Uses UUPS upgradeable pattern with MultisigTimelock for admin operations
contract Factory is Initializable, UUPSUpgradeable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct CreateCollectionParams {
        string name;
        string symbol;
        string revealType;
        string baseURI;
        string placeholderURI;
        address royaltyReceiver;
        uint96 royaltyFeeNumerator;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 batchMintSupply;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_SUPPLY = 20_000;

    uint256 private _collectionsIdCounter;
    address private _marketplace;
    address private _beacon;
    address private _vrfAdapter;
    address private _multisigTimelock;
    bool private _isFactoryActive;

    mapping(uint256 => address) public collectionIdToOwner;
    mapping(uint256 => address) public collectionIdToAddress;
    mapping(address => uint256) public collectionAddressToId;
    mapping(address => uint256[]) public userCollections;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BeaconSet(address indexed beacon);
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        address indexed collectionAddress,
        string name,
        string symbol
    );
    event FactoryActivated();
    event FactoryStopped();
    event MultisigTimelockSet(address indexed multisigTimelock);
    event MarketplaceAddressSet(address indexed marketplace);
    event VRFAdapterSet(address indexed vrfAdapter);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

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
    error NoBeaconAddressSet();
    error NoVRFAdapterSet();
    error NotAMultisigTimelock();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) {
            revert NotAMultisigTimelock();
        }
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
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

    /// @notice Initializes the factory contract
    /// @param multisigTimelock Address of the MultisigTimelock contract
    function initialize(address multisigTimelock) external initializer {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _collectionsIdCounter = 1;
        _multisigTimelock = multisigTimelock;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new NFT collection
    /// @param params Collection creation parameters
    /// @return collectionId The ID of the created collection
    /// @return collectionAddress The address of the created collection proxy
    function createCollection(
        CreateCollectionParams calldata params
    ) external nonReentrant returns (uint256 collectionId, address collectionAddress) {
        if (!_isFactoryActive) revert FactoryIsStopped();
        if (_vrfAdapter == address(0)) revert NoVRFAdapterSet();
        if (_beacon == address(0)) revert NoBeaconAddressSet();
        if (_marketplace == address(0)) revert MarketplaceAddressIsNotSet();
        if (params.maxSupply > MAX_SUPPLY || params.maxSupply == 0) revert IncorrectCollectionSupply();
        if (params.mintPrice == 0) revert IncorrectMintPrice();
        if (params.batchMintSupply > params.maxSupply) revert IncorrectBatchMintSupply();

        bytes32 revealTypeHash = keccak256(bytes(params.revealType));
        if (
            revealTypeHash != keccak256(bytes("instant")) &&
            revealTypeHash != keccak256(bytes("delayed"))
        ) {
            revert IncorrectRevealType();
        }
        if (params.royaltyFeeNumerator > 10000) revert IncorrectRoyaltyFee();

        collectionId = _collectionsIdCounter;
        unchecked {
            _collectionsIdCounter++;
        }

        ERC721Collection.InitConfig memory initConfig = ERC721Collection.InitConfig({
            name: params.name,
            symbol: params.symbol,
            revealType: params.revealType,
            baseURI: params.baseURI,
            placeholderURI: params.placeholderURI,
            royaltyReceiver: params.royaltyReceiver,
            royaltyFeeNumerator: params.royaltyFeeNumerator,
            maxSupply: params.maxSupply,
            mintPrice: params.mintPrice,
            batchMintSupply: params.batchMintSupply,
            vrfAdapter: _vrfAdapter
        });

        bytes memory initCalldata = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            initConfig
        );

        BeaconProxy proxy = new BeaconProxy(_beacon, initCalldata);
        collectionAddress = address(proxy);

        userCollections[msg.sender].push(collectionId);
        collectionAddressToId[collectionAddress] = collectionId;
        collectionIdToOwner[collectionId] = msg.sender;
        collectionIdToAddress[collectionId] = collectionAddress;

        emit CollectionCreated(
            collectionId,
            msg.sender,
            collectionAddress,
            params.name,
            params.symbol
        );

        return (collectionId, collectionAddress);
    }

    /// @notice Activates the factory
    function activateFactory() external onlyMultisig {
        if (_isFactoryActive) revert FactoryIsActiveAlready();
        if (_marketplace == address(0)) revert MarketplaceAddressIsNotSet();
        if (_beacon == address(0)) revert NoBeaconAddressSet();
        _isFactoryActive = true;
        emit FactoryActivated();
    }

    /// @notice Stops the factory
    function stopFactory() external onlyMultisig {
        if (!_isFactoryActive) revert FactoryIsStoppedAlready();
        _isFactoryActive = false;
        emit FactoryStopped();
    }

    /// @notice Sets a new MultisigTimelock address
    /// @param newMultisigTimelock The new MultisigTimelock address
    function setMultisigTimelock(address newMultisigTimelock) external onlyMultisig {
        if (newMultisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
    }

    /// @notice Sets the VRF adapter address
    /// @param newVRFAdapter The new VRF adapter address
    function setVRFAdapter(address newVRFAdapter) external onlyMultisig {
        if (newVRFAdapter == address(0)) revert ZeroAddress();
        _vrfAdapter = newVRFAdapter;
        emit VRFAdapterSet(newVRFAdapter);
    }

    /// @notice Sets the marketplace address
    /// @param marketplaceAddress The new marketplace address
    function setMarketplaceAddress(address marketplaceAddress) external onlyMultisig {
        if (marketplaceAddress == address(0)) revert ZeroAddress();
        _marketplace = marketplaceAddress;
        emit MarketplaceAddressSet(marketplaceAddress);
    }

    /// @notice Sets the collection beacon address
    /// @param beaconAddress The beacon address
    function setCollectionBeaconAddress(address beaconAddress) external onlyMultisig {
        if (_beacon != address(0)) revert BeaconIsAlreadySet();
        if (beaconAddress == address(0)) revert ZeroAddress();
        _beacon = beaconAddress;
        emit BeaconSet(beaconAddress);
    }

    /// @notice Returns the beacon address
    function getBeaconAddress() external view returns (address) {
        return _beacon;
    }

    /// @notice Returns the MultisigTimelock address
    function getMultisigTimelock() external view returns (address) {
        return _multisigTimelock;
    }

    /// @notice Returns whether the factory is active
    function isFactoryActive() external view returns (bool) {
        return _isFactoryActive;
    }

    /// @notice Returns the marketplace address
    function getMarketplaceAddress() external view returns (address) {
        return _marketplace;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the owner of a collection by ID
    /// @param collectionId The collection ID
    function getCollectionOwnerById(uint256 collectionId) public view returns (address) {
        if (collectionId == 0 || collectionId >= _collectionsIdCounter) revert CollectionDoesNotExist();
        return collectionIdToOwner[collectionId];
    }

    /// @notice Returns the collection ID by its address
    /// @param collectionAddress The collection proxy address
    function getCollectionIdByAddress(address collectionAddress) public view returns (uint256) {
        if (collectionAddress == address(0)) revert ZeroAddress();
        if (collectionAddressToId[collectionAddress] == 0) revert CollectionDoesNotExist();
        return collectionAddressToId[collectionAddress];
    }

    /// @notice Returns the collection address by its ID
    /// @param collectionId The collection ID
    function getCollectionAddressById(uint256 collectionId) public view returns (address) {
        if (collectionId == 0 || collectionId >= _collectionsIdCounter) revert CollectionDoesNotExist();
        if (collectionIdToAddress[collectionId] == address(0)) revert ZeroAddress();
        return collectionIdToAddress[collectionId];
    }

    /// @notice Returns all collection IDs owned by a user
    /// @param userAddress The user address
    function getAllAddressCollectionIds(address userAddress) public view returns (uint256[] memory) {
        if (userAddress == address(0)) revert ZeroAddress();
        if (userCollections[userAddress].length == 0) revert AddressHasNoCollections();
        return userCollections[userAddress];
    }

    /// @notice Returns the number of collections owned by a user
    /// @param userAddress The user address
    function getAddressCollectionAmount(address userAddress) public view returns (uint256) {
        if (userAddress == address(0)) revert ZeroAddress();
        return userCollections[userAddress].length;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override onlyMultisig {}
}
