// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Victim2 {
    mapping(address => uint256) public balances;


    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return a < b ? a : b;
    }

    function logBase(uint256 x, uint256 base) public pure returns (int256) {
    // Computes ln(x)/ln(base) using Taylor approx near 1.0
    // Assumes x and base are in 1e18 fixed point
    require(x > 0 && base > 0, "log: x and base must be > 0");

    int256 lnX = ln(int256(x));
    int256 lnBase = ln(int256(base));
    return lnX * 1e18 / lnBase;
}



function ln(int256 x) public pure returns (int256) {
    // Natural log approximation using 10 terms of series around 1.0
    require(x > 0, "ln: x must be > 0");
    int256 z = (x - 1e18) * 1e18 / (x + 1e18);
    int256 z2 = (z * z) / 1e18;
    int256 term = z;
    int256 result = 0;
    for (uint256 i = 1; i <= 9; i += 2) {
        result += term / int256(i);
        term = (term * z2) / 1e18;
    }
    return 2 * result;
}


    constructor() payable {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient");
        balances[msg.sender] -= amount;
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function pow(uint256 x, uint256 n) public pure returns (uint256) {
    // Computes x^n where x is in 1e18 fixed point, n is integer
    uint256 result = 1e18;
    for (uint256 i = 0; i < n; i++) {
        result = (result * x) / 1e18;
    }
    return result;
}
}
