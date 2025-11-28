// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AuctionTestBase} from "../../helpers/AuctionTestBase.sol";
import {Auction} from "../../../src/Auction.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AuctionBiddingTest is AuctionTestBase {
    uint256 internal constant DEFAULT_DURATION = 1 days;
    uint256 internal constant DEFAULT_MIN_BID = 1 ether;
    uint256 immutable private EXTENSION_TIME = 5 minutes;

    function test_PutTokenOnAuction_TransfersNFT() public {
        (uint256 auctionId, uint256 tokenId) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        (address seller, address collectionAddress, uint256 storedTokenId,, uint256 deadline, bool finished) =
            auction.getAuctionInfo(auctionId);

        assertEq(seller, USER1);
        assertEq(collectionAddress, address(collection));
        assertEq(storedTokenId, tokenId);
        assertGt(deadline, block.timestamp);
        assertFalse(finished);
        assertEq(collection.ownerOf(tokenId), address(auction));
    }

    function test_PutTokenOnAuction_RevertWhenAuctionStopped() public {
        vm.prank(multisig);
        auction.stopAuction();

        uint256 tokenId = _mintToken(USER1);
        _ensureApproval(USER1);

        vm.expectRevert(Auction.AuctionIsStoppedAlready.selector);
        vm.prank(USER1);
        auction.putTokenOnAuction(collectionId, tokenId, DEFAULT_DURATION, DEFAULT_MIN_BID);
    }

    function test_PutTokenOnAuction_RevertWhenInvalidDuration() public {
        uint256 tokenId = _mintToken(USER1);
        _ensureApproval(USER1);

        vm.startPrank(USER1);
        vm.expectRevert(Auction.InvalidDuration.selector);
        auction.putTokenOnAuction(collectionId, tokenId, 10 minutes, DEFAULT_MIN_BID);

        vm.expectRevert(Auction.InvalidDuration.selector);
        auction.putTokenOnAuction(collectionId, tokenId, 8 days, DEFAULT_MIN_BID);
        vm.stopPrank();
    }

    function test_PutTokenOnAuction_RevertWhenInvalidPrice() public {
        uint256 tokenId = _mintToken(USER1);
        _ensureApproval(USER1);

        vm.expectRevert(Auction.InvalidPrice.selector);
        vm.prank(USER1);
        auction.putTokenOnAuction(collectionId, tokenId, DEFAULT_DURATION, 999 wei);
    }

    function test_PutTokenOnAuction_RevertWhenNotOwner() public {
        uint256 tokenId = _mintToken(USER1);
        _ensureApproval(USER1);

        vm.expectRevert(Auction.NotATokenOwner.selector);
        vm.prank(USER2);
        auction.putTokenOnAuction(collectionId, tokenId, DEFAULT_DURATION, DEFAULT_MIN_BID);
    }

    function test_PutTokenOnAuction_RevertWhenFactoryMissing() public {
        Auction implementation = new Auction();

        bytes memory initData = abi.encodeWithSelector(Auction.initialize.selector, multisig);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        Auction newAuction = Auction(payable(address(proxy)));

        vm.prank(multisig);
        newAuction.activateAuction();

        uint256 tokenId = _mintToken(USER1);
        _ensureApproval(USER1);

        vm.expectRevert(Auction.NoFactoryAddressSet.selector);
        vm.prank(USER1);
        newAuction.putTokenOnAuction(collectionId, tokenId, DEFAULT_DURATION, DEFAULT_MIN_BID);
    }

    function test_MakeFirstBid() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        (uint256 bidAmount, bool hasBid) = auction.getUserBid(auctionId, USER2);
        assertEq(bidAmount, DEFAULT_MIN_BID);
        assertTrue(hasBid);
    }

    function test_MakeSubsequentBidRequiresIncrement() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        uint256 nextBid = auction.getNextBidAmount(auctionId);
       assertEq(nextBid, DEFAULT_MIN_BID + (DEFAULT_MIN_BID * 5) / 100);

        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: nextBid}(auctionId);

        (uint256 bidAmount,) = auction.getUserBid(auctionId, USER3);
        assertEq(bidAmount, nextBid);
    }

    function test_MakeBid_RevertWhenOwner() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER1, 10 ether);
        vm.expectRevert(Auction.OwnerCanMakeNoBid.selector);
        vm.prank(USER1);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);
    }

    function test_MakeBid_RevertWhenExpired() public {
        (uint256 auctionId,) = _createAuction(USER1, 1 hours, DEFAULT_MIN_BID);
        _fastForward(2 hours);

        vm.deal(USER2, 10 ether);
        vm.expectRevert(Auction.AuctionIsExpired.selector);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);
    }

    function test_MakeBid_RevertWhenInsufficientValue() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.expectRevert(Auction.InsufficientPayment.selector);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID - 1}(auctionId);
    }

    function test_MakeBid_RevertWhenAuctionStopped() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.prank(multisig);
        auction.stopAuction();

        vm.deal(USER2, 10 ether);
        vm.expectRevert(Auction.AuctionIsStoppedAlready.selector);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);
    }

    function test_MultipleBidsAccumulateForSameUser() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);

        vm.deal(USER2, 10 ether);
        vm.startPrank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);
        auction.makeABid{value: 0.5 ether}(auctionId);
        vm.stopPrank();

        (uint256 bidAmount,) = auction.getUserBid(auctionId, USER2);
        assertEq(bidAmount, 1.5 ether);
    }

    function test_BidExtendsDeadlineForHighestBid() public {
        (uint256 auctionId,) = _createAuction(USER1, DEFAULT_DURATION, DEFAULT_MIN_BID);
        (,,,, uint256 deadlineBefore,) = auction.getAuctionInfo(auctionId);

        vm.deal(USER2, 10 ether);
        vm.prank(USER2);
        auction.makeABid{value: DEFAULT_MIN_BID}(auctionId);

        (,,,, uint256 deadlineAfterFirst,) = auction.getAuctionInfo(auctionId);
        assertEq(deadlineAfterFirst, deadlineBefore + 5 minutes);

        vm.deal(USER3, 10 ether);
        vm.prank(USER3);
        auction.makeABid{value: 2 * DEFAULT_MIN_BID}(auctionId);

        (,,,, uint256 deadlineAfterSecond,) = auction.getAuctionInfo(auctionId);
        assertEq(deadlineAfterSecond, deadlineAfterFirst + EXTENSION_TIME);
    }

    //==      Admin Tests      ==//
    
    function test_StopAuction() public {
        vm.prank(multisig);
        auction.stopAuction();
        assertFalse(auction.isAuctionActive());
    }

    function test_StopAuction_RevertWhenAlreadyStopped() public {
        vm.startPrank(multisig);
        auction.stopAuction();
        vm.expectRevert(Auction.AuctionIsStoppedAlready.selector);
        auction.stopAuction();
        vm.stopPrank();
    }

    function test_StopAuction_RevertWhenNotMultisig() public {
        vm.expectRevert(Auction.NotAMultisigTimelock.selector);
        vm.prank(USER2);
        auction.stopAuction();
    }

    function test_ActivateAuction() public {
        vm.startPrank(multisig);
        auction.stopAuction();
        auction.activateAuction();
        assertTrue(auction.isAuctionActive());
        vm.stopPrank();
    }

    function test_ActivateAuction_RevertWhenAlreadyActive() public {
        vm.expectRevert(Auction.AuctionIsActiveAlready.selector);
        vm.prank(multisig);
        auction.activateAuction();
    }

    function test_SetNewAuctionFeeAmount() public {
        uint256 newFee = 200;
        vm.prank(multisig);
        auction.setNewAuctionFeeAmount(newFee);

        (,,,,, uint256 feeAmount,) = auction.getAuctionSettings();
        assertEq(feeAmount, newFee);
    }

    function test_SetNewAuctionFeeAmount_RevertWhenTooHigh() public {
        vm.expectRevert(Auction.InvalidAuctionFeeAmount.selector);
        vm.prank(multisig);
        auction.setNewAuctionFeeAmount(501);
    }

    function test_SetMaxDuration() public {
        uint256 newDuration = 10 days;
        vm.prank(multisig);
        auction.setMaxDuration(newDuration);
        (, uint256 maxDuration,,,,,) = auction.getAuctionSettings();
        assertEq(maxDuration, newDuration);
    }

    function test_SetMaxDuration_RevertWhenBelowMinimum() public {
        vm.expectRevert(Auction.InvalidDuration.selector);
        vm.prank(multisig);
        auction.setMaxDuration(29 minutes);
    }

    function test_SetAuctionFeeReceiver() public {
        vm.prank(multisig);
        auction.setAuctionFeeReceiver(USER2);
        (,,,,,, address receiver) = auction.getAuctionSettings();
        assertEq(receiver, USER2);
    }

    function test_SetAuctionFeeReceiver_RevertWhenZeroAddress() public {
        vm.expectRevert(Auction.ZeroAddress.selector);
        vm.prank(multisig);
        auction.setAuctionFeeReceiver(address(0));
    }

    function test_SetMultisigTimelock() public {
        address newMultisig = address(0xABC);
        vm.prank(multisig);
        auction.setMultisigTimelock(newMultisig);

        vm.expectRevert(Auction.NotAMultisigTimelock.selector);
        vm.prank(multisig);
        auction.stopAuction();
    }

    function test_SetFactoryAddress() public {
        address newFactory = address(0x123);
        vm.prank(multisig);
        auction.setFactoryAddress(newFactory);
        assertEq(auction.getFactoryAddress(), newFactory);
    }

    function test_SetFactoryAddress_RevertWhenZeroAddress() public {
        vm.expectRevert(Auction.ZeroAddress.selector);
        vm.prank(multisig);
        auction.setFactoryAddress(address(0));
    }

    function test_SetMinimumNextBidPercent() public {
        vm.prank(multisig);
        auction.setMinimumNextBidPercent(10);
        (,,,, uint256 minPercent,,) = auction.getAuctionSettings();
        assertEq(minPercent, 10);
    }

    function test_SetMinimumNextBidPercent_RevertWhenTooLow() public {
        vm.expectRevert(Auction.InvalidNextBidPercent.selector);
        vm.prank(multisig);
        auction.setMinimumNextBidPercent(4);
    }

    function test_SetMinimumNextBidPercent_RevertWhenTooHigh() public {
        vm.expectRevert(Auction.InvalidNextBidPercent.selector);
        vm.prank(multisig);
        auction.setMinimumNextBidPercent(60);
    }
}

