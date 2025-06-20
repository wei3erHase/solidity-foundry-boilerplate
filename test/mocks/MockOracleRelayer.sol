// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IOracleRelayer} from "../../src/IOracleRelayer.sol"; // Relative path

contract MockOracleRelayer is IOracleRelayer {
    uint256 private _redemptionPrice;
    address public owner;

    constructor(uint256 initialPrice) {
        _redemptionPrice = initialPrice;
        owner = msg.sender;
    }
    function redemptionPrice() external view override returns (uint256) {
        return _redemptionPrice;
    }
    function setRedemptionPrice(uint256 newPrice) external {
        require(msg.sender == owner, "MockOracleRelayer: Not owner");
        _redemptionPrice = newPrice;
    }
}
