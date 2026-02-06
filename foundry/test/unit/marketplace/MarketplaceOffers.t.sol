// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MarketplaceTestHelper} from "../../helpers/MarketplaceTestHelper.sol";
import {MarketplaceNFT} from "../../../src/Marketplace.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";

contract MarketplaceOffersTest is MarketplaceTestHelper {
    function test_CreateOffer_Succeeds() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);

        assertEq(offer.buyer, defaultOfferBuyer);
        assertEq(offer.collectionId, collectionId);
        assertEq(offer.tokenId, tokenId);
        assertEq(offer.price, DEFAULT_SALE_TOKEN_PRICE);
    }

    function test_CreateOffer_RevertIf_PriceBelowMin() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        // depositAndApproveWeth(defaultOfferBuyer, DEFAULT_SALE_TOKEN_PRICE);

        vm.expectRevert(MarketplaceNFT.IncorrectPrice.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.createOffer(
            collectionId,
            tokenId,
            0,
            DEFAULT_NONCE,
            DEFAULT_DEADLINE
        );
    }

    function test_CreateOffer_RevertIf_BuyerOwnsToken() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(defaultOfferBuyer);

        vm.expectRevert(MarketplaceNFT.InvalidOfferOperation.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.createOffer(
            collectionId,
            tokenId,
            DEFAULT_SALE_TOKEN_PRICE,
            DEFAULT_NONCE,
            DEFAULT_DEADLINE
        );
    }

    function test_CreateOffer_RevertIf_InsufficientBalance() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.createOffer(
            collectionId,
            tokenId,
            DEFAULT_SALE_TOKEN_PRICE,
            DEFAULT_NONCE,
            DEFAULT_DEADLINE
        );
    }

    function test_CreateOffer_RevertIf_AllowanceMissing() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        vm.deal(defaultOfferBuyer, DEFAULT_BALANCE);
        vm.startPrank(defaultOfferBuyer);
        weth.deposit{value: DEFAULT_SALE_TOKEN_PRICE}();
        vm.stopPrank();

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.createOffer(
            collectionId,
            tokenId,
            DEFAULT_SALE_TOKEN_PRICE,
            DEFAULT_NONCE,
            DEFAULT_DEADLINE
        );
    }

    function test_ExecuteOffer_Succeeds() public {
        (uint256 collectionId, address collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        vm.startPrank(USER1);
        uint256 tokenId = collection.getNextTokenId();
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        collection.setApprovalForAll(address(marketplace), true);
        vm.stopPrank();

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        (address royaltyReceiver, uint256 royaltyAmount, uint256 marketplaceFeeAmount) = marketplace
            .getAllRoyaltyAndFeeInfo(collectionAddress, tokenId, offer.price);
        uint256 sellerWethBalanceBefore = IERC20(address(weth)).balanceOf(USER1);
        uint256 buyerWethBalanceBefore = IERC20(address(weth)).balanceOf(defaultOfferBuyer);
        uint256 royaltyReceiverBalanceBefore = IERC20(address(weth)).balanceOf(royaltyReceiver);
        address feeReceiver = marketplace.getMarketplaceFeeReceiver();
        uint256 feeReceiverBalanceBefore = IERC20(address(weth)).balanceOf(feeReceiver);
        uint256 sellerProceeds = offer.price - marketplaceFeeAmount - royaltyAmount;

        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);
        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);

        assertEq(collection.ownerOf(tokenId), defaultOfferBuyer);
        assertTrue(marketplace.isOfferNonceUsed(defaultOfferBuyer, DEFAULT_NONCE));
        assertEq(IERC20(address(weth)).balanceOf(USER1), sellerWethBalanceBefore + sellerProceeds + (feeReceiver == USER1 ? marketplaceFeeAmount : 0));
        assertEq(IERC20(address(weth)).balanceOf(defaultOfferBuyer) + offer.price, buyerWethBalanceBefore);
        assertEq(IERC20(address(weth)).balanceOf(royaltyReceiver), royaltyReceiverBalanceBefore + royaltyAmount);
        assertEq(
            IERC20(address(weth)).balanceOf(feeReceiver),
            feeReceiverBalanceBefore + marketplaceFeeAmount + (feeReceiver == USER1 ? sellerProceeds : 0)
        );
    }

    function test_ExecuteOffer_RevertIf_Expired() public {
        (uint256 collectionId, address collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        vm.startPrank(USER1);
        uint256 tokenId = collection.getNextTokenId();
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        collection.setApprovalForAll(address(marketplace), true);
        vm.stopPrank();

        depositAndApproveWeth(defaultOfferBuyer, DEFAULT_SALE_TOKEN_PRICE);
        vm.prank(defaultOfferBuyer);
        MarketplaceNFT.Offer memory offer = marketplace.createOffer(
            collectionId,
            tokenId,
            DEFAULT_SALE_TOKEN_PRICE,
            DEFAULT_NONCE,
            block.timestamp + 100
        );

        vm.warp(block.timestamp + 101);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.expectRevert(MarketplaceNFT.OfferExpired.selector);
        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);
    }

    function test_ExecuteOffer_RevertIf_InvalidSignature() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory wrongSignature = signOffer(offer, 0x999);

        vm.expectRevert(MarketplaceNFT.InvalidSignature.selector);
        marketplace.executeOffer(offer, wrongSignature);
    }

    function test_ExecuteOffer_RevertIf_BuyerBalanceRemoved() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.deal(defaultOfferBuyer, DEFAULT_BALANCE);

        vm.prank(defaultOfferBuyer);
        weth.withdraw(DEFAULT_SALE_TOKEN_PRICE);

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);
    }

    function test_ExecuteOffer_RevertIf_BuyerRevokesAllowance() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.prank(defaultOfferBuyer);
        IERC20(address(weth)).approve(address(marketplace), 0);

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);
    }

    function test_ExecuteOffer_RevertIf_CallerNotOwner() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(USER3);
        marketplace.executeOffer(offer, signature);
    }

    function test_CancelOffer_Succeeds() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.prank(defaultOfferBuyer);
        marketplace.cancelOffer(offer, signature);

        assertTrue(marketplace.isOfferCancelled(offer));
    }

    function test_CancelOffer_RevertIf_InvalidCaller() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(USER1);
        marketplace.cancelOffer(offer, signature);
    }

    function test_CancelOffer_RevertIf_InvalidSignature() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory wrongSignature = signOffer(offer, 0x999);

        vm.expectRevert(MarketplaceNFT.InvalidSignature.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.cancelOffer(offer, wrongSignature);
    }

    function test_CancelOffer_RevertIf_AlreadyExecuted() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);

        vm.expectRevert(MarketplaceNFT.OfferNotCancellable.selector);
        vm.prank(defaultOfferBuyer);
        marketplace.cancelOffer(offer, signature);
    }

    function test_OfferCancellationState() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        assertFalse(marketplace.isOfferCancelled(offer));

        vm.prank(defaultOfferBuyer);
        marketplace.cancelOffer(offer, signature);

        assertTrue(marketplace.isOfferCancelled(offer));
    }
}


