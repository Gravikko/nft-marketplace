// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC2981} from "openzeppelin-contracts/interfaces/IERC2981.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";
import {IMultisigTimelock} from "./interfaces/IMultisigTimelock.sol";

/// @title MarketplaceNFT
/// @notice NFT marketplace with EIP-712 signed orders and offers
/// @dev Supports both ETH (orders) and WETH (offers) payments with royalties
contract MarketplaceNFT is
    Initializable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuard,
    IERC721Receiver
{
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Order struct for seller-initiated listings
    struct Order {
        address seller;
        uint256 collectionId;
        uint256 tokenId;
        uint256 price;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice Offer struct for buyer-initiated bids
    struct Offer {
        address buyer;
        uint256 collectionId;
        uint256 tokenId;
        uint256 price;
        uint256 nonce;
        uint256 deadline;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    using SafeERC20 for IERC20;

    uint256 public constant MIN_PRICE = 1000 wei;
    uint256 private constant FEE_DENOMINATOR = 10_000;

    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address seller,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant OFFER_TYPEHASH = keccak256(
        "Offer(address buyer,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
    );

    bool private _isMarketplaceActive;
    address public weth;
    address private _multisigTimelock;
    address private _marketplaceFeeReceiver;
    uint256 private _marketplaceFeeAmount;
    IFactory private _factory;

    mapping(bytes32 => bool) private _cancelledOrders;
    mapping(bytes32 => bool) private _cancelledOffers;
    mapping(address => mapping(uint256 => bool)) private _usedNoncesOrders;
    mapping(address => mapping(uint256 => bool)) private _usedNoncesOffers;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FactoryAddressSet(address indexed newFactory);
    event MarketplaceActivated();
    event MarketplaceStopped();
    event MarketplaceFeeAmountSet(uint256 indexed feeAmount);
    event MarketplaceFeeReceiverSet(address indexed newMarketplaceFeeReceiver);
    event MultisigTimelockSet(address indexed multisigTimelock);
    event NonceMarkedUsed(address indexed account, uint256 indexed nonce);
    event OfferCancelled(
        address indexed buyer,
        uint256 indexed collectionId,
        uint256 indexed tokenId,
        uint256 nonce
    );
    event OfferExecuted(
        address indexed buyer,
        address indexed seller,
        uint256 indexed collectionId,
        uint256 tokenId,
        uint256 price,
        uint256 nonce,
        uint256 deadline
    );
    event OrderCancelled(
        address indexed seller,
        uint256 indexed collectionId,
        uint256 indexed tokenId,
        uint256 nonce
    );
    event OrderExecuted(
        address indexed seller,
        address indexed buyer,
        uint256 indexed collectionId,
        uint256 tokenId,
        uint256 price
    );
    event UnmintedTokenPurchased(
        address indexed buyer,
        uint256 collectionId,
        uint256 indexed tokenId,
        uint256 price
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error IncorrectPrice();
    error InsufficientPayment();
    error InvalidCollectionAddress();
    error InvalidMarketplaceFeeAmount();
    error InvalidOfferOperation();
    error InvalidSignature();
    error MarketplaceHasNoApprovalForSale();
    error MarketplaceIsActiveAlready();
    error MarketplaceIsStopped();
    error MarketplaceIsStoppedAlready();
    error MintFailed();
    error NoFactoryAddressSet();
    error NoUnmintedTokens();
    error NonceAlreadyUsed();
    error NotAMultisigTimelock();
    error NotATokenOwner();
    error OfferIsCancelled();
    error OfferExpired();
    error OfferNotCancellable();
    error OrderIsCancelled();
    error OrderExpired();
    error OrderNotCancellable();
    error PaymentFailed();
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

    modifier onlyOperational() {
        if (!_isMarketplaceActive) revert MarketplaceIsStopped();
        if (address(_factory) == address(0)) revert NoFactoryAddressSet();
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

    /// @notice Initializes the marketplace contract
    /// @param multisigTimelock Address of the MultisigTimelock contract
    /// @param _weth Address of the WETH token
    function initialize(address multisigTimelock, address _weth) external initializer {
        __EIP712_init("MarketplaceNFT", "1");
        if (multisigTimelock == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        weth = _weth;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a signed order (buyer purchases from seller)
    /// @param order The order details
    /// @param signature EIP-712 signature from the seller
    function executeOrder(
        Order memory order,
        bytes memory signature
    ) external payable nonReentrant onlyOperational {
        if (msg.value < order.price) revert InsufficientPayment();
        if (order.deadline < block.timestamp) revert OrderExpired();
        if (_usedNoncesOrders[order.seller][order.nonce]) revert NonceAlreadyUsed();

        {
            bytes32 orderHash = keccak256(abi.encodePacked(
                order.seller,
                order.collectionId,
                order.tokenId,
                order.price,
                order.nonce,
                order.deadline
            ));
            if (_cancelledOrders[orderHash]) revert OrderIsCancelled();

            bytes32 structHash = keccak256(abi.encode(
                ORDER_TYPEHASH,
                order.seller,
                order.collectionId,
                order.tokenId,
                order.price,
                order.nonce,
                order.deadline
            ));
            bytes32 hash = _hashTypedDataV4(structHash);
            address signer = ECDSA.recover(hash, signature);
            if (signer != order.seller) revert InvalidSignature();
        }

        address collectionAddress = getCollectionAddress(order.collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);

        {
            address owner = collection.ownerOf(order.tokenId);
            if (owner != order.seller) revert NotATokenOwner();
            if (!collection.isTokenApproved(order.tokenId, address(this))) {
                revert MarketplaceHasNoApprovalForSale();
            }
        }

        _usedNoncesOrders[order.seller][order.nonce] = true;
        collection.safeTransferFrom(order.seller, msg.sender, order.tokenId);

        address royaltyReceiver;
        uint256 royaltyAmount;
        uint256 marketplaceFeeAmount;
        uint256 sellerProceeds;

        {
            (royaltyReceiver, royaltyAmount, marketplaceFeeAmount) = getAllRoyaltyAndFeeInfo(
                collectionAddress,
                order.tokenId,
                order.price
            );
            sellerProceeds = order.price - royaltyAmount - marketplaceFeeAmount;
        }

        {
            (bool successSeller,) = payable(order.seller).call{value: sellerProceeds}("");
            if (!successSeller) revert PaymentFailed();
        }

        if (royaltyReceiver != address(0) && royaltyAmount > 0) {
            (bool successRoyaltyReceiver,) = payable(royaltyReceiver).call{value: royaltyAmount}("");
            if (!successRoyaltyReceiver) revert PaymentFailed();
        }

        if (_marketplaceFeeReceiver != address(0)) {
            (bool successMarketplaceFeeReceiver,) = payable(_marketplaceFeeReceiver).call{value: marketplaceFeeAmount}("");
            if (!successMarketplaceFeeReceiver) revert PaymentFailed();
        }

        {
            uint256 refund = msg.value - order.price;
            if (refund > 0) {
                (bool successRefund,) = payable(msg.sender).call{value: refund}("");
                if (!successRefund) revert PaymentFailed();
            }
        }

        emit OrderExecuted(order.seller, msg.sender, order.collectionId, order.tokenId, order.price);
    }

    /// @notice Executes a signed offer (seller accepts buyer's offer)
    /// @dev Buyer must have approved WETH to this contract
    /// @param offer The offer details
    /// @param signature EIP-712 signature from the buyer
    function executeOffer(
        Offer memory offer,
        bytes memory signature
    ) external payable nonReentrant onlyOperational {
        if (offer.deadline < block.timestamp) revert OfferExpired();
        if (_usedNoncesOffers[offer.buyer][offer.nonce]) revert NonceAlreadyUsed();

        {
            bytes32 offerHash = keccak256(abi.encodePacked(
                offer.buyer,
                offer.collectionId,
                offer.tokenId,
                offer.price,
                offer.nonce,
                offer.deadline
            ));
            if (_cancelledOffers[offerHash]) revert OfferIsCancelled();

            bytes32 digest = _hashTypedDataV4(_hashOffer(offer));
            address signer = ECDSA.recover(digest, signature);
            if (signer != offer.buyer) revert InvalidSignature();
        }

        address buyer = offer.buyer;
        uint256 collectionId = offer.collectionId;
        uint256 tokenId = offer.tokenId;
        uint256 price = offer.price;

        {
            IERC20 wethToken = IERC20(weth);
            if (wethToken.balanceOf(buyer) < price) revert InsufficientPayment();
            if (wethToken.allowance(buyer, address(this)) < price) revert InsufficientPayment();
            wethToken.safeTransferFrom(buyer, address(this), price);
        }

        address collectionAddress = getCollectionAddress(collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);
        address seller = msg.sender;

        {
            address owner = collection.ownerOf(tokenId);
            if (owner != seller) revert NotATokenOwner();
        }

        address royaltyReceiver;
        uint256 royaltyAmount;
        uint256 marketplaceFeeAmount;
        uint256 sellerProceeds;
        {
            (royaltyReceiver, royaltyAmount) = IERC2981(collectionAddress).royaltyInfo(tokenId, price);
            uint256 maxRoyaltyAmount = (price * 1000) / FEE_DENOMINATOR;
            if (royaltyAmount > maxRoyaltyAmount) {
                royaltyAmount = maxRoyaltyAmount;
            }
            marketplaceFeeAmount = (price * _marketplaceFeeAmount) / FEE_DENOMINATOR;
            sellerProceeds = price - royaltyAmount - marketplaceFeeAmount;
        }

        uint256 nonce = offer.nonce;
        uint256 deadline = offer.deadline;

        _usedNoncesOffers[buyer][nonce] = true;
        collection.safeTransferFrom(seller, buyer, tokenId);

        {
            IERC20 wethToken = IERC20(weth);
            if (sellerProceeds > 0) wethToken.safeTransfer(seller, sellerProceeds);
            if (royaltyReceiver != address(0) && royaltyAmount > 0) wethToken.safeTransfer(royaltyReceiver, royaltyAmount);
            if (_marketplaceFeeReceiver != address(0) && marketplaceFeeAmount > 0) wethToken.safeTransfer(_marketplaceFeeReceiver, marketplaceFeeAmount);
        }

        emit NonceMarkedUsed(buyer, nonce);
        emit OfferExecuted(buyer, seller, collectionId, tokenId, price, nonce, deadline);
    }

    /// @notice Creates an offer for a specific NFT
    /// @dev Validates that buyer has sufficient WETH allowance
    /// @param collectionId The collection ID
    /// @param tokenId The token ID
    /// @param price The offer price
    /// @param nonce The offer nonce
    /// @param deadline The offer deadline
    /// @return The created offer struct
    function createOffer(
        uint256 collectionId,
        uint256 tokenId,
        uint256 price,
        uint256 nonce,
        uint256 deadline
    ) external onlyOperational returns (Offer memory) {
        if (price < MIN_PRICE) revert IncorrectPrice();

        address collectionAddress = getCollectionAddress(collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);

        address owner = collection.ownerOf(tokenId);
        if (owner == msg.sender) revert InvalidOfferOperation();

        IERC20 wethToken = IERC20(weth);
        if (wethToken.balanceOf(msg.sender) < price) revert InsufficientPayment();
        if (wethToken.allowance(msg.sender, address(this)) < price) revert InsufficientPayment();

        return Offer({
            buyer: msg.sender,
            collectionId: collectionId,
            tokenId: tokenId,
            price: price,
            nonce: nonce,
            deadline: deadline
        });
    }

    /// @notice Cancels an order
    /// @param order The order to cancel
    /// @param signature The seller's signature
    function cancelOrder(
        Order memory order,
        bytes memory signature
    ) external {
        if (msg.sender != order.seller) revert NotATokenOwner();

        bytes32 structHash = keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.seller,
            order.collectionId,
            order.tokenId,
            order.price,
            order.nonce,
            order.deadline
        ));

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);
        if (signer != order.seller) revert InvalidSignature();

        if (_usedNoncesOrders[order.seller][order.nonce]) {
            revert OrderNotCancellable();
        }

        bytes32 orderHash = keccak256(abi.encodePacked(
            order.seller,
            order.collectionId,
            order.tokenId,
            order.price,
            order.nonce,
            order.deadline
        ));

        if (_cancelledOrders[orderHash]) {
            revert OrderNotCancellable();
        }

        _cancelledOrders[orderHash] = true;

        emit OrderCancelled(order.seller, order.collectionId, order.tokenId, order.nonce);
    }

    /// @notice Cancels an offer
    /// @param offer The offer to cancel
    /// @param signature The buyer's signature
    function cancelOffer(
        Offer memory offer,
        bytes memory signature
    ) external {
        if (msg.sender != offer.buyer) revert NotATokenOwner();

        bytes32 digest = _hashTypedDataV4(_hashOffer(offer));
        address signer = ECDSA.recover(digest, signature);
        if (signer != offer.buyer) revert InvalidSignature();

        if (_usedNoncesOffers[offer.buyer][offer.nonce]) {
            revert OfferNotCancellable();
        }

        bytes32 offerHash = keccak256(abi.encodePacked(
            offer.buyer,
            offer.collectionId,
            offer.tokenId,
            offer.price,
            offer.nonce,
            offer.deadline
        ));

        if (_cancelledOffers[offerHash]) {
            revert OfferNotCancellable();
        }

        _cancelledOffers[offerHash] = true;

        emit OfferCancelled(offer.buyer, offer.collectionId, offer.tokenId, offer.nonce);
    }

    /// @notice Validates an order before signing
    /// @param order The order to validate
    function putTokenOnSale(Order memory order) external view onlyOperational {
        if (order.price < MIN_PRICE) revert IncorrectPrice();
        if (order.deadline <= block.timestamp) revert OrderExpired();
        if (order.seller != msg.sender) revert NotATokenOwner();

        address collectionAddress = getCollectionAddress(order.collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);

        address owner = collection.ownerOf(order.tokenId);
        if (owner != msg.sender) revert NotATokenOwner();

        if (!collection.isTokenApproved(order.tokenId, address(this))) {
            revert MarketplaceHasNoApprovalForSale();
        }
    }

    /// @notice Buys an unminted token directly from a collection
    /// @param collectionId The collection ID
    function buyUnmintedToken(uint256 collectionId) external payable nonReentrant onlyOperational {
        address collectionAddress = getCollectionAddress(collectionId);
        IERC721Collection collection = IERC721Collection(collectionAddress);

        if (collection.remainingSupply() == 0) revert NoUnmintedTokens();
        uint256 mintPrice = collection.mintPrice();
        if (msg.value < mintPrice) revert InsufficientPayment();

        uint256 supplyBefore = collection.getSupply();
        collection.mint{value: mintPrice}();

        uint256 supplyAfter = collection.getSupply();
        if (supplyAfter != supplyBefore + 1) revert MintFailed();
        uint256 tokenId = supplyAfter;

        collection.safeTransferFrom(address(this), msg.sender, tokenId);

        uint256 refund = msg.value - mintPrice;
        if (refund > 0) {
            (bool successRefund,) = payable(msg.sender).call{value: refund}("");
            if (!successRefund) revert PaymentFailed();
        }

        emit UnmintedTokenPurchased(msg.sender, collectionId, tokenId, mintPrice);
    }

    /// @notice Activates the marketplace
    function activateMarketplace() external onlyMultisig {
        if (_isMarketplaceActive) revert MarketplaceIsActiveAlready();
        _isMarketplaceActive = true;
        emit MarketplaceActivated();
    }

    /// @notice Stops the marketplace
    function stopMarketplace() external onlyMultisig {
        if (!_isMarketplaceActive) revert MarketplaceIsStoppedAlready();
        _isMarketplaceActive = false;
        emit MarketplaceStopped();
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

    /// @notice Sets the marketplace fee amount (in basis points)
    /// @param newMarketplaceFeeAmount The new fee amount (max 500 = 5%)
    function setMarketplaceFeeAmount(uint256 newMarketplaceFeeAmount) external onlyMultisig {
        if (newMarketplaceFeeAmount > 500) revert InvalidMarketplaceFeeAmount();
        _marketplaceFeeAmount = newMarketplaceFeeAmount;
        emit MarketplaceFeeAmountSet(newMarketplaceFeeAmount);
    }

    /// @notice Sets the marketplace fee receiver address
    /// @param newMarketplaceFeeReceiver The new address
    function setMarketplaceFeeReceiver(address newMarketplaceFeeReceiver) external onlyMultisig {
        if (newMarketplaceFeeReceiver == address(0)) revert ZeroAddress();
        _marketplaceFeeReceiver = newMarketplaceFeeReceiver;
        emit MarketplaceFeeReceiverSet(newMarketplaceFeeReceiver);
    }

    /// @notice Withdraws accumulated marketplace fees
    function withdrawMarketplaceFees() external nonReentrant onlyMultisig {
        uint256 balance = address(this).balance;
        if (balance == 0) revert PaymentFailed();

        (bool success,) = payable(_marketplaceFeeReceiver).call{value: balance}("");
        if (!success) revert PaymentFailed();
    }

    /// @notice Checks if an order nonce has been used
    function isOrderNonceUsed(address seller, uint256 nonce) external view returns (bool) {
        return _usedNoncesOrders[seller][nonce];
    }

    /// @notice Checks if an offer nonce has been used
    function isOfferNonceUsed(address buyer, uint256 nonce) external view returns (bool) {
        return _usedNoncesOffers[buyer][nonce];
    }

    /// @notice Checks if the marketplace is active
    function isMarketplaceActive() external view returns (bool) {
        return _isMarketplaceActive;
    }

    /// @notice Checks if an order has been cancelled
    function isOrderCancelled(Order memory order) external view returns (bool) {
        bytes32 orderHash = keccak256(abi.encodePacked(
            order.seller,
            order.collectionId,
            order.tokenId,
            order.price,
            order.nonce,
            order.deadline
        ));
        return _cancelledOrders[orderHash];
    }

    /// @notice Checks if an offer has been cancelled
    function isOfferCancelled(Offer memory offer) external view returns (bool) {
        bytes32 offerHash = keccak256(abi.encodePacked(
            offer.buyer,
            offer.collectionId,
            offer.tokenId,
            offer.price,
            offer.nonce,
            offer.deadline
        ));
        return _cancelledOffers[offerHash];
    }

    /// @notice Returns marketplace settings
    function getMarketplaceSettings() external view returns (
        uint256 minPrice,
        uint256 marketplaceFeeAmount,
        address feeReceiver,
        address wethAddress,
        address factoryAddress
    ) {
        return (
            MIN_PRICE,
            _marketplaceFeeAmount,
            _marketplaceFeeReceiver,
            weth,
            address(_factory)
        );
    }

    /// @notice Returns the EIP-712 domain separator
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Returns the marketplace fee receiver
    function getMarketplaceFeeReceiver() external view returns (address) {
        return _marketplaceFeeReceiver;
    }

    /// @notice Returns the marketplace fee amount
    function getMarketplaceFeeAmount() external view returns (uint256) {
        return _marketplaceFeeAmount;
    }

    /// @notice IERC721Receiver implementation
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates royalty and marketplace fees for a sale
    /// @param collectionAddress The collection address
    /// @param tokenId The token ID
    /// @param price The sale price
    /// @return royaltyReceiver The royalty receiver address
    /// @return royaltyAmount The royalty amount
    /// @return marketplaceFeeAmount The marketplace fee amount
    function getAllRoyaltyAndFeeInfo(
        address collectionAddress,
        uint256 tokenId,
        uint256 price
    ) public view returns (address royaltyReceiver, uint256 royaltyAmount, uint256 marketplaceFeeAmount) {
        (royaltyReceiver, royaltyAmount) = IERC2981(collectionAddress).royaltyInfo(tokenId, price);
        uint256 maxRoyaltyAmount = (price * 1000) / FEE_DENOMINATOR;
        if (royaltyAmount > maxRoyaltyAmount) {
            royaltyAmount = maxRoyaltyAmount;
        }
        marketplaceFeeAmount = (price * _marketplaceFeeAmount) / FEE_DENOMINATOR;
    }

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

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Authorizes contract upgrades
    function _authorizeUpgrade(address) internal override onlyMultisig {}

    /// @dev Hashes an offer struct for EIP-712 signing
    function _hashOffer(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            OFFER_TYPEHASH,
            offer.buyer,
            offer.collectionId,
            offer.tokenId,
            offer.price,
            offer.nonce,
            offer.deadline
        ));
    }
}
