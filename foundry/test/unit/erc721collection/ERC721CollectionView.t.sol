// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../../Base.t.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";
import {ERC721CollectionHelper} from "../../helpers/ERC721CollectionHelper.sol";

contract ERC721CollectionViewTest is ERC721CollectionHelper {
    allDeployments public allContracts;

    ERC721Collection public erc721Collection;
    address public multisig;

    function setUp() public override {
        super.setUp();

        allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);

        // Create a default collection via the factory so all dependencies are wired
        (uint256 collectionId, address collectionAddress) =
            helper_CreateCollection(COLLECTION_AUTHOR, allContracts.factory);

        erc721Collection = ERC721Collection(collectionAddress);
    }


    // View functions (some can revert, some are pure queries)
    function test_GetRevealedCount() public {
        // Initially no revealed tokens
        assertEq(erc721Collection.getRevealedCount(), 0);

        // Mint a token with instant reveal
        uint256 tokenId = mintToken(erc721Collection, USER1);
        assertEq(erc721Collection.isRevealed(tokenId), true);

        assertEq(erc721Collection.getRevealedCount(), 1);
    }

    function test_GetVRFAdapter() public {
        assertEq(erc721Collection.getVRFAdapter(), address(allContracts.vrfAdapter));
    }

    function test_GetDefaultRoyaltyReceiver() public {
        address receiver = erc721Collection.getDefaultRoyaltyReceiver();
        assertEq(receiver, COLLECTION_AUTHOR);
    }

    function test_GetRevealedTraitIndex() public {
        // Unrevealed token (from initial batch mint)
        uint256 unrevealedTokenId = 1;
        assertEq(erc721Collection.getRevealedTraitIndex(unrevealedTokenId), 0);

        // Revealed token after mint
        uint256 revealedTokenId = mintToken(erc721Collection, USER1);
        assertTrue(erc721Collection.isRevealed(revealedTokenId));
        assertGt(erc721Collection.getRevealedTraitIndex(revealedTokenId), 0);
    }

    function test_GetSupply() public {
        // Initial supply equals batchMintSupply
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        assertEq(erc721Collection.getSupply(), config.batchMintSupply);

        // After minting one more token
        mintToken(erc721Collection, USER1);
        assertEq(erc721Collection.getSupply(), config.batchMintSupply + 1);
    }

    function test_RemainingSupply() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        uint256 initialRemaining = erc721Collection.remainingSupply();
        assertEq(initialRemaining, config.maxSupply - config.batchMintSupply);

        mintToken(erc721Collection, USER1);
        uint256 remainingAfter = erc721Collection.remainingSupply();
        assertEq(remainingAfter, initialRemaining - 1);
    }

    function test_IsRevealed() public {
        uint256 tokenId = mintToken(erc721Collection, USER1);
        assertTrue(erc721Collection.isRevealed(tokenId));
    }

    function test_RevertWhen_IsRevealed() public {
        uint256 invalidTokenId = erc721Collection.getNextTokenId() + 1;
        vm.expectRevert(ERC721Collection.TokenIsNotMinted.selector);
        erc721Collection.isRevealed(invalidTokenId);
    }

    function test_GetNextTokenId() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        uint256 nextId = erc721Collection.getNextTokenId();
        assertEq(nextId, config.batchMintSupply + 1);
    }

    function test_RevertWhen_GetNextTokenId() public {
        // Create a collection where all supply is already minted in the initializer
        ERC721Collection.InitConfig memory cfg;
        cfg.name = "Full";
        cfg.symbol = "FULL";
        cfg.revealType = "instant";
        cfg.baseURI = "baseURI";
        cfg.placeholderURI = "placeholderURI";
        cfg.royaltyReceiver = COLLECTION_AUTHOR;
        cfg.royaltyFeeNumerator = DEFAULT_ROYALTY_FEE;
        cfg.maxSupply = 1;
        cfg.mintPrice = DEFAULT_MINT_PRICE;
        cfg.batchMintSupply = 1;
        cfg.vrfAdapter = address(allContracts.vrfAdapter);

        ERC721Collection full = initializeCollectionWithParams(cfg);

        vm.expectRevert(ERC721Collection.MaxSupplyReached.selector);
        full.getNextTokenId();
    }

    function test_IsTokenApproved() public {
        uint256 tokenId = mintToken(erc721Collection, USER1);

        // Initially not approved
        assertFalse(erc721Collection.isTokenApproved(tokenId, MARKETPLACE));

        // Approve marketplace
        vm.prank(USER1);
        erc721Collection.approve(MARKETPLACE, tokenId);

        assertTrue(erc721Collection.isTokenApproved(tokenId, MARKETPLACE));
    }

    function test_SupportsInterface() public {
        // ERC721 interfaceId
        assertTrue(erc721Collection.supportsInterface(0x80ac58cd));

        // ERC2981 interfaceId
        assertTrue(erc721Collection.supportsInterface(0x2a55205a));
    }

    function test_TokenURI() public {
        // Unrevealed token uses placeholder URI
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        string memory uri = erc721Collection.tokenURI(1);
        assertEq(uri, config.placeholderURI);

        // Revealed token uses base URI + trait index (non-empty and not placeholder)
        uint256 tokenId = mintToken(erc721Collection, USER1);
        string memory revealedURI = erc721Collection.tokenURI(tokenId);
        assertTrue(bytes(revealedURI).length > 0);
        assertTrue(keccak256(bytes(revealedURI)) != keccak256(bytes(config.placeholderURI)));
    }

    function test_RevertWhen_TokenURI() public {
        uint256 invalidTokenId = erc721Collection.getNextTokenId() + 1;
        vm.expectRevert(); // ERC721NonexistentToken
        erc721Collection.tokenURI(invalidTokenId);
    }

    function test_GetRoyaltyByTokenId() public {
        uint256 salePrice = 1 ether;
        (uint256 royaltyAmount, address receiver) = erc721Collection.getRoyaltyByTokenId(1, salePrice);

        assertEq(receiver, COLLECTION_AUTHOR);
        assertEq(royaltyAmount, (salePrice * DEFAULT_ROYALTY_FEE) / 10000);
    }

    function test_NextUnrevealedIndex() public {
        // With no reveals, nextUnrevealedIndex should return the start index if within range
        uint256 index = erc721Collection.nextUnrevealedIndex(1);
        assertEq(index, 1);

        // After revealing a token, it should return a different index
        uint256 tokenId = mintToken(erc721Collection, USER1);
        uint256 nextIndex = erc721Collection.nextUnrevealedIndex(tokenId);
        assertNotEq(nextIndex, tokenId);
    }

    function test_RevertWhen_NextUnrevealedIndex() public {
        // Create a tiny collection where all tokens are revealed
        ERC721Collection.InitConfig memory cfg;
        cfg.name = "Tiny";
        cfg.symbol = "TNY";
        cfg.revealType = "instant";
        cfg.baseURI = "baseURI";
        cfg.placeholderURI = "placeholderURI";
        cfg.royaltyReceiver = COLLECTION_AUTHOR;
        cfg.royaltyFeeNumerator = DEFAULT_ROYALTY_FEE;
        cfg.maxSupply = 1;
        cfg.mintPrice = DEFAULT_MINT_PRICE;
        cfg.batchMintSupply = 0;
        cfg.vrfAdapter = address(allContracts.vrfAdapter);

        ERC721Collection tiny = initializeCollectionWithParams(cfg);

        // Mint will instantly reveal the only token
        mintToken(tiny, USER1);

        vm.expectRevert(ERC721Collection.NoUnrevealedIndexes.selector);
        tiny.nextUnrevealedIndex(1);
    }
}