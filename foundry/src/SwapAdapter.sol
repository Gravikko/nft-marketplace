// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/// @title SwapAdapter
/// @notice ETH/WETH swap utility contract
contract SwapAdapter {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    using SafeERC20 for IERC20;

    address public immutable WETH;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TransferFailed();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates the swap adapter
    /// @param weth The WETH contract address
    constructor(address weth) {
        if (weth == address(0)) revert ZeroAddress();
        WETH = weth;
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unwraps WETH to ETH and sends to recipient
    /// @param amount The amount to unwrap
    /// @param recipient The recipient address
    function unwrapWETH(uint256 amount, address payable recipient) external {
        if (recipient == address(0)) revert ZeroAddress();
        IWETH(WETH).withdraw(amount);
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Wraps ETH to WETH and sends to recipient
    /// @param recipient The recipient address
    function wrapETH(address recipient) external payable {
        if (recipient == address(0)) revert ZeroAddress();
        IWETH(WETH).deposit{value: msg.value}();
        IERC20(WETH).safeTransfer(recipient, msg.value);
    }
}
