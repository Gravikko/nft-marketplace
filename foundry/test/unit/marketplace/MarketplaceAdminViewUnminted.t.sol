// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketplaceTestHelper} from "../../helpers/MarketplaceTestHelper.sol";
import {MarketplaceNFT} from "../../../src/Marketplace.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";

contract MarketplaceAdminViewUnmintedTest is MarketplaceTestHelper {
    function test_SetMarketplaceFeeAmount_Succeeds() public {
        uint256 newFee = 200;

        vm.expectEmit(true, false, false, false);
        emit MarketplaceNFT.MarketplaceFeeAmountSet(newFee);

        vm.prank(multisig);
        marketplace.setMarketplaceFeeAmount(newFee);

        assertEq(marketplace.getMarketplaceFeeAmount(), newFee);
    }

    function test_SetMarketplaceFeeAmount_RevertIf_TooHigh() public {
        vm.expectRevert(MarketplaceNFT.InvalidMarketplaceFeeAmount.selector);
        vm.prank(multisig);
        marketplace.setMarketplaceFeeAmount(501);
    }

    function test_SetMarketplaceFeeReceiver_Succeeds() public {
        address newReceiver = USER2;

        vm.expectEmit(true, false, false, false);
        emit MarketplaceNFT.MarketplaceFeeReceiverSet(newReceiver);

        vm.prank(multisig);
        marketplace.setMarketplaceFeeReceiver(newReceiver);

        assertEq(marketplace.getMarketplaceFeeReceiver(), newReceiver);
    }

    function test_AdminFunctions_RevertIf_NotMultisig() public {
        vm.expectRevert(MarketplaceNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        marketplace.setMarketplaceFeeAmount(100);

        vm.expectRevert(MarketplaceNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        marketplace.setMarketplaceFeeReceiver(USER2);

        vm.expectRevert(MarketplaceNFT.NotAMultisigTimelock.selector);
        vm.prank(USER1);
        marketplace.activateMarketplace();
    }

    function test_SetCriticalAddresses_RevertIf_ZeroAddress() public {
        vm.startPrank(multisig);

        vm.expectRevert(MarketplaceNFT.ZeroAddress.selector);
        marketplace.setMultisigTimelock(address(0));

        vm.expectRevert(MarketplaceNFT.ZeroAddress.selector);
        marketplace.setFactoryAddress(address(0));

        vm.expectRevert(MarketplaceNFT.ZeroAddress.selector);
        marketplace.setMarketplaceFeeReceiver(address(0));

        vm.stopPrank();
    }

    function test_ActivateMarketplace_RevertIf_AlreadyActive() public {
        vm.expectRevert(MarketplaceNFT.MarketplaceIsActiveAlready.selector);
        vm.prank(multisig);
        marketplace.activateMarketplace();
    }

    function test_StopMarketplace_RevertIf_AlreadyStopped() public {
        vm.startPrank(multisig);
        marketplace.stopMarketplace();
        vm.expectRevert(MarketplaceNFT.MarketplaceIsStoppedAlready.selector);
        marketplace.stopMarketplace();
        vm.stopPrank();
    }

    function test_WithdrawMarketplaceFees_Succeeds() public {
        uint256 simulatedFees = 0.1 ether;
        vm.deal(address(marketplace), simulatedFees);
        address feeReceiver = marketplace.getMarketplaceFeeReceiver();
        uint256 receiverBalanceBefore = feeReceiver.balance;

        vm.prank(multisig);
        marketplace.withdrawMarketplaceFees();

        assertEq(address(marketplace).balance, 0);
        assertEq(feeReceiver.balance, receiverBalanceBefore + simulatedFees);
    }

    function test_WithdrawMarketplaceFees_RevertIf_ZeroBalance() public {
        vm.expectRevert(MarketplaceNFT.PaymentFailed.selector);
        vm.prank(multisig);
        marketplace.withdrawMarketplaceFees();
    }

    function test_InvalidInitialization_RevertIf_ZeroAddresses() public {
        MarketplaceNFT newMarketplace = new MarketplaceNFT();

        bytes memory initData = abi.encodeWithSelector(
            MarketplaceNFT.initialize.selector,
            address(0),
            address(allContracts.weth)
        );

        vm.expectRevert(MarketplaceNFT.ZeroAddress.selector);
        new ERC1967Proxy(address(newMarketplace), initData);

        initData = abi.encodeWithSelector(
            MarketplaceNFT.initialize.selector,
            multisig,
            address(0)
        );

        vm.expectRevert(MarketplaceNFT.ZeroAddress.selector);
        new ERC1967Proxy(address(newMarketplace), initData);
    }

    //// view functions
    
    function test_GetMarketplaceSettings() public {
        (uint256 minPrice, uint256 feeAmount, address feeReceiver, address wethAddress, address factoryAddress) =
            marketplace.getMarketplaceSettings();

        assertEq(minPrice, marketplace.MIN_PRICE());
        assertEq(feeAmount, DEFAULT_MARKETPLACE_FEE_AMOUNT);
        assertEq(feeReceiver, USER1);
        assertEq(wethAddress, address(allContracts.weth));
        assertEq(factoryAddress, address(factory));
    }

    function test_GetDomainSeparator() public {
        bytes32 domainSeparator = marketplace.getDomainSeparator();
        assertTrue(domainSeparator != bytes32(0));
    }

    function test_IsMarketplaceActive_Toggles() public {
        assertTrue(marketplace.isMarketplaceActive());

        vm.prank(multisig);
        marketplace.stopMarketplace();
        assertFalse(marketplace.isMarketplaceActive());

        vm.prank(multisig);
        marketplace.activateMarketplace();
        assertTrue(marketplace.isMarketplaceActive());
    }

    function test_GetCollectionAddress_ReturnsValue() public {
        (uint256 collectionId, address collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        assertEq(marketplace.getCollectionAddress(collectionId), collectionAddress);
    }

    function test_GetAllRoyaltyAndFeeInfo_ReturnsValues() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        address collectionAddress = marketplace.getCollectionAddress(collectionId);

        (address royaltyReceiver, uint256 royaltyAmount, uint256 marketplaceFeeAmount) = marketplace
            .getAllRoyaltyAndFeeInfo(collectionAddress, tokenId, DEFAULT_SALE_TOKEN_PRICE);

        assertEq(royaltyReceiver, COLLECTION_AUTHOR);
        assertTrue(royaltyAmount > 0);
        assertTrue(marketplaceFeeAmount > 0);
    }

    function test_IsOrderCancelled_ViewUpdates() public {
        uint256 sellerPk = DEFAULT_SELLER_PRIVATE_KEY;
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(vm.addr(sellerPk));

        assertFalse(marketplace.isOrderCancelled(order));

        bytes memory signature = signOrder(order, sellerPk);
        vm.prank(order.seller);
        marketplace.cancelOrder(order, signature);

        assertTrue(marketplace.isOrderCancelled(order));
    }

    function test_IsOrderNonceUsed_ViewUpdates() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        assertFalse(marketplace.isOrderNonceUsed(info.order.seller, info.order.nonce));

        executeOrderWithSignature(info, DEFAULT_SELLER_PRIVATE_KEY);

        assertTrue(marketplace.isOrderNonceUsed(info.order.seller, info.order.nonce));
    }

    function test_IsOfferCancelled_ViewUpdates() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);

        assertFalse(marketplace.isOfferCancelled(offer));

        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);
        vm.prank(defaultOfferBuyer);
        marketplace.cancelOffer(offer, signature);

        assertTrue(marketplace.isOfferCancelled(offer));
    }

    function test_IsOfferNonceUsed_ViewUpdates() public {
        (, uint256 collectionId, uint256 tokenId) = createCollectionAndBuy(USER1);
        ERC721Collection collection = ERC721Collection(marketplace.getCollectionAddress(collectionId));
        vm.prank(USER1);
        collection.setApprovalForAll(address(marketplace), true);

        MarketplaceNFT.Offer memory offer = createOffer(collectionId, tokenId);
        bytes memory signature = signOffer(offer, DEFAULT_BUYER_PRIVATE_KEY);

        assertFalse(marketplace.isOfferNonceUsed(defaultOfferBuyer, DEFAULT_NONCE));

        vm.prank(USER1);
        marketplace.executeOffer(offer, signature);

        assertTrue(marketplace.isOfferNonceUsed(defaultOfferBuyer, DEFAULT_NONCE));
    }



    /////////// unminted

    function test_BuyUnmintedToken_Succeeds() public {
        (uint256 collectionId, address collectionAddress) = helper_CreateCollection(USER2, factory);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        uint256 supplyBefore = collection.getSupply();
        vm.prank(USER2);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        uint256 tokenId = supplyBefore + 1;

        assertEq(collection.ownerOf(tokenId), USER2);
    }

    function test_BuyUnmintedToken_RevertIf_MarketplaceStopped() public {
        vm.prank(multisig);
        marketplace.stopMarketplace();

        (uint256 collectionId,) = helper_CreateCollection(COLLECTION_AUTHOR, factory);

        vm.expectRevert(MarketplaceNFT.MarketplaceIsStopped.selector);
        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
    }

    function test_BuyUnmintedToken_RevertIf_NoSupply() public {
        (uint256 collectionId, address collectionAddress) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        uint256 remainingSupply = collection.remainingSupply();
        for (uint256 i = 0; i < remainingSupply; i++) {
            vm.prank(USER1);
            marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
        }

        vm.expectRevert(MarketplaceNFT.NoUnmintedTokens.selector);
        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE}(collectionId);
    }

    function test_BuyUnmintedToken_RevertIf_InsufficientPayment() public {
        (uint256 collectionId,) = helper_CreateCollection(COLLECTION_AUTHOR, factory);

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE - 1}(collectionId);
    }

    function test_BuyUnmintedToken_RefundsExcessPayment() public {
        (uint256 collectionId,) = helper_CreateCollection(COLLECTION_AUTHOR, factory);
        uint256 buyerBalanceBefore = USER1.balance;
        uint256 excess = 0.05 ether;

        vm.prank(USER1);
        marketplace.buyUnmintedToken{value: DEFAULT_MINT_PRICE + excess}(collectionId);

        assertEq(USER1.balance, buyerBalanceBefore - DEFAULT_MINT_PRICE);
    }
}

