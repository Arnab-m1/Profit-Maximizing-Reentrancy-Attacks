// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MultiVictim1 {
    mapping(address => uint256) public balances;
    
    event LogWithdraw(address sender, uint256 amount, uint256 contractBalance, bool sent);
    event DebugWithdraw(address sender, uint256 beforeBalance, uint256 afterBalance, uint256 contractBalance, uint256 amount);
    event LogDeposit(address sender, uint256 amount, uint256 beforeBalance);
    
    constructor() payable {}
    
    function deposit() external payable {
        uint256 beforeBalance = balances[msg.sender];
        balances[msg.sender] += msg.value;
        emit LogDeposit(msg.sender, msg.value, beforeBalance);
    }
    
    function withdraw(uint256 amount) external {
        uint256 before = balances[msg.sender];
        require(before >= amount, "Insufficient balance");
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");
        balances[msg.sender] -= amount;
        uint256 afterBal = balances[msg.sender];
        emit DebugWithdraw(msg.sender, before, afterBal, address(this).balance, amount);
    }
    
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getUserBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}
