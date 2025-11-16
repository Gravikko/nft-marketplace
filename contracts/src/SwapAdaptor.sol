// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns(bool);
    function balanceOf(address) external view returns(uint256);
}

contract SwapAdaptor {
    address public immutable WETH;

    error ZeroAddress();
    error TransferFailed();

    constructor(address weth) {
        if (weth == address(0)) revert ZeroAddress();
        WETH = weth;
    }

    receive() external payable {}

    function unwrapWETH(uint256 amount, address payable recipient) external {
        if (recipient == address(0)) revert ZeroAddress();
        IWETH(WETH).withdraw(amount);
        (bool ok, ) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function wrapETH(address recipient) external payable {
        if (recipient == address(0)) revert ZeroAddress();
        IWETH(WETH).deposit{value: msg.value}();
        if (!IWETH(WETH).transfer(recipient, msg.value)) revert TransferFailed();
    } 
}