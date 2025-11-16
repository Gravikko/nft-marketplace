// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";

/// @title Interface for MultisigTimelock verification
interface IMultisigTimelock {
    function verifyCurrentTransaction() external view;
}

///@title An NFT staking contract
///@notice Users can stake their NFTs by transfering them to this contract
///@dev The contract implements IERC721Receiver to safely receive NFTs 

contract StakingNFT is 
    Initializable,
    UUPSUpgradeable,
    IERC721Receiver
{
    IFactory private _factory;
    uint256 private _rewardAmount;
    address private _multisigTimelock;
    bool private _isStakingActive;
    mapping(address => mapping(uint256 => address)) private _stakedNFT;
    mapping(address => mapping(uint256 => uint256)) private _stakedTimestamp;
    mapping(address => mapping(address => uint256[])) private _userStakedTokens;
    mapping(address => mapping(address => mapping(uint256 => bool))) private _userStakedNFT;

    /* Events */
    event NewFactoryAddressSet(address indexed factory);
    event NewMultisigTimelockSet(address indexed multisigTimelock);
    event NewRewardAmountSet(uint256 indexed amount);
    event NFTStaked(
        address indexed staker,
        uint256 indexed collectionId,
        uint256 indexed tokenId,
        uint256 timestamp
    );
    event NFTUnstaked(
        address indexed staker,
        uint256 indexed collectionId,
        uint256 indexed tokenId,
        uint256 timestamp
    );
    event StakingIsActive();
    event StakingIsStopped();

    /* Errors */
    error InvalidCollectionAddress();
    error InvalidTimestamp();
    error InsufficientContractBalance();
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
    error StakingIsNotActive();
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
     * @dev Stop staking contract
     */
    function stopStaking() external onlyMultisig {
        if (!_isStakingActive) revert StakingAlreadyStopped();
        _isStakingActive = false;
        emit StakingIsStopped();
    }

    /**
     * @dev Activate staking contract
     */
    function activateStaking() external onlyMultisig {
        if (_isStakingActive) revert StakingAlreadyActive();
        _isStakingActive = true;
        emit StakingIsActive();
    }


    /**
     * @dev Sets new multisigTimelock address
     */
    function setMultisigTimelock(address multisigTimelock) external onlyMultisig {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        emit NewMultisigTimelockSet(multisigTimelock);
    } 
     
    function initialize(address multisigTimelock, address factory) external initializer {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        if (factory == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        _factory = IFactory(factory);
        _isStakingActive = false;
    }

    function setFactoryAddress(address newFactoryAddress) external onlyMultisig {
        if (newFactoryAddress == address(0)) revert ZeroAddress();
        _factory = IFactory(newFactoryAddress);
        emit NewFactoryAddressSet(newFactoryAddress);
    }

    /**
     * @dev Stake an NFT
     * @notice User must approve this contract to transfer the NFT before calling this function
     * @param collectionId The ID of the collection
     * @param tokenId The ID of the token to stake
     */
    function stake(uint256 collectionId, uint256 tokenId) external {
        if (!_isStakingActive) revert StakingIsNotActive();
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        if (collectionAddress == address(0)) revert InvalidCollectionAddress();

        IERC721Collection collection = IERC721Collection(collectionAddress);
        if (collection.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();

        if (_stakedNFT[collectionAddress][tokenId] != address(0)) revert NFTAlreadyStaked();

        if (!collection.isTokenApproved(tokenId, address(this))) revert NoApprovedForStakingContract();

        collection.safeTransferFrom(msg.sender, address(this), tokenId);

        _stakedNFT[collectionAddress][tokenId] = msg.sender;
        _userStakedNFT[msg.sender][collectionAddress][tokenId] = true;
        _userStakedTokens[msg.sender][collectionAddress].push(tokenId);
        _stakedTimestamp[collectionAddress][tokenId] = block.timestamp;

        emit NFTStaked(
            msg.sender,
            collectionId,
            tokenId,
            block.timestamp
        );
    }

    /**
     * @dev Unstake an NFT
     * @param collectionId The ID of the collection
     * @param tokenId The ID of the token to stake
     */
    function unstakeNFT(uint256 collectionId, uint256 tokenId) external {
        if (!_isStakingActive) revert StakingIsNotActive();
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        if (collectionAddress == address(0)) revert InvalidCollectionAddress();

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
        (bool success, ) = payable(msg.sender).call{value: reward}("");

        if (!success) revert PaymentFailed();

        delete _stakedTimestamp[collectionAddress][tokenId];

        emit NFTUnstaked(
            msg.sender,
            collectionId,
            tokenId,
            block.timestamp
        );
    }



    /**
     * @dev Set new reward amount per second
     */
    function setRewardAmount(uint256 amount) external onlyMultisig {
        _rewardAmount = amount;
        emit NewRewardAmountSet(amount);
    }   

    /**
     * @dev Get the staker address for a specific NFT
     * @param collectionId The ID of the collection
     * @param tokenId The ID of the token
     * @return The address of the staker, or address(0) if not staked
     */
    function getStaker(uint256 collectionId, uint256 tokenId) external view returns(address) {
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        if (collectionAddress == address(0)) revert InvalidCollectionAddress();

        return _stakedNFT[collectionAddress][tokenId];
    }

    /**
     * @dev Check if user staked current NFT
     * @param user The address of the user to check
     * @param collectionId The ID of the collection
     * @param tokenId The ID of the token to check
     * @return True if the user has staked the NFT, false otherwise
     */
    function checkUserStakeNFT(address user, uint256 collectionId, uint256 tokenId) external view returns (bool) {
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        if (collectionAddress == address(0)) revert InvalidCollectionAddress();

        return _userStakedNFT[user][collectionAddress][tokenId];
    }

    /**
     * @dev Get all staked token IDs for a user in a collection
     * @param user The address of the user
     * @param collectionId The ID of the collection
     * @return Array of staked token IDs
     */
    function getUserTokenStaked(address user, uint256 collectionId) external view returns(uint256[] memory) {
        if (address(_factory) == address(0)) revert NoFactoryAddress();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        if (collectionAddress == address(0)) revert InvalidCollectionAddress();

        return _userStakedTokens[user][collectionAddress];
    }


    /**
     * @dev Check if staking is active
     */
    function isStakingActive() external view returns(bool) {
        return _isStakingActive;
    }


    /**
     * @dev Implementation of IERC721Receiver to allow contract to receive NFTs
     * @notice This is required when receiving NFTs via safeTransferFrom
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    /**
     * @dev Get current rewards per second
     */
    function getRewardAmount() public view returns(uint256) {
        return _rewardAmount;
    }



    /**
     * @dev Authorized upgrade. Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address) internal override onlyMultisig {}

} 