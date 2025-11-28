// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {ERC721Collection} from "../../src/ERC721Collection.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockVRFAdapter} from "./Mocks.sol";

contract ERC721CollectionHelper is DeployHelpers {

    function initializeCollectionWithParams(ERC721Collection.InitConfig memory initConfig)
        public
        returns (ERC721Collection)
    {
        ERC721Collection impl = deployERC721CollectionImpl();

        bytes memory initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            initConfig
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            initData
        );

        return ERC721Collection(payable(address(proxy)));
    }

    function initializeDefaultCollection() public returns(ERC721Collection) {

        ERC721Collection impl = deployERC721CollectionImpl();
        
        MockVRFAdapter vrfAdapter = new MockVRFAdapter();

        ERC721Collection.InitConfig memory initConfig = ERC721Collection.InitConfig({
            name: "Test Collection",
            symbol: "TEST",
            revealType: "instant",
            baseURI: "https://example.com/",
            placeholderURI: "https://example.com/placeholder",
            royaltyReceiver: COLLECTION_AUTHOR,
            royaltyFeeNumerator: DEFAULT_ROYALTY_FEE,
            maxSupply: DEFAULT_MAX_SUPPLY,
            mintPrice: DEFAULT_MINT_PRICE,
            batchMintSupply: DEFAULT_BATCH_MINT_SUPPLY,
            vrfAdapter: address(vrfAdapter)
        });
        
        bytes memory initData = abi.encodeWithSelector(
            ERC721Collection.initialize.selector,
            initConfig
        );
        
        // Create proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            initData
        );
        
        return ERC721Collection(payable(address(proxy)));
    }

    function mintToken(ERC721Collection erc721Collection, address buyer) public returns (uint256 tokenId) {
        tokenId = erc721Collection.getNextTokenId();
        vm.deal(buyer, 100 ether);
        vm.startPrank(buyer);
        erc721Collection.mint{value: erc721Collection.getMintPrice()}();
        vm.stopPrank();
    }
}