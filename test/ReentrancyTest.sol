// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Victim.sol";
import "../src/Attacker.sol";

contract ReentrancyTest is Test {
    Victim public victim;
    Attacker public attacker;

    // Model parameters loaded from environment
    uint public alpha;
    uint public delta;
    uint public gasPrice;
    uint public victimBalance;

    function setUp() public {
        // Load parameters from environment
        alpha = vm.envOr("ALPHA", uint(0.001e18));        // Default: 0.1% detection rate
        delta = vm.envOr("DELTA", uint(0.5e18));          // Default: 50% max risk
        gasPrice = vm.envOr("GAS_PRICE", uint(10 gwei));  // Default: 10 gwei
        victimBalance = vm.envOr("VICTIM_BALANCE", uint(100 ether)); // Default: 100 ETH

        // Deploy victim with configured balance
        victim = new Victim{value: victimBalance}();

        // Deploy attacker with model parameters
        attacker = new Attacker{value: 1 ether}(
            address(victim),
            6,              // max reentry
            alpha,          // detection rate
            delta,         // max detection risk
            gasPrice       // gas price
        );

        // Labels for better trace readability
        vm.label(address(victim), "Victim");
        vm.label(address(attacker), "Attacker");
    }

    function testOptimalAttackParameters() public view {
        // Get optimal parameters before attack
        Attacker.AttackParams memory params = attacker.optimizeAttack(address(victim).balance);
        
        // Log optimal parameters
        console.log("=== Optimal Attack Parameters ===");
        console.log("Victim Balance:", address(victim).balance / 1e18, "ETH");
        console.log("Withdrawal amount:", params.optimalAmount / 1e18, "ETH");
        console.log("Number of calls:", params.optimalCalls);
        console.log("Expected profit:", params.expectedProfit / 1e18, "ETH");
        console.log("Detection risk:", params.detectionRisk * 100 / 1e18, "%");
        console.log("Gas required:", params.gasRequired);
        console.log("Gas cost (ETH):", (params.gasRequired * gasPrice) / 1e18, "ETH");

        // Verify parameters are within constraints
        require(params.detectionRisk <= delta, "Detection risk exceeds maximum");
        require(params.gasRequired <= block.gaslimit, "Gas required exceeds block limit");
        require(params.optimalAmount * params.optimalCalls <= address(victim).balance, "Withdrawal exceeds balance");
        
        // Verify profitability
        uint gasCost = gasPrice * params.gasRequired;
        require(params.expectedProfit > gasCost, "Attack not profitable after gas costs");
    }

    function testReentrancyProtection() public {
        // Initial state
        uint initialVictimBalance = address(victim).balance;
        uint initialAttackerBalance = address(attacker).balance;

        // Execute attack
        vm.startPrank(address(attacker));
        
        bool attackSucceeded;
        try attacker.attack{value: 1 ether}() {
            attackSucceeded = true;
        } catch Error(string memory reason) {
            // Expected to fail
            console.log("Attack prevented with reason:", reason);
            attackSucceeded = false;
        }

        vm.stopPrank();

        // The attack should have failed
        assertFalse(attackSucceeded, "Reentrancy attack should have been prevented");

        // Final state
        uint finalVictimBalance = address(victim).balance;
        uint finalAttackerBalance = address(attacker).balance;

        // Log attack metrics
        console.log("=== Attack Results ===");
        console.log("Initial Victim Balance:", initialVictimBalance / 1e18, "ETH");
        console.log("Final Victim Balance:", finalVictimBalance / 1e18, "ETH");
        console.log("Initial Attacker Balance:", initialAttackerBalance / 1e18, "ETH");
        console.log("Final Attacker Balance:", finalAttackerBalance / 1e18, "ETH");
        console.log("Gas Used:", attacker.totalGasUsed());
        console.log("Detection Risk:", attacker.detectionRisk() * 100 / 1e18, "%");

        // Verify reentrancy protection worked
        assertEq(finalVictimBalance, initialVictimBalance, "Victim balance should remain unchanged");
        assertEq(finalAttackerBalance, initialAttackerBalance, "Attacker balance should remain unchanged");
        assertEq(victim.balances(address(attacker)), 0, "Attacker balance in contract should be 0");
        assertTrue(attacker.detectionRisk() <= delta, "Detection risk exceeded maximum");
    }

    function testGasEstimation() public view {
        uint gasForSingleCall = attacker.calculateGasLimit(1);
        uint gasForMaxCalls = attacker.calculateGasLimit(6);

        console.log("=== Gas Estimation ===");
        console.log("Gas for single call:", gasForSingleCall);
        console.log("Gas for max calls:", gasForMaxCalls);
        console.log("Base gas:", attacker.BASE_GAS());
        console.log("Call gas:", attacker.CALL_GAS());
        console.log("Gas cost for max calls:", (gasForMaxCalls * gasPrice) / 1e18, "ETH");

        require(gasForSingleCall >= attacker.BASE_GAS(), "Gas estimation too low");
        require(gasForMaxCalls <= block.gaslimit, "Gas estimation exceeds block limit");
    }
}
