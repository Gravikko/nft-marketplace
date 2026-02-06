// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC721Collection
/// @notice Interface for the ERC721Collection contract
interface IERC721Collection {
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function mint() external payable;
    function ownerOf(uint256 tokenId) external view returns (address);
    function isTokenApproved(uint256 tokenId, address operator) external view returns (bool);
    function getRoyaltyByTokenId(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (uint256 royaltyAmount, address royaltyReceiver);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function remainingSupply() external view returns (uint256);
    function mintPrice() external view returns (uint256);
    function getSupply() external view returns (uint256);
    function revealWithRandomNumber(uint256 tokenId, uint256 randomNumber) external;
}
