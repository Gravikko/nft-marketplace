// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFactory
/// @notice Interface for the Factory contract
interface IFactory {
    function getCollectionOwnerById(uint256 collectionId) external view returns (address);
    function getCollectionIdByAddress(address collectionAddress) external view returns (uint256);
    function getCollectionAddressById(uint256 collectionId) external view returns (address);
    function getAllAddressCollectionIds(address userAddress) external view returns (uint256[] memory);
    function getAddressCollectionAmount(address userAddress) external view returns (uint256);
    function isFactoryActive() external view returns (bool);
    function getBeaconAddress() external view returns (address);
}
