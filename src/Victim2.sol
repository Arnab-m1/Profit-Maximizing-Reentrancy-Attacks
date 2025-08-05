// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Victim2 {
    mapping(address => uint256) public balances;

    receive() external payable {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");

        // This check prevents underflow when the recursive calls unwind.
        if (balances[msg.sender] >= amount) {
            balances[msg.sender] -= amount;
        }
    }

    // --- Math helpers ---
    function pow(uint256 baseE18, uint256 exp) public pure returns (uint256 result) {
        result = 1e18;
        for (uint256 i = 0; i < exp; i++) {
            result = (result * baseE18) / 1e18;
        }
    }

    function logBase(uint256 baseE18, uint256 valE18) public pure returns (int256) {
        if (valE18 >= 1e18 || baseE18 >= 1e18) return -1;
        int256 count = 0;
        uint256 value = 1e18;
        while (value > valE18) {
            value = (value * baseE18) / 1e18;
            count++;
            if (count > 256) return -1;
        }
        return count;
    }

    function min(uint256 a, uint256 b) external pure returns (uint256) {
        return a < b ? a : b;
    }
}