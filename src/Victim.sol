// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Victim {
    mapping(address => uint) public balances;

    constructor() payable {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint amount) external {
        require(balances[msg.sender] >= amount, "Insufficient");
        balances[msg.sender] -= amount; // Update state before external call
        (bool sent, ) = msg.sender.call{value: amount}(""); // External interaction last
        require(sent, "Transfer failed");
    }

    function getBalance() external view returns (uint) {
        return address(this).balance;
    }
}
