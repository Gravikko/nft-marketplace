// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {Factory} from "../../src/Factory.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

abstract contract MarketplaceTestHelper is DeployHelpers {
    MarketplaceNFT public marketplace;
    Factory public factory;
    address public multisig;
    IWETH internal weth;

    uint256 internal constant DEFAULT_BUYER_PRIVATE_KEY = 0xB0B;
    address internal defaultOfferBuyer;

    struct OrderExecutionInfo {
        MarketplaceNFT.Order order;
        address collectionAddress;
        uint256 tokenId;
        address royaltyReceiver;
        uint256 royaltyAmount;
        uint256 marketplaceFeeAmount;
    }

    allDeployments public allContracts;

    function setUp() public virtual override {
        super.setUp();
        allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        marketplace = allContracts.marketplace;
        factory = allContracts.factory;
        weth = IWETH(address(allContracts.weth));

        defaultOfferBuyer = vm.addr(DEFAULT_BUYER_PRIVATE_KEY);
        vm.label(defaultOfferBuyer, "offer_buyer");
        vm.deal(defaultOfferBuyer, DEFAULT_BALANCE);
    }

    function createCollectionAndBuy(address buyer)
        internal
        returns (ERC721Collection collection, uint256 collectionId, uint256 tokenId)
    {
        address collectionAddress;
        (collectionId, collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        collection = ERC721Collection(collectionAddress);

        vm.deal(buyer, DEFAULT_MINT_PRICE);
        tokenId = collection.getNextTokenId();
        vm.prank(buyer);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
    }

    function buyTokenAndApprove(address seller)
        internal
        returns (MarketplaceNFT.Order memory order, address collectionAddress, uint256 tokenId)
    {
        (uint256 collectionId, address addr) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        ERC721Collection collection = ERC721Collection(addr);

        vm.deal(seller, DEFAULT_BALANCE); 

        vm.startPrank(seller);
        tokenId = collection.getNextTokenId();
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        collection.setApprovalForAll(address(marketplace), true);
        vm.stopPrank();

        order = MarketplaceNFT.Order({
            seller: seller,
            collectionId: collectionId,
            tokenId: tokenId,
            price: DEFAULT_SALE_TOKEN_PRICE,
            nonce: DEFAULT_NONCE,
            deadline: DEFAULT_DEADLINE
        });
        collectionAddress = addr;
    }

    function buildOrderExecutionInfo(address seller) internal returns (OrderExecutionInfo memory info) {
        (info.order, info.collectionAddress, info.tokenId) = buyTokenAndApprove(seller);
        (info.royaltyReceiver, info.royaltyAmount, info.marketplaceFeeAmount) = marketplace.getAllRoyaltyAndFeeInfo(
            info.collectionAddress,
            info.tokenId,
            info.order.price
        );
    }

    function executeOrderWithSignature(OrderExecutionInfo memory info, uint256 sellerPrivateKey) internal {
        bytes memory signature = signOrder(info.order, sellerPrivateKey);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);
    }

    function signOrder(MarketplaceNFT.Order memory order, uint256 signerPrivateKey) internal view returns (bytes memory) {
        bytes32 ORDER_TYPEHASH = keccak256(
            "Order(address seller,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.seller,
                order.collectionId,
                order.tokenId,
                order.price,
                order.nonce,
                order.deadline
            )
        );

        bytes32 domainSeparator = marketplace.getDomainSeparator();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function signOffer(MarketplaceNFT.Offer memory offer, uint256 signerPrivateKey) internal view returns (bytes memory) {
        bytes32 OFFER_TYPEHASH = keccak256(
            "Offer(address buyer,uint256 collectionId,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                offer.buyer,
                offer.collectionId,
                offer.tokenId,
                offer.price,
                offer.nonce,
                offer.deadline
            )
        );

        bytes32 domainSeparator = marketplace.getDomainSeparator();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function depositAndApproveWeth(address buyer, uint256 amount) internal {
        vm.deal(buyer, DEFAULT_BALANCE);
        vm.startPrank(buyer);
        weth.deposit{value: amount}();
        weth.approve(address(marketplace), amount);
        vm.stopPrank();
    }

    function createOffer(uint256 collectionId, uint256 tokenId) internal returns (MarketplaceNFT.Offer memory offer) {
        depositAndApproveWeth(defaultOfferBuyer, DEFAULT_SALE_TOKEN_PRICE);
        vm.prank(defaultOfferBuyer);
        offer = marketplace.createOffer(
            collectionId,
            tokenId,
            DEFAULT_SALE_TOKEN_PRICE,
            DEFAULT_NONCE,
            DEFAULT_DEADLINE
        );
    }
}

