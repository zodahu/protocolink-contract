// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISpenderAaveV2Delegation {
    error RouterInvalidUser();

    function borrow(address asset, uint256 amount, uint256 interestRateMode) external;
}