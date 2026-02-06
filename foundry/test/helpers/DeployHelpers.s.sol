// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {Factory} from "../../src/Factory.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockMultisigTimelock, MockVRFAdapter} from "../helpers/Mocks.sol";
import {ERC721CollectionBeacon} from "../../src/ERC721CollectionBeacon.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {MarketplaceNFT} from "../../src/Marketplace.sol";
import {Auction} from "../../src/Auction.sol";
import {StakingNFT} from "../../src/Staking.sol";
import {MockWETH} from "../unit/SwapAdapter.t.sol";

contract DeployHelpers is BaseTest { 

    struct allDeployments {
        Auction auction;
        ERC721Collection erc721Collection;
        ERC721CollectionBeacon beacon;
        MockMultisigTimelock mockMultisig;
        MarketplaceNFT marketplace;
        Factory factory;
        StakingNFT stakingNFT;
        MockVRFAdapter vrfAdapter;
        MockWETH weth;  // WETH address for Marketplace
    }

    struct CollectionParams {
        string name;
        string symbol;
        string revealType;
        string baseURI;
        string placeholderURI;
        address royaltyReceiver;
        uint96 royaltyFeeNumerator;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 batchMintSupply;
    }

    struct CollectionResult {
        uint256 collectionId;
        address collectionAddress;
    }

    function helper_CreateCollection(address creator, Factory factory) internal returns(uint256 collectionId, address collectionAddress) {
        CollectionResult memory result = createCollectionWithDefaults(factory, creator, DEFAULT_MAX_SUPPLY, DEFAULT_MINT_PRICE, DEFAULT_ROYALTY_FEE, DEFAULT_BATCH_MINT_SUPPLY);
        collectionId = result.collectionId;
        collectionAddress = result.collectionAddress;
    }

    function createCollectionWithDefaults(
        Factory factory,
        address creator,
        uint256 defaultMaxSupply,
        uint256 defaultMintPrice,
        uint96 defaultRoyaltyFee,
        uint256 defaultBatchMintSupply
    ) public returns (CollectionResult memory) {
        return createCollection(
            factory,
            creator,
            CollectionParams({
                name: "Test Collection",
                symbol: "TEST",
                revealType: "instant",
                baseURI: "https://example.com/",
                placeholderURI: "https://example.com/placeholder",
                royaltyReceiver: creator,
                royaltyFeeNumerator: defaultRoyaltyFee,
                maxSupply: defaultMaxSupply,
                mintPrice: defaultMintPrice,
                batchMintSupply: defaultBatchMintSupply
            })
        );
    }

    function createCollection(
        Factory factory,
        address creator,
        CollectionParams memory params
    ) public returns (CollectionResult memory result) {
        vm.prank(creator);
        (result.collectionId, result.collectionAddress) = factory.createCollection(
            Factory.CreateCollectionParams({
                name: params.name,
                symbol: params.symbol,
                revealType: params.revealType,
                baseURI: params.baseURI,
                placeholderURI: params.placeholderURI,
                royaltyReceiver: params.royaltyReceiver,
                royaltyFeeNumerator: params.royaltyFeeNumerator,
                maxSupply: params.maxSupply,
                mintPrice: params.mintPrice,
                batchMintSupply: params.batchMintSupply
            })
        );
        
        return result;
    }

    function deployFactory(address multisigTimelock) public returns (Factory) {
        Factory factoryImpl = new Factory();

        bytes memory initData = abi.encodeWithSelector(
            Factory.initialize.selector,
            multisigTimelock
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(factoryImpl), 
            initData
        );

        return Factory(payable(address(proxy)));
    }

    function deployMarketplace(address multisigTimelock, address weth) public returns(MarketplaceNFT) {
        MarketplaceNFT marketplaceImpl = new MarketplaceNFT();

        bytes memory initData = abi.encodeWithSelector(
            MarketplaceNFT.initialize.selector, 
            multisigTimelock,
            weth
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(marketplaceImpl),
            initData
        );

        return MarketplaceNFT(payable(address(proxy)));
    }

    function deployAuction(address multisigTimelock) public returns(Auction) {
        Auction auctionImpl = new Auction();

        bytes memory initData = abi.encodeWithSelector(
            Auction.initialize.selector, 
            multisigTimelock
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(auctionImpl),
            initData
        );

        return Auction(payable(address(proxy)));
    }

    /**
     * @dev Deploys ERC721Collection IMPLEMENTATION (not proxy) for beacon
     */
    function deployERC721CollectionImpl() public returns(ERC721Collection) {
        return new ERC721Collection();
    }

    /**
     * @dev DEPRECATED: Use deployERC721CollectionImpl() for beacon
     * Kept for backwards compatibility if needed
     */
    function deployERC721Collection(address multisigTimelock) public returns(ERC721Collection) {
        ERC721Collection erc721Collection = new ERC721Collection();

        bytes memory initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector, 
            multisigTimelock
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(erc721Collection),
            initData
        );

        return ERC721Collection(payable(address(proxy)));
    }
    
    function deployStakingNFT(address multisigTimelock) public returns(StakingNFT) {
        StakingNFT stakingImpl = new StakingNFT();

        bytes memory initData = abi.encodeWithSelector(
            StakingNFT.initialize.selector, 
            multisigTimelock
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakingImpl),
            initData
        );

        return StakingNFT(payable(address(proxy)));
    }

    function deployERC721Beacon(address collectionImpl, address multisig) public returns(ERC721CollectionBeacon) {
        ERC721CollectionBeacon beacon = new ERC721CollectionBeacon(collectionImpl, multisig);
        return beacon;
    }

    /**
     * @dev Sets up Factory with all required addresses and activates it
     */
    function setupFactory(
        Factory factory,
        address multisig,
        address marketplace,
        address vrfAdapter,
        address beacon
    ) public {
        vm.startPrank(multisig);
        factory.setMarketplaceAddress(marketplace);
        factory.setCollectionBeaconAddress(beacon);
        factory.setVRFAdapter(vrfAdapter);
        factory.activateFactory();  // Added missing activateFactory call
        vm.stopPrank();
    }

    /**
     * @dev Deploys all contracts in correct order
     */
    function deployAllContracts() public returns(allDeployments memory) {
        MockMultisigTimelock mockMultisig = new MockMultisigTimelock();
        MockVRFAdapter mockVRFAdapter = new MockVRFAdapter();

        allDeployments memory allContracts;

        allContracts.mockMultisig = mockMultisig;
        allContracts.vrfAdapter = mockVRFAdapter;
        allContracts.weth = new MockWETH();
        allContracts.factory = deployFactory(address(mockMultisig));
        allContracts.marketplace = deployMarketplace(address(mockMultisig), address(allContracts.weth));
        allContracts.auction = deployAuction(address(mockMultisig));
        allContracts.stakingNFT = deployStakingNFT(address(mockMultisig));
        allContracts.erc721Collection = deployERC721CollectionImpl();
        allContracts.beacon = deployERC721Beacon(
            address(allContracts.erc721Collection), 
            address(mockMultisig)
        );

        return allContracts; 
    }

    /**
     * @dev Sets up Factory with all required dependencies
     */
    function _setUpFactory(allDeployments memory allContracts) internal {
        vm.startPrank(address(allContracts.mockMultisig));
        
        allContracts.factory.setMarketplaceAddress(address(allContracts.marketplace));
        allContracts.factory.setCollectionBeaconAddress(address(allContracts.beacon));
        allContracts.factory.setVRFAdapter(address(allContracts.vrfAdapter));
        allContracts.factory.activateFactory();
        
        vm.stopPrank();
    }

    function _setUpMarketplace(allDeployments memory allContracts) internal {
        vm.startPrank(address(allContracts.mockMultisig));
        allContracts.marketplace.setFactoryAddress(address(allContracts.factory));
        allContracts.marketplace.setMarketplaceFeeAmount(DEFAULT_MARKETPLACE_FEE_AMOUNT);
        allContracts.marketplace.setMarketplaceFeeReceiver(USER1);
        allContracts.marketplace.activateMarketplace();
        vm.stopPrank();
    }   

    function _setUpAuction(allDeployments memory allContracts) internal {
        vm.startPrank(address(allContracts.mockMultisig));
        allContracts.auction.setFactoryAddress(address(allContracts.factory));
        allContracts.auction.setAuctionFeeAmount(DEFAULT_AUCTION_FEE);
        allContracts.auction.setAuctionFeeReceiver(USER1);
        allContracts.auction.activateAuction();
        vm.stopPrank();
    }   

    function _setUpStaking(allDeployments memory allContracts) internal {

        vm.startPrank(address(allContracts.mockMultisig));
        
        allContracts.stakingNFT.setFactoryAddress(address(allContracts.factory));
        allContracts.stakingNFT.setRewardAmount(DEFAULT_REWARD_AMOUNT);
        allContracts.stakingNFT.activateStaking();
        vm.stopPrank();
    }   
 
    /**
     * @dev Sets up all dependencies: Factory setup + cross-contract dependencies
     */
    function setAllDependencies(allDeployments memory allContracts) public {
        _setUpFactory(allContracts);
        _setUpMarketplace(allContracts);
        _setUpAuction(allContracts);
        _setUpStaking(allContracts); 
    }

    /**
     * @dev Deploys all contracts and sets up all dependencies in one call
     */
    function deployAndSetAllContracts() public returns(allDeployments memory) {
        allDeployments memory allContracts = deployAllContracts();
        setAllDependencies(allContracts);
        return allContracts;
    }
}