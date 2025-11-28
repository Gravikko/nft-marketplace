// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {Factory} from "../../src/Factory.sol";
import {Auction} from "../../src/Auction.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";

abstract contract AuctionTestBase is DeployHelpers {
    allDeployments internal deployments;

    MarketplaceNFT internal marketplace;
    Factory internal factory;
    Auction internal auction;
    ERC721Collection internal collection;
    address internal multisig;

    uint256 internal collectionId;

    modifier onlyAuction() {
        require(address(auction) != address(0), "Auction not set");
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        deployments = deployAndSetAllContracts();
        marketplace = deployments.marketplace;
        factory = deployments.factory;
        auction = deployments.auction;
        multisig = address(deployments.mockMultisig);
        address collectionAddress;

        (collectionId, collectionAddress) = helper_CreateCollection(USER1, factory);
        collection = ERC721Collection(collectionAddress);
    }

    function _mintToken(address owner) internal returns (uint256 tokenId) {
        vm.startPrank(owner);
        collection.mint{value: DEFAULT_MINT_PRICE}();
        vm.stopPrank();
        tokenId = collection.getSupply();
    }

    function _ensureApproval(address owner) internal {
        vm.prank(owner);
        collection.setApprovalForAll(address(auction), true);
    }

    function _createAuction(
        address owner,
        uint256 duration,
        uint256 minimumBid
    ) internal returns (uint256 auctionId, uint256 tokenId) {
        tokenId = _mintToken(owner);
        _ensureApproval(owner);

        vm.prank(owner);
        auction.putTokenOnAuction(collectionId, tokenId, duration, minimumBid);

        auctionId = auction.getAuctionCount();
    }

    function _bid(
        address bidder,
        uint256 auctionId,
        uint256 amount,
        uint256 balance
    ) internal {
        vm.deal(bidder, balance);
        vm.prank(bidder);
        auction.makeABid{value: amount}(auctionId);
    }

    function _fastForward(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }
}

