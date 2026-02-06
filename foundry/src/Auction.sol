// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "openzeppelin-contracts/interfaces/IERC2981.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";
import {IMultisigTimelock} from "./interfaces/IMultisigTimelock.sol";

/// @title Auction
/// @notice NFT auction contract with time-based bidding
/// @dev Supports royalties and fee distribution
contract Auction is Initializable, UUPSUpgradeable, ReentrancyGuard, IERC721Receiver {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Bid {
        address buyer;
        uint256 buyPrice;
    }

    struct AuctionInfo {
        address seller;
        address collectionAddress;
        uint256 tokenId;
        uint256 price;
        uint256 deadline;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant FEE_DENOMINATOR = 10_000;
    uint256 private constant PERCENT_DIVISOR = 100;
    uint256 private constant MIN_DURATION = 30 minutes;
    uint256 private constant MIN_PRICE = 1000 wei;
    uint256 private constant EXTENSION_TIME = 5 minutes;

    uint256 private _auctionCounter;
    uint256 private _maxDuration;
    uint256 private _minNextBidPercent;
    uint256 private _auctionBlockedAmount;
    uint256 private _auctionFeeAmount;
    bool private _isAuctionActive;
    address private _multisigTimelock;
    address private _auctionFeeReceiver;
    IFactory private _factory;

    mapping(uint256 => AuctionInfo) private _auctionInfo;
    mapping(uint256 => Bid[]) private _auctionBids;
    mapping(uint256 => bool) private _auctionFinished;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionActivated();
    event AuctionCancelled(address indexed seller, address indexed collectionAddress, uint256 indexed tokenId);
    event AuctionCreated(address indexed seller, uint256 indexed collectionId, uint256 indexed tokenId);
    event AuctionEnded(uint256 indexed auctionId);
    event AuctionFeeAmountSet(uint256 indexed newAuctionFeeAmount);
    event AuctionFeeReceiverSet(address indexed newFeeReceiver);
    event AuctionStopped();
    event BidPlaced(uint256 indexed auctionId, uint256 indexed newBid, address indexed user);
    event BidWithdrawn(uint256 indexed auctionId, address indexed userAddress);
    event FactoryAddressSet(address indexed newFactory);
    event MaxDurationSet(uint256 indexed newMaxDuration);
    event MinNextBidPercentSet(uint256 indexed newBidPercent);
    event MultisigTimelockSet(address indexed multisigTimelock);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AllBidsArePaid();
    error AuctionHasBids();
    error AuctionIsActiveAlready();
    error AuctionIsExpired();
    error AuctionIsNotFinished();
    error AuctionIsStoppedAlready();
    error InsufficientBalance();
    error InsufficientPayment();
    error InvalidAuction();
    error InvalidAuctionFeeAmount();
    error InvalidBidAddress();
    error InvalidDuration();
    error InvalidNextBidPercent();
    error InvalidPrice();
    error NoBidsMade();
    error NoFactoryAddressSet();
    error NotAMultisigTimelock();
    error NotAnAuctionAuthor();
    error NotATokenOwner();
    error OwnerCannotBid();
    error PaymentFailed();
    error UserBidNotFound();
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
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the auction contract
    /// @param multisigTimelock Address of the MultisigTimelock contract
    function initialize(address multisigTimelock) external initializer {
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        _maxDuration = 7 days;
        _minNextBidPercent = 5;
        _auctionCounter = 1;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates an auction for an NFT
    /// @param collectionId The collection ID
    /// @param tokenId The token ID
    /// @param duration Auction duration in seconds
    /// @param minimumBid Minimum starting bid
    function putTokenOnAuction(
        uint256 collectionId,
        uint256 tokenId,
        uint256 duration,
        uint256 minimumBid
    ) external nonReentrant {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        if (duration < MIN_DURATION || duration > _maxDuration) revert InvalidDuration();
        if (minimumBid < MIN_PRICE) revert InvalidPrice();
        if (address(_factory) == address(0)) revert NoFactoryAddressSet();

        address collectionAddress;
        try _factory.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error(string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }

        IERC721Collection collection = IERC721Collection(collectionAddress);
        address owner = collection.ownerOf(tokenId);
        if (owner != msg.sender) revert NotATokenOwner();

        collection.safeTransferFrom(msg.sender, address(this), tokenId);

        _auctionInfo[_auctionCounter] = AuctionInfo({
            seller: msg.sender,
            collectionAddress: collectionAddress,
            tokenId: tokenId,
            price: minimumBid,
            deadline: block.timestamp + duration
        });

        emit AuctionCreated(msg.sender, collectionId, tokenId);
        _auctionCounter++;
    }

    /// @notice Places a bid on an auction
    /// @param auctionId The auction ID
    function makeABid(uint256 auctionId) external payable nonReentrant {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        if (msg.sender == address(this)) revert InvalidBidAddress();
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionInfo[auctionId].seller == msg.sender) revert OwnerCannotBid();
        if (_auctionInfo[auctionId].deadline <= block.timestamp) revert AuctionIsExpired();

        uint256 bidsLength = _auctionBids[auctionId].length;
        if (bidsLength == 0) {
            if (msg.value < _auctionInfo[auctionId].price) revert InsufficientPayment();
        } else {
            (uint256 highestBid,) = getMaximumBid(auctionId);
            uint256 newHighestBid = highestBid + (_minNextBidPercent * highestBid / PERCENT_DIVISOR);

            for (uint256 i = 0; i < bidsLength; ++i) {
                if (_auctionBids[auctionId][i].buyer == msg.sender) {
                    newHighestBid -= _auctionBids[auctionId][i].buyPrice;
                    break;
                }
            }

            if (msg.value < newHighestBid) revert InsufficientPayment();
        }

        bool isUserInBid = false;
        for (uint256 i = 0; i < bidsLength; ++i) {
            if (_auctionBids[auctionId][i].buyer == msg.sender) {
                _auctionBids[auctionId][i].buyPrice += msg.value;
                isUserInBid = true;
                break;
            }
        }

        if (!isUserInBid) {
            _auctionBids[auctionId].push(Bid({buyer: msg.sender, buyPrice: msg.value}));
        }

        _auctionBlockedAmount += msg.value;

        (uint256 maxCurrentBid, uint256 maxBidIndex) = getMaximumBid(auctionId);

        uint256 userBidIndex = type(uint256).max;
        uint256 updatedBidsLength = _auctionBids[auctionId].length;
        for (uint256 i = 0; i < updatedBidsLength; ++i) {
            if (_auctionBids[auctionId][i].buyer == msg.sender) {
                userBidIndex = i;
                break;
            }
        }

        if (userBidIndex != type(uint256).max && userBidIndex == maxBidIndex) {
            _auctionInfo[auctionId].deadline += EXTENSION_TIME;
        }

        emit BidPlaced(auctionId, maxCurrentBid, msg.sender);
    }

    /// @notice Finalizes an auction after it ends
    /// @param auctionId The auction ID
    function finalizeAuction(uint256 auctionId) external nonReentrant {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionInfo[auctionId].deadline > block.timestamp) revert AuctionIsNotFinished();

        IERC721Collection collection = IERC721Collection(_auctionInfo[auctionId].collectionAddress);
        uint256 tokenId = _auctionInfo[auctionId].tokenId;
        uint256 length = _auctionBids[auctionId].length;

        if (length == 0) {
            _auctionFinished[auctionId] = true;
            collection.safeTransferFrom(address(this), _auctionInfo[auctionId].seller, tokenId);
        } else {
            (uint256 maxBid, uint256 maxBidIndex) = getMaximumBid(auctionId);
            _auctionFinished[auctionId] = true;

            collection.safeTransferFrom(address(this), _auctionBids[auctionId][maxBidIndex].buyer, tokenId);

            (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(_auctionInfo[auctionId].collectionAddress).royaltyInfo(tokenId, maxBid);
            uint256 maxRoyaltyAmount = (maxBid * 1000) / FEE_DENOMINATOR;
            if (royaltyAmount > maxRoyaltyAmount) {
                royaltyAmount = maxRoyaltyAmount;
            }
            uint256 auctionFeeAmount = (maxBid * _auctionFeeAmount) / FEE_DENOMINATOR;
            uint256 sellerProceeds = maxBid - royaltyAmount - auctionFeeAmount;

            (bool successSeller,) = payable(_auctionInfo[auctionId].seller).call{value: sellerProceeds}("");
            if (!successSeller) revert PaymentFailed();

            if (royaltyReceiver != address(0) && royaltyAmount > 0) {
                (bool successRoyaltyReceiver,) = payable(royaltyReceiver).call{value: royaltyAmount}("");
                if (!successRoyaltyReceiver) revert PaymentFailed();
            }

            if (_auctionFeeReceiver != address(0)) {
                (bool successAuctionFeeReceiver,) = payable(_auctionFeeReceiver).call{value: auctionFeeAmount}("");
                if (!successAuctionFeeReceiver) revert PaymentFailed();
            }

            _auctionBids[auctionId][maxBidIndex] = _auctionBids[auctionId][length - 1];
            _auctionBids[auctionId].pop();

            _auctionBlockedAmount -= maxBid;
        }

        delete _auctionInfo[auctionId];
        emit AuctionEnded(auctionId);
    }

    /// @notice Cancels an auction before any bids
    /// @param auctionId The auction ID
    function cancelAuction(uint256 auctionId) external nonReentrant {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionInfo[auctionId].seller != msg.sender) revert NotAnAuctionAuthor();
        if (_auctionInfo[auctionId].deadline <= block.timestamp) revert AuctionIsExpired();
        if (_auctionBids[auctionId].length > 0) revert AuctionHasBids();

        IERC721Collection collection = IERC721Collection(_auctionInfo[auctionId].collectionAddress);
        uint256 tokenId = _auctionInfo[auctionId].tokenId;

        collection.safeTransferFrom(address(this), _auctionInfo[auctionId].seller, tokenId);

        _auctionFinished[auctionId] = true;

        emit AuctionCancelled(_auctionInfo[auctionId].seller, _auctionInfo[auctionId].collectionAddress, _auctionInfo[auctionId].tokenId);

        delete _auctionInfo[auctionId];
    }

    /// @notice Withdraws a losing bid after auction finalization
    /// @param auctionId The auction ID
    function withdrawAuctionBid(uint256 auctionId) external nonReentrant {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (!_auctionFinished[auctionId]) revert AuctionIsNotFinished();

        uint256 length = _auctionBids[auctionId].length;
        if (length == 0) revert AllBidsArePaid();

        for (uint256 i = 0; i < length; ++i) {
            if (_auctionBids[auctionId][i].buyer == msg.sender) {
                uint256 bidAmount = _auctionBids[auctionId][i].buyPrice;

                _auctionBids[auctionId][i] = _auctionBids[auctionId][length - 1];
                _auctionBids[auctionId].pop();

                _auctionBlockedAmount -= bidAmount;

                (bool success,) = payable(msg.sender).call{value: bidAmount}("");
                if (!success) revert PaymentFailed();

                emit BidWithdrawn(auctionId, msg.sender);
                return;
            }
        }
        revert UserBidNotFound();
    }

    /// @notice Withdraws accumulated auction fees
    function withdraw() external onlyMultisig {
        if (_auctionFeeReceiver == address(0)) revert ZeroAddress();
        if (address(this).balance < _auctionBlockedAmount) revert InsufficientBalance();

        uint256 availableAmount = address(this).balance - _auctionBlockedAmount;
        if (availableAmount == 0) revert InsufficientBalance();

        (bool success,) = payable(_auctionFeeReceiver).call{value: availableAmount}("");
        if (!success) revert PaymentFailed();
    }

    /// @notice Activates the auction contract
    function activateAuction() external onlyMultisig {
        if (_isAuctionActive) revert AuctionIsActiveAlready();
        _isAuctionActive = true;
        emit AuctionActivated();
    }

    /// @notice Stops the auction contract
    function stopAuction() external onlyMultisig {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        _isAuctionActive = false;
        emit AuctionStopped();
    }

    /// @notice Sets the MultisigTimelock address
    /// @param newMultisigTimelock The new address
    function setMultisigTimelock(address newMultisigTimelock) external onlyMultisig {
        if (newMultisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
    }

    /// @notice Sets the factory address
    /// @param newFactoryAddress The new address
    function setFactoryAddress(address newFactoryAddress) external onlyMultisig {
        if (newFactoryAddress == address(0)) revert ZeroAddress();
        _factory = IFactory(newFactoryAddress);
        emit FactoryAddressSet(newFactoryAddress);
    }

    /// @notice Sets the auction fee amount (in basis points)
    /// @param newAuctionFeeAmount The new fee amount (max 500 = 5%)
    function setAuctionFeeAmount(uint256 newAuctionFeeAmount) external onlyMultisig {
        if (newAuctionFeeAmount > 500) revert InvalidAuctionFeeAmount();
        _auctionFeeAmount = newAuctionFeeAmount;
        emit AuctionFeeAmountSet(newAuctionFeeAmount);
    }

    /// @notice Sets the auction fee receiver address
    /// @param newFeeReceiver The new address
    function setAuctionFeeReceiver(address newFeeReceiver) external onlyMultisig {
        if (newFeeReceiver == address(0)) revert ZeroAddress();
        _auctionFeeReceiver = newFeeReceiver;
        emit AuctionFeeReceiverSet(newFeeReceiver);
    }

    /// @notice Sets the minimum next bid percentage
    /// @param newBidPercent The new percentage (5-50)
    function setMinimumNextBidPercent(uint256 newBidPercent) external onlyMultisig {
        if (newBidPercent < 5 || newBidPercent > 50) revert InvalidNextBidPercent();
        _minNextBidPercent = newBidPercent;
        emit MinNextBidPercentSet(newBidPercent);
    }

    /// @notice Sets the maximum auction duration
    /// @param newMaxDuration The new max duration
    function setMaxDuration(uint256 newMaxDuration) external onlyMultisig {
        if (newMaxDuration < MIN_DURATION) revert InvalidDuration();
        _maxDuration = newMaxDuration;
        emit MaxDurationSet(newMaxDuration);
    }

    /// @notice Returns whether the auction is active
    function isAuctionActive() external view returns (bool) {
        return _isAuctionActive;
    }

    /// @notice Returns the total number of auctions created
    function getAuctionCount() external view returns (uint256) {
        return _auctionCounter - 1;
    }

    /// @notice Returns the factory address
    function getFactoryAddress() external view returns (address) {
        return address(_factory);
    }

    /// @notice Returns the total blocked amount
    function getBlockedAmount() external view returns (uint256) {
        return _auctionBlockedAmount;
    }

    /// @notice Returns the auction fee receiver
    function getAuctionFeeReceiver() external view returns (address) {
        return _auctionFeeReceiver;
    }

    /// @notice Returns a user's bid for an auction
    /// @param auctionId The auction ID
    /// @param user The user address
    /// @return bidAmount The bid amount
    /// @return hasBid Whether the user has a bid
    function getUserBid(uint256 auctionId, address user) external view returns (uint256 bidAmount, bool hasBid) {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        Bid[] memory bids = _auctionBids[auctionId];
        for (uint256 i = 0; i < bids.length; ++i) {
            if (bids[i].buyer == user) {
                return (bids[i].buyPrice, true);
            }
        }
        return (0, false);
    }

    /// @notice Returns all bids for an auction
    /// @param auctionId The auction ID
    /// @return buyers Array of bidder addresses
    /// @return amounts Array of bid amounts
    function getAllBids(uint256 auctionId) external view returns (address[] memory buyers, uint256[] memory amounts) {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        Bid[] memory bids = _auctionBids[auctionId];
        uint256 length = bids.length;
        buyers = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            buyers[i] = bids[i].buyer;
            amounts[i] = bids[i].buyPrice;
        }
    }

    /// @notice Returns the minimum bid amount for the next bid
    /// @param auctionId The auction ID
    function getNextBidAmount(uint256 auctionId) external view returns (uint256) {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();

        uint256 bidsLength = _auctionBids[auctionId].length;
        if (bidsLength == 0) {
            return _auctionInfo[auctionId].price;
        }

        (uint256 highestBid,) = getMaximumBid(auctionId);
        return highestBid + (_minNextBidPercent * highestBid / PERCENT_DIVISOR);
    }

    /// @notice Returns auction information
    /// @param auctionId The auction ID
    function getAuctionInfo(uint256 auctionId) external view returns (
        address seller,
        address collectionAddress,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        bool isFinished
    ) {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        AuctionInfo memory auction = _auctionInfo[auctionId];
        return (
            auction.seller,
            auction.collectionAddress,
            auction.tokenId,
            auction.price,
            auction.deadline,
            _auctionFinished[auctionId]
        );
    }

    /// @notice Returns auction settings
    function getAuctionSettings() external view returns (
        uint256 minDuration,
        uint256 maxDuration,
        uint256 minPrice,
        uint256 extensionTime,
        uint256 minNextBidPercent,
        uint256 auctionFeeAmount,
        address feeReceiver
    ) {
        return (
            MIN_DURATION,
            _maxDuration,
            MIN_PRICE,
            EXTENSION_TIME,
            _minNextBidPercent,
            _auctionFeeAmount,
            _auctionFeeReceiver
        );
    }

    /// @notice IERC721Receiver implementation
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the maximum bid for an auction
    /// @param auctionId The auction ID
    /// @return maxCurrentBid The highest bid amount
    /// @return maxBidIndex The index of the highest bid
    function getMaximumBid(uint256 auctionId) public view returns (uint256 maxCurrentBid, uint256 maxBidIndex) {
        if (auctionId >= _auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionBids[auctionId].length == 0) revert NoBidsMade();

        for (uint256 i = 0; i < _auctionBids[auctionId].length; ++i) {
            if (_auctionBids[auctionId][i].buyPrice > maxCurrentBid) {
                maxCurrentBid = _auctionBids[auctionId][i].buyPrice;
                maxBidIndex = i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override onlyMultisig {}
}
