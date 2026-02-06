// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketplaceTestHelper} from "../../helpers/MarketplaceTestHelper.sol";
import {MarketplaceNFT} from "../../../src/Marketplace.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";

contract MarketplaceOrdersTest is MarketplaceTestHelper {
    function test_PutTokenOnSale_Succeeds() public {
        (MarketplaceNFT.Order memory order, address collectionAddress, uint256 tokenId) = buyTokenAndApprove(USER2);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        vm.prank(order.seller);
        marketplace.putTokenOnSale(order);

        assertTrue(collection.isTokenApproved(tokenId, address(marketplace)));
        assertEq(order.seller, USER2);
        assertEq(order.nonce, DEFAULT_NONCE);
    }

    function test_PutTokenOnSale_RevertIf_PriceBelowMin() public {
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(USER1);
        order.price = marketplace.MIN_PRICE() - 1;

        vm.expectRevert(MarketplaceNFT.IncorrectPrice.selector);
        vm.prank(order.seller);
        marketplace.putTokenOnSale(order);
    }

    function test_PutTokenOnSale_RevertIf_DeadlinePassed() public {
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(USER1);
        order.deadline = block.timestamp;

        vm.expectRevert(MarketplaceNFT.OrderExpired.selector);
        vm.prank(order.seller);
        marketplace.putTokenOnSale(order);
    }

    function test_PutTokenOnSale_RevertIf_CallerNotSeller() public {
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(USER1);

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(USER2);
        marketplace.putTokenOnSale(order);
    }

    function test_PutTokenOnSale_RevertIf_NotTokenOwner() public {
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(USER1);
        order.seller = USER2;

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(USER2);
        marketplace.putTokenOnSale(order);
    }

    function test_PutTokenOnSale_RevertIf_NoMarketplaceApproval() public {
        (MarketplaceNFT.Order memory order, address collectionAddress,) = buyTokenAndApprove(USER1);
        ERC721Collection collection = ERC721Collection(collectionAddress);

        vm.prank(order.seller);
        collection.setApprovalForAll(address(marketplace), false);

        vm.expectRevert(MarketplaceNFT.MarketplaceHasNoApprovalForSale.selector);
        vm.prank(order.seller);
        marketplace.putTokenOnSale(order);
    }

    function test_CancelOrder_Succeeds() public {
        uint256 sellerPk = DEFAULT_SELLER_PRIVATE_KEY;
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(vm.addr(sellerPk));
        bytes memory signature = signOrder(order, sellerPk);

        vm.prank(order.seller);
        marketplace.cancelOrder(order, signature);

        assertTrue(marketplace.isOrderCancelled(order));
    }

    function test_CancelOrder_RevertIf_InvalidCaller() public {
        uint256 sellerPk = DEFAULT_SELLER_PRIVATE_KEY;
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(vm.addr(sellerPk));
        bytes memory signature = signOrder(order, sellerPk);

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(USER3);
        marketplace.cancelOrder(order, signature);
    }

    function test_CancelOrder_RevertIf_InvalidSignature() public {
        uint256 sellerPk = DEFAULT_SELLER_PRIVATE_KEY;
        (MarketplaceNFT.Order memory order,,) = buyTokenAndApprove(vm.addr(sellerPk));
        bytes memory wrongSignature = signOrder(order, 0x999);

        vm.expectRevert(MarketplaceNFT.InvalidSignature.selector);
        vm.prank(order.seller);
        marketplace.cancelOrder(order, wrongSignature);
    }

    function test_CancelOrder_RevertIf_OrderExecuted() public {
        uint256 sellerPk = DEFAULT_SELLER_PRIVATE_KEY;
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(sellerPk));
        executeOrderWithSignature(info, sellerPk);

        bytes memory signature = signOrder(info.order, sellerPk);

        vm.expectRevert(MarketplaceNFT.OrderNotCancellable.selector);
        vm.prank(info.order.seller);
        marketplace.cancelOrder(info.order, signature);
    }

    function test_ExecuteOrder_Succeeds() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        address seller = info.order.seller;
        uint256 sellerBalanceBefore = seller.balance;
        uint256 buyerBalanceBefore = ORDER_EXECUTER.balance;
        address feeReceiver = marketplace.getMarketplaceFeeReceiver();
        uint256 feeReceiverBalanceBefore = feeReceiver.balance;
        uint256 royaltyReceiverBalanceBefore = info.royaltyReceiver.balance;
        uint256 sellerProceeds = info.order.price - info.marketplaceFeeAmount - info.royaltyAmount;

        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);

        assertEq(ERC721Collection(info.collectionAddress).ownerOf(info.order.tokenId), ORDER_EXECUTER);
        assertEq(seller.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(ORDER_EXECUTER.balance, buyerBalanceBefore - info.order.price);
        assertEq(feeReceiver.balance, feeReceiverBalanceBefore + info.marketplaceFeeAmount);
        assertEq(info.royaltyReceiver.balance, royaltyReceiverBalanceBefore + info.royaltyAmount);
        assertTrue(marketplace.isOrderNonceUsed(info.order.seller, info.order.nonce));
    }

    function test_ExecuteOrder_RevertIf_InsufficientPayment() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        vm.expectRevert(MarketplaceNFT.InsufficientPayment.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price - 1}(info.order, signature);
    }

    function test_ExecuteOrder_RevertIf_OrderExpired() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        vm.warp(info.order.deadline + 1);
        vm.expectRevert(MarketplaceNFT.OrderExpired.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);
    }

    function test_ExecuteOrder_RevertIf_Cancelled() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        vm.prank(info.order.seller);
        marketplace.cancelOrder(info.order, signature);

        vm.expectRevert(MarketplaceNFT.OrderIsCancelled.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);
    }

    function test_ExecuteOrder_RevertIf_InvalidSignature() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        bytes memory wrongSignature = signOrder(info.order, 0x999);

        vm.expectRevert(MarketplaceNFT.InvalidSignature.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, wrongSignature);
    }

    function test_ExecuteOrder_RevertIf_NoMarketplaceApproval() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        ERC721Collection collection = ERC721Collection(info.collectionAddress);
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        vm.prank(info.order.seller);
        collection.setApprovalForAll(address(marketplace), false);

        vm.expectRevert(MarketplaceNFT.MarketplaceHasNoApprovalForSale.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);
    }

    function test_ExecuteOrder_RevertIf_NotOwner() public {
        OrderExecutionInfo memory info = buildOrderExecutionInfo(vm.addr(DEFAULT_SELLER_PRIVATE_KEY));
        ERC721Collection collection = ERC721Collection(info.collectionAddress);
        bytes memory signature = signOrder(info.order, DEFAULT_SELLER_PRIVATE_KEY);

        vm.prank(info.order.seller);
        collection.transferFrom(info.order.seller, USER3, info.order.tokenId);

        vm.expectRevert(MarketplaceNFT.NotATokenOwner.selector);
        vm.prank(ORDER_EXECUTER);
        marketplace.executeOrder{value: info.order.price}(info.order, signature);
    }
}

