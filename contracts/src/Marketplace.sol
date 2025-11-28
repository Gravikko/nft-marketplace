// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol"; 
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {EIP712Upgradeable} from "openzeppelin-contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {IERC2981} from "openzeppelin-contracts/interfaces/IERC2981.sol";
import {IERC721Collection} from "./interfaces/IERC721Collection.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

/// @title Interface for MultisigTimelock verification
interface IMultisigTimelock {
    function verifyCurrentTransaction() external view;
}

/// @title An NFT Marketplace
/// @notice 
/// TODO: 
/// ready C) Off-chain signed orders (EIP-712) — наиболее популярно для масштабируемых маркетплейсов


contract MarketplaceNFT is 
    Initializable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuard,
    IERC721Receiver
{

    /**
     * @dev Order struct for EIP-712
     */
    struct Order {
        address seller;
        uint256 collectionId;
        uint256 tokenId;
        uint256 price;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @dev Offer struct for EIP-712 
     */
    struct Offer {
        address buyer;
        uint256 collectionId;
        uint256 tokenId;
        uint256 price;
        uint256 nonce;
        uint256 deadline;
    }

    bool private _isMarketplaceActive;
    address public _weth;
    address private _multisigTimelock;
    address private _marketplaceFeeReceiver;
    uint256 private _marketplaceFeeAmount;
    uint256 public constant MIN_PRICE = 1000 wei;
    uint256 private constant FEE_DENOMINATOR = 10_000; // Used only for marketplace fee calculation (basis points)
    IFactory private _factoryTyped;
    mapping(bytes32 => bool) private _cancelledOrders;
    mapping(bytes32 => bool) private _cancelledOffers;
    mapping(address => mapping(uint256 => bool)) private _usedNoncesOrders;
    mapping(address => mapping(uint256 => bool)) private _usedNoncesOffers;
    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address seller,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant OFFER_TYPEHASH = keccak256(
        "Offer(address buyer,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
    );

    /* Events */
    event MarketplaceIsActive();
    event MarketplaceSetStopped();
    event MultisigTimelockSet(address indexed multisigTimelock);
    event NewFactoryAddressSet(address indexed newFactory);
    event NewMarketplaceFeeAmountSet(uint256 indexed feeAmount);
    event NewMarketplaceFeeReceiverSet(address indexed newMarketplaceFeeReceiver);
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

    /* Errors */
    error IncorrectPrice();
    error InsufficientPayment();
    error InvalidBidAddress();
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

    modifier onlyMultisig() {
        if (msg.sender != _multisigTimelock) {
            revert NotAMultisigTimelock();
        }
        IMultisigTimelock(_multisigTimelock).verifyCurrentTransaction();
        _;
    }

    modifier onlyOperational() {
        if (!_isMarketplaceActive) revert MarketplaceIsStopped();
        if (address(_factoryTyped) == address(0)) revert NoFactoryAddressSet();
        _;
    }

    constructor() {
        _disableInitializers();
    }    

    function initialize(address multisigTimelock, address weth) external initializer {
        __EIP712_init("MarketplaceNFT", "1");
        //__ReentrancyGuard_init();
        if (multisigTimelock == address(0)) revert ZeroAddress();
        if (weth == address(0)) revert ZeroAddress();
        _multisigTimelock = multisigTimelock;
        _weth = weth;
    }

    /**
     * @dev Set new MultisigTimelock address
     */
    function setMultisigTimelock(address newMultisigTimelock) external onlyMultisig {
        if (newMultisigTimelock == address(0)) revert ZeroAddress();
        _multisigTimelock = newMultisigTimelock;
        emit MultisigTimelockSet(newMultisigTimelock);
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
     * @dev Set Marketplace Fee amount
     */
    function setMarketplaceFeeAmount(uint256 newMarketplaceFeeAmount) external onlyMultisig {
        if (newMarketplaceFeeAmount > 500) revert InvalidMarketplaceFeeAmount();
        _marketplaceFeeAmount = newMarketplaceFeeAmount;
        emit NewMarketplaceFeeAmountSet(newMarketplaceFeeAmount);
    }

    /**
     * @dev Set Marketplace active
     */
    function activateMarketplace() external onlyMultisig {
        if (_isMarketplaceActive) revert MarketplaceIsActiveAlready();
        _isMarketplaceActive = true;
        emit MarketplaceIsActive();
    }

    /**
     * @dev Set Marketplace stopped
     */
    function stopMarketplace() external onlyMultisig {
        if (!_isMarketplaceActive) revert MarketplaceIsStoppedAlready();
        _isMarketplaceActive = false;
        emit MarketplaceSetStopped();
    }

    /**
     * @dev Users create offer for buying specific NFT
     * @notice before purchasing users have to approve needed amount of WETH
     */
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

        IERC20 weth = IERC20(_weth);
        if (weth.balanceOf(msg.sender) < price) revert InsufficientPayment();
        if (weth.allowance(msg.sender, address(this)) < price) revert InsufficientPayment(); 

        return Offer({
            buyer: msg.sender,
            collectionId: collectionId,
            tokenId: tokenId,
            price: price,
            nonce: nonce,
            deadline: deadline
        });
    }


    /**
     * @dev Execute offer
     * @notice Buyer has to have enough amount of token which were approved
     */
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
        uint256 nonce = offer.nonce;
        uint256 deadline = offer.deadline;

        {
            IERC20 weth = IERC20(_weth);
            if (weth.balanceOf(buyer) < price) revert InsufficientPayment();
            if (weth.allowance(buyer, address(this)) < price) revert InsufficientPayment();
            if (!weth.transferFrom(buyer, address(this), price)) revert PaymentFailed();
        }

        address collectionAddress = getCollectionAddress(collectionId);

        IERC721Collection collection = IERC721Collection(collectionAddress);
        address seller = msg.sender;
        
        // Scope owner check
        {
            address owner = collection.ownerOf(tokenId);
            if (owner != seller) revert NotATokenOwner();
        }

        // Calculate fees in scoped block
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

        _usedNoncesOffers[buyer][nonce] = true;
        collection.safeTransferFrom(seller, buyer, tokenId);

        // Execute payments in scoped blocks
        IERC20 weth = IERC20(_weth);
        if (sellerProceeds > 0 && !weth.transfer(seller, sellerProceeds)) revert PaymentFailed();
        if (royaltyReceiver != address(0) && royaltyAmount > 0 && !weth.transfer(royaltyReceiver, royaltyAmount)) revert PaymentFailed();
        if (_marketplaceFeeReceiver != address(0) && marketplaceFeeAmount > 0 && !weth.transfer(_marketplaceFeeReceiver, marketplaceFeeAmount)) revert PaymentFailed();

        emit NonceMarkedUsed(buyer, nonce);
        emit OfferExecuted(
            buyer,
            seller,
            collectionId,
            tokenId,
            price,
            nonce,
            deadline
        );
    }

    /**
     * @dev Cancel current Order
     * @notice requires signature of offer creator
     */
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

    /**
     * @dev Execute order - THIS is the transaction users call
     * @notice Buyer calls this with signed order to purchase NFT
     */
     function executeOrder(
        Order memory order,
        bytes memory signature
    ) external payable nonReentrant onlyOperational {
        if (msg.value < order.price) revert InsufficientPayment();
        if (order.deadline < block.timestamp) revert OrderExpired();
        if (_usedNoncesOrders[order.seller][order.nonce]) revert NonceAlreadyUsed();

        // Scope validation variables
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

        // Scope owner check
        {
            address owner = collection.ownerOf(order.tokenId);
            if (owner != order.seller) revert NotATokenOwner();
            if (!collection.isTokenApproved(order.tokenId, address(this))) {
                revert MarketplaceHasNoApprovalForSale();
            }
        }

        _usedNoncesOrders[order.seller][order.nonce] = true;
        collection.safeTransferFrom(order.seller, msg.sender, order.tokenId);

        // Calculate fees and payments in scoped block
        address royaltyReceiver;
        uint256 royaltyAmount;
        uint256 marketplaceFeeAmount;
        uint256 sellerProceeds;

        {
            (royaltyReceiver, royaltyAmount, marketplaceFeeAmount) = getAllRoyaltyAndFeeInfo(collectionAddress, order.tokenId, order.price);
            sellerProceeds = order.price - royaltyAmount - marketplaceFeeAmount;
        }

        // Execute payments in scoped blocks
        {
            (bool successSeller, ) = payable(order.seller).call{value: sellerProceeds}("");
            if (!successSeller) revert PaymentFailed();
        }

        if (royaltyReceiver != address(0) && royaltyAmount > 0) {
            (bool successRoyaltyReceiver, ) = payable(royaltyReceiver).call{value: royaltyAmount}("");
            if (!successRoyaltyReceiver) revert PaymentFailed();
        }

        if (_marketplaceFeeReceiver != address(0)) {
            (bool successMarketplaceFeeReceiver, ) = payable(_marketplaceFeeReceiver).call{value: marketplaceFeeAmount}("");
            if (!successMarketplaceFeeReceiver) revert PaymentFailed();
        }

        {
            uint256 refund = msg.value - order.price;
            if (refund > 0) {
                (bool successRefund, ) = payable(msg.sender).call{value: refund}("");
                if (!successRefund) revert PaymentFailed();
            }
        }

        emit OrderExecuted(order.seller, msg.sender, order.collectionId, order.tokenId, order.price);
    }

    /**
     * @dev Cancel current Order
     * @notice requires signature of order creator
     */
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
    
    /**
     * @dev Buy unminted token from collection
     * @notice Buyer pays mintPrice and receives a newly minted token
     */
    function buyUnmintedToken(uint256 collectionId) external payable onlyOperational {

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
            (bool successRefund, ) = payable(msg.sender).call{value: refund}("");
            if (!successRefund) revert PaymentFailed();
        }

        emit UnmintedTokenPurchased(msg.sender, collectionId, tokenId, mintPrice);
    }

    /**
     * @dev Set new marketplace fees receiver address
     */
    function setMarketplaceFeeReceiver(address newMarketplaceFeeReceiver) external onlyMultisig {
        if (newMarketplaceFeeReceiver == address(0)) revert ZeroAddress();
        _marketplaceFeeReceiver = newMarketplaceFeeReceiver;
        emit NewMarketplaceFeeReceiverSet(newMarketplaceFeeReceiver);
    }

    /**
     * @dev Withdraw accumulated marketplace fees
     */
    function withdrawMarketplaceFees() external onlyMultisig {
        uint256 balance = address(this).balance;
        if (balance == 0) revert PaymentFailed();
        
        (bool success, ) = payable(_marketplaceFeeReceiver).call{value: balance}("");
        if (!success) revert PaymentFailed();
    }

    /**
     * @dev Put token on the sale
     */
    function putTokenOnSale(
        Order memory order
    ) external view onlyOperational {
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

    /**
     * @dev Check if an order nonce has been used
     * @param seller The address of the seller
     * @param nonce The nonce to check
     * @return used Whether the nonce has been used
     */
    function isOrderNonceUsed(address seller, uint256 nonce) external view returns (bool used) {
        return _usedNoncesOrders[seller][nonce];
    }

    /**
     * @dev Check Marketplace status
     */
    function isMarketplaceActive() external view returns (bool) {
        return _isMarketplaceActive;
    }

    /**
     * @dev Get the royalty, marketplace fee amount and royalty receiver
     */
    function getAllRoyaltyAndFeeInfo(address collectionAddress, uint256 tokenId, uint256 price) public view returns (address royaltyReceiver, uint256 royaltyAmount, uint256 marketplaceFeeAmount) {
        (royaltyReceiver, royaltyAmount) = IERC2981(collectionAddress).royaltyInfo(tokenId, price);
        uint256 maxRoyaltyAmount = (price * 1000) / FEE_DENOMINATOR; 
        if (royaltyAmount > maxRoyaltyAmount) {
            royaltyAmount = maxRoyaltyAmount;
        }
        marketplaceFeeAmount = (price * _marketplaceFeeAmount) / FEE_DENOMINATOR;
    }

    /**
     * @dev Check and return if the collection exists
     */
    function getCollectionAddress(uint256 collectionId) public view returns(address collectionAddress) {
        try _factoryTyped.getCollectionAddressById(collectionId) returns (address _collectionAddress) {
            collectionAddress = _collectionAddress;
        } catch Error (string memory reason) {
            revert(string.concat("Factory revert: ", reason));
        } catch (bytes memory) {
            revert("Factory call failed");
        }
        if (collectionAddress == address(0)) revert InvalidCollectionAddress();
    }

    /**
     * @dev Check if an offer nonce has been used
     * @param buyer The address of the buyer
     * @param nonce The nonce to check
     * @return used Whether the nonce has been used
     */
    function isOfferNonceUsed(address buyer, uint256 nonce) external view returns (bool used) {
        return _usedNoncesOffers[buyer][nonce];
    }

    /**
     * @dev Check if an order has been cancelled
     * @param order The order struct
     * @return cancelled Whether the order has been cancelled
     */
    function isOrderCancelled(Order memory order) external view returns (bool cancelled) {
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

    /**
     * @dev Check if an offer has been cancelled
     * @param offer The offer struct
     * @return cancelled Whether the offer has been cancelled
     */
    function isOfferCancelled(Offer memory offer) external view returns (bool cancelled) {
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

    /**
     * @dev Get marketplace contract settings
     * @return minPrice Minimum price for listings/offers
     * @return marketplaceFeeAmount Marketplace fee in basis points
     * @return feeReceiver Address that receives marketplace fees
     * @return wethAddress WETH token address
     * @return factoryAddress Factory contract address
     */
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
            _weth,
            address(_factoryTyped)
        );
    }

    /**
     * @dev Get the domain separator for EIP-712 signing
     * @return The domain separator
     */
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev Get the marketplace fee receiver address
     */
    function getMarketplaceFeeReceiver() external view returns(address) {
        return _marketplaceFeeReceiver;
    }

    /**
     * @dev Get the marketplace fee amount
     */
    function getMarketplaceFeeAmount() external view returns(uint256) {
        return _marketplaceFeeAmount;
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
     * @dev Authorized upgrade. Required by UUPSUpgrade
     */
    function _authorizeUpgrade(address) internal override onlyMultisig {}

    /**
     * @dev Returns offer's hash
     */
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
