// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracleRelayer {
    function redemptionPrice() external view returns (uint256);
}
