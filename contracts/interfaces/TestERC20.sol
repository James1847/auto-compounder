// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface TestERC20 is IERC20 {
    function faucet(uint256 amount) external;
}