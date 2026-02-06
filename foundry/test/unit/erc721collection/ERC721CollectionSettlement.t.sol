// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../../Base.t.sol";
import {ERC721Collection} from "../../../src/ERC721Collection.sol";
import {ERC721CollectionHelper} from "../../helpers/ERC721CollectionHelper.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC721CollectionSettlementTest is ERC721CollectionHelper {
    allDeployments public allContracts;

    ERC721Collection public erc721Collection;
    address public multisig;

    function setUp() public override {
        super.setUp();

        allContracts = deployAndSetAllContracts();
        multisig = address(allContracts.mockMultisig);
        erc721Collection = initializeDefaultCollection();
    }

    function test_Initialize() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        assertEq(config.name, "Test Collection");
        assertEq(config.symbol, "TEST");
        assertEq(config.revealType, "instant");
        assertEq(config.baseURI, "https://example.com/");
        assertEq(config.placeholderURI, "https://example.com/placeholder");
        assertEq(config.royaltyReceiver, COLLECTION_AUTHOR);
        assertEq(config.royaltyFeeNumerator, DEFAULT_ROYALTY_FEE);
        assertEq(config.maxSupply, DEFAULT_MAX_SUPPLY);
        assertEq(config.mintPrice, DEFAULT_MINT_PRICE);
        assertEq(config.batchMintSupply, DEFAULT_BATCH_MINT_SUPPLY);
        // VRF adapter is set to the mock adapter used during initialization
        assertEq(config.vrfAdapter, erc721Collection.getVRFAdapter());
    }
    
    function test_RevertWhen_Initialize() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        config.batchMintSupply = config.maxSupply + 1;
        
        ERC721Collection impl = deployERC721CollectionImpl();

        bytes memory initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            config
        );

        vm.expectRevert(ERC721Collection.IncorrectBatchMintSupply.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            initData
        );


        ERC721Collection.InitConfig memory config2 = erc721Collection.getCollectionSettings();
        config2.vrfAdapter = address(0);

        initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            config2
        );

        vm.expectRevert(ERC721Collection.ZeroAddress.selector);
        proxy = new ERC1967Proxy(
            address(impl),
            initData
        );
    }

    function test_Mint() public {
        uint256 tokenId = mintToken(erc721Collection, USER1);

        assertEq(erc721Collection.ownerOf(tokenId), USER1);
        assertEq(erc721Collection.isRevealed(tokenId), true);
    }

    function test_RevertWhen_Mint() public {
        vm.prank(USER1);
        vm.expectRevert(ERC721Collection.InsufficientBalance.selector);
        erc721Collection.mint{value: 0}();

        ERC721Collection.InitConfig memory config;
        config.name = "MaxSupplyOne";
        config.symbol = "MS1";
        config.revealType = "instant";
        config.baseURI = "https://example.com/";
        config.placeholderURI = "https://example.com/placeholder";
        config.royaltyReceiver = COLLECTION_AUTHOR;
        config.royaltyFeeNumerator = DEFAULT_ROYALTY_FEE;
        config.maxSupply = 1;
        config.mintPrice = DEFAULT_MINT_PRICE;
        config.batchMintSupply = 0;
        config.vrfAdapter = address(allContracts.vrfAdapter);

        ERC721Collection limited = initializeCollectionWithParams(config);

        vm.deal(USER1, 100 ether);
        vm.startPrank(USER1);
        limited.mint{value: limited.getMintPrice()}();
        vm.stopPrank();

        vm.deal(USER1, 100 ether);
        vm.expectRevert(ERC721Collection.MaxSupplyReached.selector);
        limited.mint();
    }

    function test_SetBaseURI() public {
        string memory newBase = "https://new.example.com/";
        erc721Collection.setBaseURI(newBase);

        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        assertEq(config.baseURI, newBase);
    }

    function test_RevertWhen_SetBaseURI() public {
        string memory newBase = "https://new.example.com/";
        vm.prank(USER1);
        vm.expectRevert(); // onlyOwner from OwnableUpgradeable
        erc721Collection.setBaseURI(newBase);
    }

    function test_SetNewDefaultRoyaltyInfo() public {
        address newReceiver = USER2;
        uint96 newFee = 700;

        erc721Collection.setDefaultRoyaltyInfo(newReceiver, newFee);

        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        assertEq(config.royaltyReceiver, newReceiver);
        assertEq(config.royaltyFeeNumerator, newFee);
    }

    function test_RevertWhen_SetNewDefaultRoyaltyInfo() public {
        vm.expectRevert(ERC721Collection.ZeroAddress.selector);
        erc721Collection.setDefaultRoyaltyInfo(address(0), DEFAULT_ROYALTY_FEE);
    }

    function test_SetPaymentReceiver() public {
        address newReceiver = USER2;
        erc721Collection.setPaymentReceiver(newReceiver);

        // Mint and check that funds are sent to the new receiver
        uint256 balanceBefore = newReceiver.balance;
        mintToken(erc721Collection, USER1);
        uint256 balanceAfter = newReceiver.balance;

        assertGt(balanceAfter, balanceBefore);
    }

    function test_RevertWhen_SetPaymentReceiver() public {
        vm.expectRevert(ERC721Collection.ZeroAddress.selector);
        erc721Collection.setPaymentReceiver(address(0));
    }

    function test_DelayedReveal() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        config.revealType = "delayed";

        erc721Collection = initializeCollectionWithParams(config);
        uint256 tokenId = mintToken(erc721Collection, USER1);

        vm.prank(USER1);
        erc721Collection.delayedReveal(tokenId);

        assertEq(erc721Collection.isVrfPendingReveal(tokenId), true);
        assertEq(erc721Collection.isRevealed(tokenId), false);

        uint256 randomNumber = 999;

        vm.prank(erc721Collection.getVRFAdapter());
        erc721Collection.revealWithRandomNumber(tokenId, randomNumber);

        assertEq(erc721Collection.isVrfPendingReveal(tokenId), false);
        assertEq(erc721Collection.isRevealed(tokenId), true);
    }

    function test_RevertWhen_DelayedReveal() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        config.revealType = "delayed";

        erc721Collection = initializeCollectionWithParams(config);
        uint256 tokenId = mintToken(erc721Collection, USER1);

        vm.prank(USER2);
        vm.expectRevert(ERC721Collection.NotAnOwner.selector);
        erc721Collection.delayedReveal(tokenId);

        ERC721Collection.InitConfig memory config2 = erc721Collection.getCollectionSettings();
        config2.revealType = "instant";
        ERC721Collection instantCollection = initializeCollectionWithParams(config2);
        uint256 instantTokenId = mintToken(instantCollection, USER1);

        vm.expectRevert(ERC721Collection.TokenIsRevealedAlready.selector);
        vm.prank(USER1);
        instantCollection.delayedReveal(instantTokenId);

        ERC721Collection.InitConfig memory config3 = erc721Collection.getCollectionSettings();
        config3.revealType = "delayed";
        ERC721Collection delayedCollection = initializeCollectionWithParams(config3);
        uint256 delayedTokenId = mintToken(delayedCollection, USER1);

        vm.prank(USER1);
        delayedCollection.delayedReveal(delayedTokenId);

        vm.prank(USER1);
        vm.expectRevert(ERC721Collection.TokenAlreadyPendingReveal.selector);
        delayedCollection.delayedReveal(delayedTokenId);
    }

    function test_RevealWithRandomNumber() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        config.revealType = "delayed";

        erc721Collection = initializeCollectionWithParams(config);
        uint256 tokenId = mintToken(erc721Collection, USER1);

        vm.prank(USER1);
        erc721Collection.delayedReveal(tokenId);

        uint256 randomNumber = 42;
        vm.prank(erc721Collection.getVRFAdapter());
        erc721Collection.revealWithRandomNumber(tokenId, randomNumber);

        assertTrue(erc721Collection.isRevealed(tokenId));
        assertGt(erc721Collection.getRevealedTraitIndex(tokenId), 0);
    }

    function test_RevertWhen_RevealWithRandomNumber() public {
        ERC721Collection.InitConfig memory config = erc721Collection.getCollectionSettings();
        config.revealType = "delayed";

        erc721Collection = initializeCollectionWithParams(config);
        uint256 tokenId = mintToken(erc721Collection, USER1);

        vm.prank(USER1);
        vm.expectRevert(ERC721Collection.OnlyVRFAdapter.selector);
        erc721Collection.revealWithRandomNumber(tokenId, 999);

        vm.prank(erc721Collection.getVRFAdapter());
        vm.expectRevert(ERC721Collection.InvalidVRFRequest.selector);
        erc721Collection.revealWithRandomNumber(tokenId, 999);

        vm.prank(USER1);
        erc721Collection.delayedReveal(tokenId);

        uint256 randomNumber = 42;
        vm.prank(erc721Collection.getVRFAdapter());
        erc721Collection.revealWithRandomNumber(tokenId, randomNumber);

        vm.prank(erc721Collection.getVRFAdapter());
        vm.expectRevert(ERC721Collection.TokenIsRevealedAlready.selector);
        erc721Collection.revealWithRandomNumber(tokenId, randomNumber);
    }

    function test_SetMintPrice() public {
        uint256 newPrice = 0.02 ether;
        erc721Collection.setMintPrice(newPrice);

        assertEq(erc721Collection.getMintPrice(), newPrice);
    }

    function test_RevertWhen_SetMintPrice() public {
        uint256 newPrice = 0.02 ether;
        vm.prank(USER1);
        vm.expectRevert(); // onlyOwner from OwnableUpgradeable
        erc721Collection.setMintPrice(newPrice);
    }

    function test_Withdraw() public {
        // Send some ETH to the contract
        vm.deal(address(erc721Collection), 1 ether);

        address paymentReceiver = erc721Collection.getDefaultRoyaltyReceiver();
        uint256 balanceBefore = paymentReceiver.balance;

        erc721Collection.withdraw();

        uint256 balanceAfter = paymentReceiver.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
    }

    function test_RevertWhen_Withdraw() public {
        // No balance to withdraw
        vm.expectRevert(ERC721Collection.InsufficientBalance.selector);
        erc721Collection.withdraw();

        // Not owner
        vm.deal(address(erc721Collection), 1 ether);
        vm.prank(USER1);
        vm.expectRevert(); // onlyOwner from OwnableUpgradeable
        erc721Collection.withdraw();
    } 
}