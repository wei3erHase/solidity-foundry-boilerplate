// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract MockHAI is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser("Mock HAI", "mHAI") {
        _mint(msg.sender, 1_000_000_000 * 10**18); // Mint a lot to deployer
    }
}
