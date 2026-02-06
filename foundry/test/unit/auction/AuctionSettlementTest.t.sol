// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AuctionTestBase} from "../../helpers/AuctionTestBase.sol";
import {Auction} from "../../../src/Auction.sol";
import {IERC2981} from "openzeppelin-contracts/interfaces/IERC2981.sol";


contract AuctionSettlementTest is AuctionTestBase {
    uint256 internal constant DEFAULT_DURATION = 2 hours;
    uint256 internal constant DEFAULT_MIN_BID = 1 ether;

    function test_FinalizeAuction_NoBidsReturnsNFT() public {
        (uint256 auctionId, uint256 tokenId) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        _fastForward(DEFAULT_DURATION + 1 hours);

        vm.prank(USER2);
        auction.finalizeAuction(auctionId);

        assertEq(collection.ownerOf(tokenId), USER1);
    }

    function test_FinalizeAuction_WithBidsTransfersNFT() public {
        (uint256 auctionId, uint256 tokenId) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        uint256 nextBid = auction.getNextBidAmount(auctionId);
        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: nextBid}(auctionId);

        _fastForward(DEFAULT_DURATION + 1 hours);
        vm.prank(USER4);
        auction.finalizeAuction(auctionId);

        assertEq(collection.ownerOf(tokenId), USER3);
    }

    function test_FinalizeAuction_DistributesFunds() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, 10 ether);

        vm.deal(USER2, 20 ether);
        vm.prank(USER2);
        auction.makeABid{value: 10 ether}(auctionId);

        _fastForward(DEFAULT_DURATION + 1 hours);

        (, address collectionAddress, uint256 tokenId ,,,) = auction.getAuctionInfo(auctionId);

        uint256 sellerBalanceBefore = USER1.balance;
        vm.prank(USER3);
        auction.finalizeAuction(auctionId);

        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(collectionAddress).royaltyInfo(tokenId, 10 ether);
        uint256 maxRoyalty = (10 ether * 1000) / 10_000;
        uint256 fee = (10 ether * 100) / 10_000;
        if (royaltyAmount > maxRoyalty) {
            royaltyAmount = maxRoyalty;
        }

        if (royaltyReceiver == USER1) {
            royaltyAmount = 0;
        }

        if (auction.getAuctionFeeReceiver() == USER1) {
            fee = 0;
        }

        uint256 expectedSeller = 10 ether - royaltyAmount - fee;
        assertEq(USER1.balance - sellerBalanceBefore, expectedSeller);
    }

    function test_FinalizeAuction_RevertWhenInvalidAuction() public {
        vm.expectRevert(Auction.InvalidAuction.selector);
        vm.prank(USER1);
        auction.finalizeAuction(999);
    }

    function test_FinalizeAuction_RevertWhenNotFinished() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        vm.expectRevert(Auction.AuctionIsNotFinished.selector);
        vm.prank(USER2);
        auction.finalizeAuction(auctionId);
    }

    function test_FinalizeAuction_RevertWhenAlreadyFinalized() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        _fastForward(DEFAULT_DURATION + 1 hours);

        vm.prank(USER2);
        auction.finalizeAuction(auctionId);

        vm.expectRevert(Auction.AuctionIsExpired.selector);
        vm.prank(USER2);
        auction.finalizeAuction(auctionId);
    }

    function test_WithdrawAuctionBid_ReturnsFundsToLoser() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        uint256 nextBid = auction.getNextBidAmount(auctionId);
        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: nextBid}(auctionId);

        _fastForward(DEFAULT_DURATION + 1 hours);
        vm.prank(USER4);
        auction.finalizeAuction(auctionId);

        uint256 balanceBefore = USER2.balance;
        vm.prank(USER2);
        auction.withdrawAuctionBid(auctionId);

        assertEq(USER2.balance - balanceBefore, DEFAULT_MIN_BID);
    }

    function test_WithdrawAuctionBid_RevertWhenInvalidAuction() public {
        vm.expectRevert(Auction.InvalidAuction.selector);
        vm.prank(USER2);
        auction.withdrawAuctionBid(999);
    }

    function test_WithdrawAuctionBid_RevertWhenNotFinished() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.expectRevert(Auction.AuctionIsNotFinished.selector);
        vm.prank(USER2);
        auction.withdrawAuctionBid(auctionId);
    }

    function test_WithdrawAuctionBid_RevertWhenNoBidFound() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        vm.deal(USER3, 10 ether);
        vm.deal(USER4, 10 ether);

        vm.prank(USER3);
        auction.makeABid{value: 1 ether}(auctionId);

        vm.prank(USER4);
        auction.makeABid{value: 2 ether}(auctionId);

        _fastForward(DEFAULT_DURATION + 1 hours);
        vm.prank(USER2);
        auction.finalizeAuction(auctionId);

        vm.expectRevert(Auction.UserBidNotFound.selector);
        vm.prank(USER2);
        auction.withdrawAuctionBid(auctionId);

        vm.prank(USER3);
        auction.withdrawAuctionBid(auctionId);

        vm.expectRevert(Auction.AllBidsArePaid.selector);
        vm.prank(USER3);
        auction.withdrawAuctionBid(auctionId);
    }

    function test_WithdrawAuctionBid_RevertWhenAllBidsPaid() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        _fastForward(DEFAULT_DURATION + 1 hours);
        vm.prank(USER3);
        auction.finalizeAuction(auctionId);

        vm.expectRevert(Auction.AllBidsArePaid.selector);
        vm.prank(USER2);
        auction.withdrawAuctionBid(auctionId);
    }

    function test_CancelAuction_NoBids() public {
        (uint256 auctionId, uint256 tokenId) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.prank(USER1);
        auction.cancelAuction(auctionId);

        assertEq(collection.ownerOf(tokenId), USER1);
    }

    function test_CancelAuction_RevertWhenNotAuthor() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.expectRevert(Auction.NotAnAuctionAuthor.selector);
        vm.prank(USER2);
        auction.cancelAuction(auctionId);
    }

    function test_CancelAuction_RevertWhenHasBids() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        vm.expectRevert(Auction.AuctionHasBids.selector);
        vm.prank(USER1);
        auction.cancelAuction(auctionId);
    }

    function test_CancelAuction_RevertWhenExpired() public {
        (uint256 auctionId,) = _createAuction(USER1, 1 hours, DEFAULT_MIN_BID);
        _fastForward(2 hours);

        vm.expectRevert(Auction.AuctionIsExpired.selector);
        vm.prank(USER1);
        auction.cancelAuction(auctionId);
    }

    function test_WithdrawFees() public {
        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        (bool success, ) = address(auction).call{value: 5 ether}("");

        uint256 receiverBalanceBefore = USER1.balance;
        vm.prank(multisig);
        auction.withdraw();
        assertGt(USER1.balance, receiverBalanceBefore);
    }

    function test_WithdrawFees_RevertWhenNothingToWithdraw() public {
        vm.expectRevert(Auction.InsufficientBalance.selector);
        vm.prank(multisig);
        auction.withdraw();
    }

    //==      View Tests      ==//

    function test_GetAuctionCount() public {
        assertEq(auction.getAuctionCount(), 0);
        _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        assertEq(auction.getAuctionCount(), 1);
    }

    function test_GetBlockedAmount() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        assertEq(auction.getBlockedAmount(), 0);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        assertEq(auction.getBlockedAmount(), DEFAULT_MIN_BID);
    }

    function test_GetUserBid() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        (uint256 amount, bool hasBid) = auction.getUserBid(auctionId, USER2);
        assertEq(amount, 0);
        assertFalse(hasBid);
    }

    function test_GetAllBids() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        uint256 nextBid = auction.getNextBidAmount(auctionId);
        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: nextBid}(auctionId);

        (address[] memory buyers, uint256[] memory amounts) = auction.getAllBids(auctionId);
        assertEq(buyers.length, 2);
        assertEq(amounts.length, 2);
    }

    function test_GetNextBidAmount() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        uint256 nextBid = auction.getNextBidAmount(auctionId);
        assertEq(nextBid, DEFAULT_MIN_BID);
    }

    function test_GetMaximumBid_RevertWhenNoBids() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        vm.expectRevert(Auction.NoBidsMade.selector);
        auction.getMaximumBid(auctionId);
    }

    function test_GetMaximumBid_ReturnsHighest() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        uint256 nextBid = auction.getNextBidAmount(auctionId);
        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: nextBid}(auctionId);

        (uint256 maxBid, uint256 index) = auction.getMaximumBid(auctionId);
        assertEq(maxBid, nextBid);
        assertEq(index, 1);
    }

    function test_GetAuctionInfo() public {
        (uint256 auctionId, uint256 tokenId) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        (
            address seller,
            address collectionAddress,
            uint256 storedTokenId,
            uint256 price,
            uint256 deadline,
            bool finished
        ) = auction.getAuctionInfo(auctionId);

        assertEq(seller, USER1);
        assertEq(collectionAddress, address(collection));
        assertEq(storedTokenId, tokenId);
        assertEq(price, DEFAULT_MIN_BID);
        assertGt(deadline, block.timestamp);
        assertFalse(finished);
    }

    function test_GetAuctionSettings() public {
        (
            uint256 minDuration,
            uint256 maxDuration,
            uint256 minPrice,
            uint256 extensionTime,
            uint256 minNextBidPercent,
            uint256 feeAmount,
            address feeReceiver
        ) = auction.getAuctionSettings();

        assertEq(minDuration, 30 minutes);
        assertEq(maxDuration, 7 days);
        assertEq(minPrice, 1000 wei);
        assertEq(extensionTime, 5 minutes);
        assertEq(minNextBidPercent, 5);
        assertEq(feeAmount, DEFAULT_AUCTION_FEE);
        assertEq(feeReceiver, USER1);
    }
}

