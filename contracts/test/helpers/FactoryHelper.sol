// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../Base.t.sol";
import {Factory} from "../../src/Factory.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";

/// @title Factory Helper Contract
/// @notice Helper functions and utilities for Factory-related tests
contract FactoryHelper is DeployHelpers {
    /// @notice Creates a collection with default parameters
    /// @param factory The factory contract
    /// @param creator The address creating the collection
    /// @return collectionId The created collection ID
    /// @return collectionAddress The created collection address
    function createCollection(
        Factory factory,
        address creator
    ) public returns (uint256 collectionId, address collectionAddress) {
        CollectionResult memory result = createCollectionWithDefaults(
            factory,
            creator,
            DEFAULT_MAX_SUPPLY,
            DEFAULT_MINT_PRICE,
            DEFAULT_ROYALTY_FEE,
            DEFAULT_BATCH_MINT_SUPPLY
        );

        return (result.collectionId, result.collectionAddress);
    }

    /// @notice Creates a collection with custom parameters
    /// @param factory The factory contract
    /// @param creator The address creating the collection
    /// @param params The collection parameters
    /// @return collectionId The created collection ID
    /// @return collectionAddress The created collection address
    function createCollectionWithParams(
        Factory factory,
        address creator,
        Factory.CreateCollectionParams memory params
    ) public returns (uint256 collectionId, address collectionAddress) {
        vm.prank(creator);
        (collectionId, collectionAddress) = factory.createCollection(params);
    }

    /// @notice Gets default collection parameters for testing
    /// @param royaltyReceiver The royalty receiver address
    /// @return params The default collection parameters
    function getDefaultCollectionParams(
        address royaltyReceiver
    ) public pure returns (Factory.CreateCollectionParams memory params) {
        return Factory.CreateCollectionParams({
            name: "Test Collection",
            symbol: "TEST",
            revealType: "instant",
            baseURI: "baseURI",
            placeholderURI: "placeholderURI",
            royaltyReceiver: royaltyReceiver,
            royaltyFeeNumerator: DEFAULT_ROYALTY_FEE,
            maxSupply: DEFAULT_MAX_SUPPLY,
            mintPrice: DEFAULT_MINT_PRICE,
            batchMintSupply: DEFAULT_BATCH_MINT_SUPPLY
        });
    }

    /// @notice Gets default collection parameters for testing with custom reveal type
    /// @param royaltyReceiver The royalty receiver address
    /// @param revealType The reveal type ("instant" or "delayed")
    /// @return params The default collection parameters
    function getDefaultCollectionParamsWithRevealType(
        address royaltyReceiver,
        string memory revealType
    ) public pure returns (Factory.CreateCollectionParams memory params) {
        return Factory.CreateCollectionParams({
            name: "Test",
            symbol: "TEST",
            revealType: revealType,
            baseURI: "baseURI",
            placeholderURI: "placeholderURI",
            royaltyReceiver: royaltyReceiver,
            royaltyFeeNumerator: DEFAULT_ROYALTY_FEE,
            maxSupply: DEFAULT_MAX_SUPPLY,
            mintPrice: DEFAULT_MINT_PRICE,
            batchMintSupply: DEFAULT_BATCH_MINT_SUPPLY
        });
    }

    /// @notice Creates collection parameters for revert tests
    /// @param royaltyReceiver The royalty receiver address
    /// @return params The collection parameters
    function getCollectionParamsForRevert(
        address royaltyReceiver
    ) public pure returns (Factory.CreateCollectionParams memory params) {
        return Factory.CreateCollectionParams({
            name: "Test",
            symbol: "TEST",
            revealType: "instant",
            baseURI: "baseURI",
            placeholderURI: "placeholderURI",
            royaltyReceiver: royaltyReceiver,
            royaltyFeeNumerator: DEFAULT_ROYALTY_FEE,
            maxSupply: DEFAULT_MAX_SUPPLY,
            mintPrice: DEFAULT_MINT_PRICE,
            batchMintSupply: DEFAULT_BATCH_MINT_SUPPLY
        });
    }

    /// @notice Creates a factory setup with all required dependencies
    /// @param multisig The multisig address
    /// @param marketplace The marketplace address
    /// @param vrfAdapter The VRF adapter address
    /// @param beacon The beacon address
    /// @return factory The configured factory contract
    function setupFactoryWithDependencies(
        address multisig,
        address marketplace,
        address vrfAdapter,
        address beacon
    ) public returns (Factory factory) {
        factory = deployFactory(multisig);
        setupFactory(factory, multisig, marketplace, vrfAdapter, beacon);
    }
}

