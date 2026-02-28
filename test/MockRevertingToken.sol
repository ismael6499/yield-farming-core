// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/MockToken.sol";

contract MockRevertingToken is MockToken {
    constructor() MockToken("Reverting", "REV", 1000000 ether) {}
    
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false; // SafeERC20 should revert
    }
    
    function transfer(address, uint256) public pure override returns (bool) {
         return false; // SafeERC20 should revert
    }
}
