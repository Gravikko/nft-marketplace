// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

contract BaseTest is Test {
    address public constant MULTISIG  = address(0x1);
    address public constant USER1 = address(0x1001);
    address public constant USER2 = address(0x1002);
    address public constant USER3 = address(0x1003);
    address public constant USER4 = address(0x1004);
    address public constant COLLECTION_AUTHOR = address(0x1005);
    address public constant ORDER_EXECUTER = address(0x1006);
    address public constant MARKETPLACE = address(0x2001);
    address public constant VRF_ADAPTER = address(0x3001);
    address public constant BEACON = address(0x4001); 

    uint256 public constant DEFAULT_MAX_SUPPLY = 1000;
    uint256 public constant DEFAULT_BALANCE = 100 ether;
    uint256 public constant DEFAULT_MINT_PRICE = 0.01 ether;
    uint256 public constant DEFAULT_SALE_TOKEN_PRICE = 0.01 ether;
    uint256 public constant DEFAULT_BATCH_MINT_SUPPLY = 10;
    uint256 public constant DEFAULT_MARKETPLACE_FEE_AMOUNT = 100;
    uint256 public DEFAULT_DEADLINE = block.timestamp + 10000;
    uint256 public constant DEFAULT_NONCE = 100;
    uint256 public constant DEFAULT_AUCTION_FEE = 100;
    uint256 public constant DEFAULT_REWARD_AMOUNT = 1;
    uint96 public constant DEFAULT_ROYALTY_FEE = 500;
    uint256 public constant DEFAULT_SELLER_PRIVATE_KEY = 0x2;




    function setUp() public virtual {
        vm.label(USER1, "user1");
        vm.label(USER2, "user2");
        vm.label(USER3, "user3");
        vm.label(USER4, "user4");
        vm.label(COLLECTION_AUTHOR, "collection_author");
        vm.label(MARKETPLACE, "Marketplace");
        vm.label(VRF_ADAPTER, "VRFAdapter");
        vm.label(BEACON, "Beacon");
        vm.label(ORDER_EXECUTER, "order_executer");

        vm.deal(USER1, DEFAULT_BALANCE);
        vm.deal(USER2, DEFAULT_BALANCE);
        vm.deal(USER3, DEFAULT_BALANCE);
        vm.deal(USER4, DEFAULT_BALANCE);
        vm.deal(COLLECTION_AUTHOR, DEFAULT_BALANCE);
        vm.deal(ORDER_EXECUTER, DEFAULT_BALANCE);
    }   

    function getCollectionName(uint256 id) internal pure returns(string memory) {
        return string(abi.encodePacked("Test colleciton name: ", vm.toString(id)));
    }

    function getCollectionSymbol(uint256 id) internal pure returns(string memory) {
        return string(abi.encodePacked("Test collection symbol: ", vm.toString(id)));
    }


}