// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";
import {IERC2981} from "openzeppelin-contracts/interfaces/IERC2981.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

/// @title Interface for MultisigTimelock verification
interface IMultisigTimelock {
    function verifyCurrentTransaction() external view;
}

contract Auction is 
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuard,
    IERC721Receiver
{

    struct bid {
        address buyer;
        uint256 buyPrice;
    }

    struct auctionNFT {
        address seller;
        address collectionAddress;
        uint256 tokenId;
        uint256 price;
        uint256 deadline;
    }

    address private _multisigTimelock;
    address private _auctionFeeReceiver;
    IFactory private _factoryTyped;
    uint256 private auctionCounter = 1;
    uint256 private MAX_DURATION = 7 days;
    uint256 immutable private MIN_DURATION = 30 minutes;
    uint256 immutable private MIN_PRICE = 1000 wei;
    uint256 immutable private PERCENT_DIVISOR = 100;
    uint256 immutable private FEE_DENOMINATOR = 10_000;
    uint256 private EXTENSION_TIME = 5 minutes;
    uint256 private MIN_NEXT_BID_PERCENT = 5;
    uint256 private _auctionBlockedAmount;
    uint256 private _auctionFeeAmount;
    bool private _isAuctionActive;  
    mapping(uint256 => auctionNFT) private _auctionNFTInfo;
    mapping(uint256 => bid[]) private _userAuctionBids;
    mapping(uint256 => bool) private _auctionFinished;

     /* Events */
    event AuctionCancelled(address indexed seller, address indexed collectionAddress, uint256 indexed tokenId);
    event AuctionCreated(address indexed seller, uint256 indexed collectionId, uint256 indexed tokenId);
    event AuctionEnded(uint256 indexed auctionId);
    event AuctionIsActive();
    event AuctionIsStopped();
    event NewBidSet(uint256 indexed auctionId, uint256 indexed newBid, address indexed user);
    event UserBidWithdrawn(uint256 indexed auctionId, address indexed userAddress);
    event NewAuctionFeeAmountSet(uint256 indexed newAuctionFeeAmount);
    event NewAuctionFeeReceiverSet(address indexed newFeeReceiver);
    event NewFactoryAddressSet(address indexed newFactory);
    event NewMaxDurationSet(uint256 indexed newMaxDuration);
    event NewMultisigTimelockSet(address indexed multisigTimelock);
    event NewNextBidPercentSet(uint256 indexed newBidPercent);

    /* Errors */
    error InvalidAuction();
    error InvalidAuctionFeeAmount();
    error InvalidBidAddress();
    error InvalidDuration();
    error InvalidNextBidPercent();
    error InvalidPrice();
    error ZeroAddress();
    error AuctionHasBids();
    error AuctionIsActiveAlready();
    error AuctionIsAlready();
    error AuctionIsExpired();
    error AuctionIsGoing();
    error AuctionIsNotFinished();
    error AuctionIsStoppedAlready();
    error NotAMultisigTimelock();
    error NotAnAuctionAuthor();
    error NotATokenOwner();
    error OwnerCanMakeNoBid();
    error AllBidsArePaid();
    error NoBidsMade();
    error UserBidNotFound();
    error InsufficientBalance();
    error InsufficientPayment();
    error PaymentFailed();
    error NoFactoryAddressSet();

    /* Modifiers */
    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) {
            revert NotAMultisigTimelock();
        }
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
        _;
    }

   
    constructor() {
        _disableInitializers();
    }    


    
    function initialize(address multisigTimelock) external initializer {
        __ReentrancyGuard_init();
        if (multisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
    }

    /**
     * @dev Stop Auction contract
     */
    function stopAuction() external onlyMultisig {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        _isAuctionActive = false;
        emit AuctionIsStopped();
    }

    /**
     * @dev Set New auction fee amount
     */
    function setNewAuctionFeeAmount(uint256 newAuctionFeeAmount) external onlyMultisig {
        if (newAuctionFeeAmount > 500) revert InvalidAuctionFeeAmount();
        _auctionFeeAmount = newAuctionFeeAmount;
        emit NewAuctionFeeAmountSet(newAuctionFeeAmount);
    }

    /**
     * @dev Set new max duration period
     */
    function setMaxDuration(uint256 newMaxDuration) external onlyMultisig {
        if (newMaxDuration < MIN_DURATION) revert InvalidDuration();
        MAX_DURATION = newMaxDuration;
        emit NewMaxDurationSet(newMaxDuration);
    }

    /**
     * @dev Set new fee receiver address
     */
    function setAuctionFeeReceiver(address newFeeReceiver) external onlyMultisig {
        if (newFeeReceiver == address(0)) revert ZeroAddress();
        _auctionFeeReceiver = newFeeReceiver;
        emit NewAuctionFeeReceiverSet(newFeeReceiver);
    }

    /**
     * @dev Activate Auction contract
     */
    function activateAuction() external onlyMultisig {
        if (_isAuctionActive) revert AuctionIsActiveAlready();
        _isAuctionActive = true;
        emit AuctionIsActive();
    }

    

    /**
     * @dev Set new MultisigTimelock address
     */
    function setMultisigTimelock(address newMultisigTimelock) external onlyMultisig {
        _multisigTimelock = newMultisigTimelock;
        emit NewMultisigTimelockSet(newMultisigTimelock);
    }

    /**
     * @dev Set new Factory address
     */
    function setFactoryAddress(address newFactoryAddress) external onlyMultisig {
        if (newFactoryAddress == address(0)) revert ZeroAddress();
        _factoryTyped = IFactory(newFactoryAddress);
        emit NewFactoryAddressSet(newFactoryAddress);
    } 


    
    /**
     * @dev Put current token on auction
     */
    function putTokenOnAuction(
        uint256 collectionId,
        uint256 tokenId,
        uint256 duration,
        uint256 minimumBid
    ) external {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        if (duration < MIN_DURATION || duration > MAX_DURATION) revert InvalidDuration();
        if (minimumBid < MIN_PRICE) revert InvalidPrice();
        if (address(_factoryTyped) == address(0)) revert NoFactoryAddressSet();

        address collectionAddress;
        try _factoryTyped.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
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

        _auctionNFTInfo[auctionCounter] = auctionNFT({
            seller: msg.sender,
            collectionAddress: collectionAddress,
            tokenId: tokenId,
            price: minimumBid,
            deadline: block.timestamp + duration
        });

        emit AuctionCreated(msg.sender, collectionId, tokenId);
        auctionCounter++; 
    }


    /**
     * @dev Make a new bid on auction
     */
    function makeABid(uint256 auctionId) external payable nonReentrant {
        if (!_isAuctionActive) revert AuctionIsStoppedAlready();
        if (msg.sender == address(this)) revert InvalidBidAddress();
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionNFTInfo[auctionId].seller == msg.sender) revert OwnerCanMakeNoBid();
        if (_auctionNFTInfo[auctionId].deadline <= block.timestamp) revert AuctionIsExpired();

        uint256 bidsLength = _userAuctionBids[auctionId].length;
        if (bidsLength == 0) {
            if (msg.value < _auctionNFTInfo[auctionId].price) revert InsufficientPayment();
        } else {
            (uint256 highestBid, uint256 highestBidIndex) = getMaximumBid(auctionId);
            
            uint256 newHighestBid = highestBid + (MIN_NEXT_BID_PERCENT * highestBid / PERCENT_DIVISOR);

            for (uint256 i = 0; i < bidsLength; ++i) {
                if (_userAuctionBids[auctionId][i].buyer == msg.sender) {
                    newHighestBid -= _userAuctionBids[auctionId][i].buyPrice;
                    break;
                } 
            }

            if (msg.value < newHighestBid) revert InsufficientPayment();
        }

        bool isUserInBid = false;
        for (uint256 i = 0; i < bidsLength; ++i) {
            if (_userAuctionBids[auctionId][i].buyer == msg.sender) {
                _userAuctionBids[auctionId][i].buyPrice += msg.value;
                isUserInBid = true;
                break;
            } 
        }

        if (!isUserInBid) {
            _userAuctionBids[auctionId].push(bid({
                buyer: msg.sender,
                buyPrice: msg.value
            })); 
        }

        _auctionBlockedAmount += msg.value;

        (uint256 maxCurrentBid, uint256 maxBidIndex) = getMaximumBid(auctionId);
        
        // Only extend deadline if this bid becomes the new highest bid
        // Find the user's bid index after the update
        uint256 userBidIndex = type(uint256).max;
        uint256 updatedBidsLength = _userAuctionBids[auctionId].length;
        for (uint256 i = 0; i < updatedBidsLength; ++i) {
            if (_userAuctionBids[auctionId][i].buyer == msg.sender) {
                userBidIndex = i;
                break;
            }
        }
        
        // If user's bid is now the highest, extend deadline
        if (userBidIndex != type(uint256).max && userBidIndex == maxBidIndex) {
            _auctionNFTInfo[auctionId].deadline += EXTENSION_TIME;
        }
        
        emit NewBidSet(auctionId, maxCurrentBid, msg.sender);
    }

    /**
     * @dev Set new minimum next bid percent
     */
    function setMinimumNextBidPercent(uint256 newBidPercent) external onlyMultisig {
        if (newBidPercent < 5 || newBidPercent > 50) revert InvalidNextBidPercent();
        MIN_NEXT_BID_PERCENT = newBidPercent;
        emit NewNextBidPercentSet(newBidPercent);
    }

    /**
     * @dev Finalize auction after it's ended
     * @notice Anyone can finalize any auction
     */
    function finalizeAuction(uint256 auctionId) external nonReentrant {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionNFTInfo[auctionId].deadline > block.timestamp) revert AuctionIsNotFinished();

        IERC721Collection collection = IERC721Collection(_auctionNFTInfo[auctionId].collectionAddress);
        uint256 tokenId = _auctionNFTInfo[auctionId].tokenId;
        uint256 length = _userAuctionBids[auctionId].length;

        if (length == 0) {
            _auctionFinished[auctionId] = true;
            collection.safeTransferFrom(address(this), _auctionNFTInfo[auctionId].seller, tokenId);
        } else {
            (uint256 maxBid, uint256 maxBidIndex) = getMaximumBid(auctionId); 
            _auctionFinished[auctionId] = true;
            
            collection.safeTransferFrom(address(this), _userAuctionBids[auctionId][maxBidIndex].buyer, tokenId);

            (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(_auctionNFTInfo[auctionId].collectionAddress).royaltyInfo(tokenId, maxBid);
            uint256 maxRoyaltyAmount = (maxBid * 1000) / FEE_DENOMINATOR; 
            if (royaltyAmount > maxRoyaltyAmount) {
                royaltyAmount = maxRoyaltyAmount;
            }
            uint256 auctionFeeAmount = (maxBid * _auctionFeeAmount) / FEE_DENOMINATOR;

            uint256 sellerProceeds = maxBid - royaltyAmount - auctionFeeAmount;
            
            // Collect marketplace fee (stays in contract, can be withdrawn by owner)
            // Marketplace fee is already deducted from sellerProceeds above

            (bool successSeller, ) = payable(_auctionNFTInfo[auctionId].seller).call{value: sellerProceeds}("");
            if (!successSeller) revert PaymentFailed();

            if (royaltyReceiver != address(0) && royaltyAmount > 0) {
                (bool successRoyaltyReceiver, ) = payable(royaltyReceiver).call{value: royaltyAmount}("");
                if (!successRoyaltyReceiver) revert PaymentFailed();
            }

            if (_auctionFeeReceiver != address(0)) {
                (bool successAuctionFeeReceiver, ) = payable(_auctionFeeReceiver).call{value: auctionFeeAmount}("");
                if (!successAuctionFeeReceiver) revert PaymentFailed();
            } 

            _userAuctionBids[auctionId][maxBidIndex] = _userAuctionBids[auctionId][length - 1];
             _userAuctionBids[auctionId].pop();

            _auctionBlockedAmount -= maxBid;
        }
 
        delete _auctionNFTInfo[auctionId];

        emit AuctionEnded(auctionId);
    }

    /**
     * @dev Cancel auction before first bid;
     */
    function cancelAuction(uint256 auctionId) external {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_auctionNFTInfo[auctionId].seller != msg.sender) revert NotAnAuctionAuthor();
        if (_auctionNFTInfo[auctionId].deadline <= block.timestamp) revert AuctionIsExpired();

        
        if (_userAuctionBids[auctionId].length > 0) revert AuctionHasBids();
        IERC721Collection collection = IERC721Collection(_auctionNFTInfo[auctionId].collectionAddress);
        uint256 tokenId = _auctionNFTInfo[auctionId].tokenId;

        collection.safeTransferFrom(address(this), _auctionNFTInfo[auctionId].seller, tokenId);
        
        _auctionFinished[auctionId] = true;

        emit AuctionCancelled(_auctionNFTInfo[auctionId].seller, _auctionNFTInfo[auctionId].collectionAddress, _auctionNFTInfo[auctionId].tokenId);

        delete _auctionNFTInfo[auctionId]; 
    }

    /**
     * @dev withdraw all funds on contract
     */
    function withdraw() external onlyMultisig {
        if (_auctionFeeReceiver == address(0)) revert ZeroAddress();
        if (address(this).balance < _auctionBlockedAmount) revert InsufficientBalance();

        uint256 avaiableAmount = address(this).balance - _auctionBlockedAmount;

        if (avaiableAmount == 0) revert InsufficientBalance();
        (bool success, ) = payable(_auctionFeeReceiver).call{value: avaiableAmount}("");
        if (!success) revert PaymentFailed();
    }

    /**
     * @dev Withdraw losing bid from auction after finalization
     * @notice Only losing bidders can withdraw their bids after auction is finalized
     */
    function withdrawAuctionBid(uint256 auctionId) external nonReentrant {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (!_auctionFinished[auctionId]) revert AuctionIsNotFinished();

        uint256 length = _userAuctionBids[auctionId].length;
        if (length == 0) revert AllBidsArePaid();

        for (uint256 i = 0; i < length; ++i) {
            if (_userAuctionBids[auctionId][i].buyer == msg.sender) {
                uint256 bidAmount = _userAuctionBids[auctionId][i].buyPrice;
                
                // Remove bid from array (swap with last element and pop)
                _userAuctionBids[auctionId][i] = _userAuctionBids[auctionId][length - 1];
                _userAuctionBids[auctionId].pop();

                // Update blocked amount before transfer
                _auctionBlockedAmount -= bidAmount;

                // Transfer funds to bidder
                (bool success, ) = payable(msg.sender).call{value: bidAmount}("");
                if (!success) revert PaymentFailed();

                emit UserBidWithdrawn(auctionId, msg.sender);
                return;
            } 
        }
        revert UserBidNotFound();
    }


    /**
     * @dev Check Auction status
     */
    function isAuctionActive() external view returns(bool) {
        return _isAuctionActive;
    }

    /**
     * @dev Get complete auction information
     * @param auctionId The ID of the auction
     * @return seller The address of the seller
     * @return collectionAddress The address of the NFT collection
     * @return tokenId The token ID being auctioned
     * @return price The minimum bid price
     * @return deadline The auction deadline timestamp
     * @return isFinished Whether the auction is finished
     */
    function getAuctionInfo(uint256 auctionId) external view returns (
        address seller,
        address collectionAddress,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        bool isFinished
    ) {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        auctionNFT memory auction = _auctionNFTInfo[auctionId];
        return (
            auction.seller,
            auction.collectionAddress,
            auction.tokenId,
            auction.price,
            auction.deadline,
            _auctionFinished[auctionId]
        );
    }

    /**
     * @dev Get a specific user's bid for an auction
     * @param auctionId The ID of the auction
     * @param user The address of the bidder
     * @return bidAmount The total bid amount by the user
     * @return hasBid Whether the user has placed a bid
     */
    function getUserBid(uint256 auctionId, address user) external view returns (uint256 bidAmount, bool hasBid) {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        bid[] memory bids = _userAuctionBids[auctionId];
        for (uint256 i = 0; i < bids.length; ++i) {
            if (bids[i].buyer == user) {
                return (bids[i].buyPrice, true);
            }
        }
        return (0, false);
    }

    /**
     * @dev Get all bids for an auction
     * @param auctionId The ID of the auction
     * @return buyers Array of bidder addresses
     * @return amounts Array of bid amounts
     */
    function getAllBids(uint256 auctionId) external view returns (address[] memory buyers, uint256[] memory amounts) {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        bid[] memory bids = _userAuctionBids[auctionId];
        uint256 length = bids.length;
        buyers = new address[](length);
        amounts = new uint256[](length);
        
        for (uint256 i = 0; i < length; ++i) {
            buyers[i] = bids[i].buyer;
            amounts[i] = bids[i].buyPrice;
        }
    }

    /**
     * @dev Get the minimum bid amount required for the next bid
     * @param auctionId The ID of the auction
     * @return minBid The minimum bid amount required
     */
    function getNextBidAmount(uint256 auctionId) external view returns (uint256 minBid) {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        
        uint256 bidsLength = _userAuctionBids[auctionId].length;
        if (bidsLength == 0) {
            return _auctionNFTInfo[auctionId].price;
        }
        
        (uint256 highestBid, ) = getMaximumBid(auctionId);
        return highestBid + (MIN_NEXT_BID_PERCENT * highestBid / PERCENT_DIVISOR);
    }

    /**
     * @dev Get total number of auctions created
     * @return count The total number of auctions (including finished ones)
     */
    function getAuctionCount() external view returns (uint256 count) {
        return auctionCounter - 1;
    }

    /**
     * @dev Get auction contract settings
     * @return minDuration Minimum auction duration
     * @return maxDuration Maximum auction duration
     * @return minPrice Minimum bid price
     * @return extensionTime Time added when new highest bid is placed
     * @return minNextBidPercent Minimum percentage increase for next bid
     * @return auctionFeeAmount Auction fee in basis points
     * @return feeReceiver Address that receives auction fees
     */
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
            MAX_DURATION,
            MIN_PRICE,
            EXTENSION_TIME,
            MIN_NEXT_BID_PERCENT,
            _auctionFeeAmount,
            _auctionFeeReceiver
        );
    }

    /**
     * @dev Get total blocked amount (bids that haven't been withdrawn)
     * @return amount The total amount of ETH blocked in active bids
     */
    function getBlockedAmount() external view returns (uint256 amount) {
        return _auctionBlockedAmount;
    }

    /**
     * @dev Implementation of IERC721Receiver to allow marketplace to receive NFTs
     * @notice This is required when minting tokens to the marketplace contract
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
     * @dev Get maximum bid on the current auction
     */
    function getMaximumBid(uint256 auctionId) public view returns(uint256 maxCurrentBid, uint256 maxBidIndex) {
        if (auctionId >= auctionCounter) revert InvalidAuction();
        if (_auctionFinished[auctionId]) revert AuctionIsExpired();
        if (_userAuctionBids[auctionId].length == 0) revert NoBidsMade();

        for (uint256 i = 0; i < _userAuctionBids[auctionId].length; ++i) {
            if (_userAuctionBids[auctionId][i].buyPrice > maxCurrentBid) {
                maxCurrentBid = _userAuctionBids[auctionId][i].buyPrice;
                maxBidIndex = i;
            } 
        }
    }

    /**
     * @dev Authorized upgrade. Required by UUPSUpgrade
     */
    function _authorizeUpgrade(address) internal override onlyMultisig {}

}