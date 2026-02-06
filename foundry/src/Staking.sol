// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";
import {IMultisigTimelock} from "./interfaces/IMultisigTimelock.sol";

/// @title StakingNFT
/// @notice NFT staking contract with ETH rewards
/// @dev Users stake NFTs and earn rewards based on staking duration
contract StakingNFT is Initializable, UUPSUpgradeable, IERC721Receiver, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IFactory private _factory;
    uint256 private _rewardAmount;
    address private _multisigTimelock;
    bool private _isStakingActive;

    mapping(address => mapping(uint256 => address)) private _stakedNFT;
    mapping(address => mapping(uint256 => uint256)) private _stakedTimestamp;
    mapping(address => mapping(address => uint256[])) private _userStakedTokens;
    mapping(address => mapping(address => mapping(uint256 => bool))) private _userStakedNFT;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FactoryAddressSet(address indexed factory);
    event MultisigTimelockSet(address indexed multisigTimelock);
    event NFTStaked(address indexed staker, uint256 indexed collectionId, uint256 indexed tokenId, uint256 timestamp);
    event NFTUnstaked(address indexed staker, uint256 indexed collectionId, uint256 indexed tokenId, uint256 timestamp);
    event RewardAmountSet(uint256 indexed amount);
    event StakingActivated();
    event StakingStopped();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientContractBalance();
    error InvalidCollectionAddress();
    error InvalidTimestamp();
    error NFTAlreadyStaked();
    error NFTNotStaked();
    error NFTNotStakedByUser();
    error NoApprovedForStakingContract();
    error NoFactoryAddress();
    error NotAMultisigTimelock();
    error NotNFTOwner();
    error PaymentFailed();
    error StakingAlreadyActive();
    error StakingAlreadyStopped();
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

    modifier isActive() {
        if (!_isStakingActive) revert StakingAlreadyStopped();
        if (address(_factory) == address(0)) revert NoFactoryAddress();
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

    /// @notice Initializes the staking contract
    /// @param multisigTimelock Address of the MultisigTimelock contract
    function initialize(address multisigTimelock) external initializer {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        _isStakingActive = false;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes an NFT
    /// @param collectionId The collection ID
    /// @param tokenId The token ID to stake
    function stake(uint256 collectionId, uint256 tokenId) external nonReentrant isActive {
        address collectionAddress = getCollectionAddress(collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);

        if (_stakedNFT[collectionAddress][tokenId] != address(0)) revert NFTAlreadyStaked();
        if (collection.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
        if (!collection.isTokenApproved(tokenId, address(this))) revert NoApprovedForStakingContract();

        collection.safeTransferFrom(msg.sender, address(this), tokenId);

        _stakedNFT[collectionAddress][tokenId] = msg.sender;
        _userStakedNFT[msg.sender][collectionAddress][tokenId] = true;
        _userStakedTokens[msg.sender][collectionAddress].push(tokenId);
        _stakedTimestamp[collectionAddress][tokenId] = block.timestamp;

        emit NFTStaked(msg.sender, collectionId, tokenId, block.timestamp);
    }

    /// @notice Unstakes an NFT and claims rewards
    /// @param collectionId The collection ID
    /// @param tokenId The token ID to unstake
    function unstakeNFT(uint256 collectionId, uint256 tokenId) external nonReentrant isActive {
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress = getCollectionAddress(collectionId);
        if (_stakedNFT[collectionAddress][tokenId] != msg.sender) revert NFTNotStakedByUser();

        IERC721Collection collection = IERC721Collection(collectionAddress);
        address owner = collection.ownerOf(tokenId);
        if (owner != address(this)) revert NFTNotStaked();

        delete _stakedNFT[collectionAddress][tokenId];
        delete _userStakedNFT[msg.sender][collectionAddress][tokenId];

        uint256[] storage tokens = _userStakedTokens[msg.sender][collectionAddress];
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        collection.safeTransferFrom(address(this), msg.sender, tokenId);

        uint256 timePassed = block.timestamp - _stakedTimestamp[collectionAddress][tokenId];
        if (_stakedTimestamp[collectionAddress][tokenId] == 0 || timePassed == 0) revert InvalidTimestamp();

        uint256 reward = _rewardAmount * timePassed;
        if (address(this).balance < reward) revert InsufficientContractBalance();

        (bool success,) = payable(msg.sender).call{value: reward}("");
        if (!success) revert PaymentFailed();

        delete _stakedTimestamp[collectionAddress][tokenId];

        emit NFTUnstaked(msg.sender, collectionId, tokenId, block.timestamp);
    }

    /// @notice Activates the staking contract
    function activateStaking() external onlyMultisig {
        if (address(_factory) == address(0)) revert NoFactoryAddress();
        if (_isStakingActive) revert StakingAlreadyActive();
        _isStakingActive = true;
        emit StakingActivated();
    }

    /// @notice Stops the staking contract
    function stopStaking() external onlyMultisig isActive {
        _isStakingActive = false;
        emit StakingStopped();
    }

    /// @notice Sets the MultisigTimelock address
    /// @param multisigTimelock The new address
    function setMultisigTimelock(address multisigTimelock) external onlyMultisig {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        emit MultisigTimelockSet(multisigTimelock);
    }

    /// @notice Sets the factory address
    /// @param newFactoryAddress The new address
    function setFactoryAddress(address newFactoryAddress) external onlyMultisig {
        if (newFactoryAddress == address(0)) revert ZeroAddress();
        _factory = IFactory(newFactoryAddress);
        emit FactoryAddressSet(newFactoryAddress);
    }

    /// @notice Sets the reward amount per second
    /// @param amount The new reward amount
    function setRewardAmount(uint256 amount) external onlyMultisig {
        _rewardAmount = amount;
        emit RewardAmountSet(amount);
    }

    /// @notice Returns the staker address for a specific NFT
    /// @param collectionId The collection ID
    /// @param tokenId The token ID
    function getStaker(uint256 collectionId, uint256 tokenId) external view returns (address) {
        address collectionAddress = getCollectionAddress(collectionId);
        return _stakedNFT[collectionAddress][tokenId];
    }

    /// @notice Checks if a user has staked a specific NFT
    /// @param user The user address
    /// @param collectionId The collection ID
    /// @param tokenId The token ID
    function checkUserStakedNFT(address user, uint256 collectionId, uint256 tokenId) external view returns (bool) {
        address collectionAddress = getCollectionAddress(collectionId);
        return _userStakedNFT[user][collectionAddress][tokenId];
    }

    /// @notice Returns all staked token IDs for a user in a collection
    /// @param user The user address
    /// @param collectionId The collection ID
    function getUserStakedTokens(address user, uint256 collectionId) external view returns (uint256[] memory) {
        address collectionAddress = getCollectionAddress(collectionId);
        return _userStakedTokens[user][collectionAddress];
    }

    /// @notice Returns whether staking is active
    function isStakingActive() external view returns (bool) {
        return _isStakingActive;
    }

    /// @notice Returns the factory address
    function getFactoryAddress() external view returns (address) {
        return address(_factory);
    }

    /// @notice IERC721Receiver implementation
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the collection address by ID
    /// @param collectionId The collection ID
    function getCollectionAddress(uint256 collectionId) public view returns (address collectionAddress) {
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error(string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }
        if (collectionAddress == address(0)) revert InvalidCollectionAddress();
    }

    /// @notice Returns the current reward amount per second
    function getRewardAmount() public view returns (uint256) {
        return _rewardAmount;
    }

    /// @notice Returns the timestamp when a token was staked
    /// @param collectionId The collection ID
    /// @param tokenId The token ID
    function getStakedTimestamp(uint256 collectionId, uint256 tokenId) public view returns (uint256) {
        address collectionAddress = getCollectionAddress(collectionId);
        return _stakedTimestamp[collectionAddress][tokenId];
    }

    /// @notice Returns whether a user has staked a specific NFT (by address)
    /// @param user The user address
    /// @param collectionAddress The collection address
    /// @param tokenId The token ID
    function getUserStakedNFT(address user, address collectionAddress, uint256 tokenId) public view returns (bool) {
        return _userStakedNFT[user][collectionAddress][tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override onlyMultisig {}
}
