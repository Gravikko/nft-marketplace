
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {VRFCoordinatorV2_5Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2_5Interface.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";

/// @title VRF Adapter for Chainlink VRF v2.5
/// @notice This contract acts as an intermediary between ERC721Collection and Chainlink VRF
interface IERC721Collection {
    function revealWithRandomNumber(uint256 tokenId, uint256 randomNumber) external;
}

/// @title VRF Adapter Contract
/// @notice Handles VRF requests and callbacks for NFT collections
/// @dev Note: VRFConsumerBaseV2Plus inherits from ConfirmedOwner, which conflicts with OwnableUpgradeable
///      For upgradeable contracts, we'll use a different pattern - storing coordinator address manually
contract VRFAdapter is 
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{

    struct PendingRequest {
        address collection;
        uint256 tokenId;
    }

    VRFCoordinatorV2_5Interface public s_vrfCoordinator;
    uint256 private _vrfSubscriptionId;
    bytes32 private _vrfKeyHash;
    uint32 private _vrfCallbackGasLimit;
    uint16 private _vrfRequestConfirmations; 
    mapping(address => bool) private _authorizedCollections;
    mapping(uint256 => PendingRequest) private _pendingRequests;

    /* Events */
    event CollectionAuthorized(address indexed collection, bool authorized);
    event VRFConfigUpdated(
        address indexed vrfCoordinator,
        uint256 indexed subscriptionId,
        bytes32 keyHash
    );
    event VRFRequested(
        uint256 indexed requestId,
        address indexed collection,
        uint256 indexed tokenId
    );
    event VRFRevealCompleted(
        uint256 indexed requestId,
        address indexed collection,
        uint256 indexed tokenId
    );

    /* Errors */
    error InvalidRequest();
    error OnlyCoordinatorCanFulfill();
    error UnauthorizedCollection();
    error VRFNotConfigured();
    error VRFRequestFailed();
    error ZeroAddress();

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param vrfCoordinator Address of Chainlink VRF Coordinator
     * @param subscriptionId Chainlink subscription ID
     * @param keyHash Key hash for VRF
     * @param callbackGasLimit Gas limit for callback
     * @param requestConfirmations Number of confirmations required
     */
    function initialize (
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) external initializer {
        __Ownable_init(msg.sender);

        if (vrfCoordinator == address(0)) {
            revert ZeroAddress();
        }

        s_vrfCoordinator = VRFCoordinatorV2_5Interface(vrfCoordinator);
        _vrfSubscriptionId = subscriptionId;
        _vrfKeyHash = keyHash;
        _vrfCallbackGasLimit = callbackGasLimit;
        _vrfRequestConfirmations = requestConfirmations;

        emit VRFConfigUpdated(vrfCoordinator, subscriptionId, keyHash);
    }

    /**
     * @dev Sets VRF configuration
     * @param vrfCoordinator Address of Chainlink VRF Coordinator
     * @param subscriptionId Chainlink subscription ID
     * @param keyHash Key hash for VRF
     * @param callbackGasLimit Gas limit for callback
     * @param requestConfirmations Number of confirmations required
     */
    function setVRFConfig(
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) external onlyOwner {
        if (vrfCoordinator == address(0)) {
            revert ZeroAddress();
        }

        s_vrfCoordinator = VRFCoordinatorV2_5Interface(vrfCoordinator);
        _vrfSubscriptionId = subscriptionId;
        _vrfKeyHash = keyHash;
        _vrfCallbackGasLimit = callbackGasLimit;
        _vrfRequestConfirmations = requestConfirmations;

        emit VRFConfigUpdated(vrfCoordinator, subscriptionId, keyHash);
    }

    /**
     * @dev Authorizes or deauthorizes a collection contract
     * @param collection Address of the collection contract
     * @param authorized Whether to authorize or deauthorize
     */
    function setAuthorizedCollection(address collection, bool authorized) external onlyOwner {
        if (collection == address(0)) {
            revert ZeroAddress();
        }
        _authorizedCollections[collection] = authorized;
        emit CollectionAuthorized(collection, authorized);
    }


    /**
     * @dev Requests random number from Chainlink VRF for a token reveal
     * @param tokenId The token ID to reveal
     * @return requestId The VRF request ID
     */
    function requestRandomness(uint256 tokenId) external nonReentrant returns (uint256 requestId) {
        if (!_authorizedCollections[msg.sender]) {
            revert UnauthorizedCollection();
        }

        if (address(s_vrfCoordinator) == address(0)) {
            revert VRFNotConfigured();
        }

        // Request VRF v2.5 randomness with native payment
        try s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: _vrfKeyHash,
                subId: _vrfSubscriptionId,
                requestConfirmations: _vrfRequestConfirmations,
                callbackGasLimit: _vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        ) returns (uint256 _requestId) {
            requestId = _requestId;
            _pendingRequests[requestId] = PendingRequest({
                collection: msg.sender,
                tokenId: tokenId
            });

            emit VRFRequested(requestId, msg.sender, tokenId);
        } catch {
            revert VRFRequestFailed();
        }
    }

    /**
     * @dev Callback function called by Chainlink VRF Coordinator
     * @param requestId The VRF request ID
     * @param randomWords Array of random words
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(s_vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill();
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Checks if a collection is authorized
     * @param collection Address of the collection contract
     * @return Whether the collection is authorized
     */
    function isAuthorizedCollection(address collection) external view returns (bool) {
        return _authorizedCollections[collection];
    }

    /**
     * @dev Get pending request info
     * @param requestId The VRF request ID
     * @return collection The collection contract address
     * @return tokenId The token ID
     */
    function getPendingRequest(uint256 requestId) 
        external 
        view 
        returns (address collection, uint256 tokenId) 
    {
        PendingRequest memory request = _pendingRequests[requestId];
        return (request.collection, request.tokenId);
    }

    /**
     * @dev Internal function to handle the VRF response
     * @param requestId The VRF request ID
     * @param randomWords Array of random words
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        PendingRequest memory request = _pendingRequests[requestId];
        
        if (request.collection == address(0)) {
            revert InvalidRequest();
        }

        // Call the collection contract's reveal function with the random number
        IERC721Collection(request.collection).revealWithRandomNumber(
            request.tokenId,
            randomWords[0]
        );

        // Clean up the pending request
        delete _pendingRequests[requestId];

        emit VRFRevealCompleted(requestId, request.collection, request.tokenId);
    }


    /**
     * @dev Authorizes upgrade. Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
