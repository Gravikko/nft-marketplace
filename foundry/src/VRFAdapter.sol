// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";

/// @title VRFAdapter
/// @notice Chainlink VRF v2.5 adapter for NFT collection reveals
/// @dev Acts as intermediary between ERC721Collection and Chainlink VRF
contract VRFAdapter is Initializable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct PendingRequest {
        address collection;
        uint256 tokenId;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IVRFCoordinatorV2Plus public vrfCoordinator;

    uint256 private _vrfSubscriptionId;
    bytes32 private _vrfKeyHash;
    uint32 private _vrfCallbackGasLimit;
    uint16 private _vrfRequestConfirmations;

    mapping(address => bool) private _authorizedCollections;
    mapping(uint256 => PendingRequest) private _pendingRequests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollectionAuthorized(address indexed collection, bool authorized);
    event VRFConfigUpdated(address indexed vrfCoordinator, uint256 indexed subscriptionId, bytes32 keyHash);
    event VRFRequested(uint256 indexed requestId, address indexed collection, uint256 indexed tokenId);
    event VRFRevealCompleted(uint256 indexed requestId, address indexed collection, uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRequest();
    error OnlyCoordinatorCanFulfill();
    error UnauthorizedCollection();
    error VRFNotConfigured();
    error VRFRequestFailed();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the VRF adapter
    /// @param _vrfCoordinator Address of Chainlink VRF Coordinator
    /// @param subscriptionId Chainlink subscription ID
    /// @param keyHash Key hash for VRF
    /// @param callbackGasLimit Gas limit for callback
    /// @param requestConfirmations Number of confirmations required
    function initialize(
        address _vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) external initializer {
        __Ownable_init(msg.sender);

        if (_vrfCoordinator == address(0)) revert ZeroAddress();

        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        _vrfSubscriptionId = subscriptionId;
        _vrfKeyHash = keyHash;
        _vrfCallbackGasLimit = callbackGasLimit;
        _vrfRequestConfirmations = requestConfirmations;

        emit VRFConfigUpdated(_vrfCoordinator, subscriptionId, keyHash);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets VRF configuration
    /// @param _vrfCoordinator Address of Chainlink VRF Coordinator
    /// @param subscriptionId Chainlink subscription ID
    /// @param keyHash Key hash for VRF
    /// @param callbackGasLimit Gas limit for callback
    /// @param requestConfirmations Number of confirmations required
    function setVRFConfig(
        address _vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) external onlyOwner {
        if (_vrfCoordinator == address(0)) revert ZeroAddress();

        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        _vrfSubscriptionId = subscriptionId;
        _vrfKeyHash = keyHash;
        _vrfCallbackGasLimit = callbackGasLimit;
        _vrfRequestConfirmations = requestConfirmations;

        emit VRFConfigUpdated(_vrfCoordinator, subscriptionId, keyHash);
    }

    /// @notice Authorizes or deauthorizes a collection contract
    /// @param collection Address of the collection contract
    /// @param authorized Whether to authorize or deauthorize
    function setAuthorizedCollection(address collection, bool authorized) external onlyOwner {
        if (collection == address(0)) revert ZeroAddress();
        _authorizedCollections[collection] = authorized;
        emit CollectionAuthorized(collection, authorized);
    }

    /// @notice Requests random number from Chainlink VRF for a token reveal
    /// @param tokenId The token ID to reveal
    /// @return requestId The VRF request ID
    function requestRandomness(uint256 tokenId) external nonReentrant returns (uint256 requestId) {
        if (!_authorizedCollections[msg.sender]) revert UnauthorizedCollection();
        if (address(vrfCoordinator) == address(0)) revert VRFNotConfigured();

        try vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: _vrfKeyHash,
                subId: _vrfSubscriptionId,
                requestConfirmations: _vrfRequestConfirmations,
                callbackGasLimit: _vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        ) returns (uint256 _requestId) {
            requestId = _requestId;
            _pendingRequests[requestId] = PendingRequest({collection: msg.sender, tokenId: tokenId});
            emit VRFRequested(requestId, msg.sender, tokenId);
        } catch {
            revert VRFRequestFailed();
        }
    }

    /// @notice Callback function called by Chainlink VRF Coordinator
    /// @param requestId The VRF request ID
    /// @param randomWords Array of random words
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != address(vrfCoordinator)) revert OnlyCoordinatorCanFulfill();
        _fulfillRandomWords(requestId, randomWords);
    }

    /// @notice Checks if a collection is authorized
    /// @param collection Address of the collection contract
    function isAuthorizedCollection(address collection) external view returns (bool) {
        return _authorizedCollections[collection];
    }

    /// @notice Returns pending request info
    /// @param requestId The VRF request ID
    /// @return collection The collection contract address
    /// @return tokenId The token ID
    function getPendingRequest(uint256 requestId) external view returns (address collection, uint256 tokenId) {
        PendingRequest memory request = _pendingRequests[requestId];
        return (request.collection, request.tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Handles the VRF response
    function _fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        PendingRequest memory request = _pendingRequests[requestId];

        if (request.collection == address(0)) revert InvalidRequest();

        IERC721Collection(request.collection).revealWithRandomNumber(request.tokenId, randomWords[0]);

        delete _pendingRequests[requestId];

        emit VRFRevealCompleted(requestId, request.collection, request.tokenId);
    }

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
