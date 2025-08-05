// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/MultiVictim1.sol";
import "../src/MultiVictim2.sol";
import "../src/MultiVictim3.sol";
import "../src/MultiContractAttacker.sol";

contract MultiContractMonitor {
    uint256 public seed;
    uint256 public alphaE18;
    mapping(address => bool) public caught;
    mapping(address => uint256) public callCount;
    mapping(address => mapping(address => uint256)) public victimCallCount;
    mapping(address => mapping(address => bool)) public victimCaught;
    
    constructor(uint256 _alphaE18) {
        alphaE18 = _alphaE18;
    }
    
    function checkDetection(address attacker, address victim) external returns (bool) {
        callCount[attacker]++;
        victimCallCount[attacker][victim]++;
        seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            blockhash(block.number - 1),
            attacker,
            victim,
            seed,
            callCount[attacker],
            victimCallCount[attacker][victim]
        )));
        uint256 roll = seed % 1e18;
        
        if (roll < alphaE18) {
            caught[attacker] = true;
            victimCaught[attacker][victim] = true;
            return true;
        }
        return false;
    }
    
    function resetAttacker(address attacker) external {
        caught[attacker] = false;
        callCount[attacker] = 0;
    }
}

contract MultiContractTest is Test {
    address[] public victimContracts;
    MultiContractAttacker attacker;
    MultiContractMonitor monitor;
    
    address attackerEOA = address(100);
    uint256 constant GAS_PRICE = 10000000000; // 10 gwei
    uint256 constant GAS_PER_CALL = 35000;
    
    struct MultiAttackResult {
        string strategy;
        uint256[] amounts;
        uint256[] calls;
        uint256 totalProfit;
        uint256 totalGasUsed;
        bool detected;
        uint256 totalRisk;
        uint256 victimCount;
        string distribution;
    }
    
    function setUp() public {
        uint256 alpha = vm.envOr("ALPHA", uint256(20000000000000000)); // 2% default
        monitor = new MultiContractMonitor(alpha);
    }
    
    function testMultiContractStrategies() public {
        runMultiContractTestSuite();
    }
    
    function testSimpleReentrancy() public {
        // Test simple reentrancy with one victim
        uint256 victimCount = 1;
        string memory distribution = "equal";
        uint256 totalBalance = 100000000000000000000; // 100 ETH
        
        // Deploy contracts
        deployContracts(victimCount, distribution, totalBalance);
        
        uint256 preBalance = attackerEOA.balance;
        emit log_named_uint("Pre-attack EOA balance", preBalance);
        
        // Check attacker contract balance before attack
        uint256 attackerPreBalance = address(attacker).balance;
        emit log_named_uint("Attacker contract pre-balance", attackerPreBalance);
        
        // Configure attack: deposit 1 ETH, withdraw 1 ETH 3 times
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory calls = new uint256[](1);
        amounts[0] = 1000000000000000000; // 1 ETH
        calls[0] = 3;
        
        vm.prank(attackerEOA);
        attacker.configureAttack(amounts, calls);
        
        vm.prank(attackerEOA);
        attacker.initiateMultiContractAttack{value: amounts[0]}();
        
        // Check attacker contract balance after attack
        uint256 attackerPostBalance = address(attacker).balance;
        emit log_named_uint("Attacker contract post-balance", attackerPostBalance);
        emit log_named_uint("Attacker contract profit", attackerPostBalance > attackerPreBalance ? attackerPostBalance - attackerPreBalance : 0);
        
        vm.prank(attackerEOA);
        attacker.withdrawAll();
        
        uint256 postBalance = attackerEOA.balance;
        emit log_named_uint("Post-attack EOA balance", postBalance);
        emit log_named_uint("EOA Profit", postBalance > preBalance ? postBalance - preBalance : 0);
        
        // Calculate actual profit: what we got minus what we deposited
        uint256 actualProfit = postBalance - preBalance + amounts[0]; // + amounts[0] because we deposited it
        emit log_named_uint("Actual Profit (deposited - withdrawn)", actualProfit);
    }
    
    function runMultiContractTestSuite() internal {
        // Get parameters from environment
        uint256 victimCount = vm.envOr("VICTIM_COUNT", uint256(3));
        string memory distribution = vm.envOr("DISTRIBUTION", string("equal"));
        uint256 totalBalance = vm.envOr("TOTAL_BALANCE", uint256(300000000000000000000)); // 300 ETH
        uint256 alpha = vm.envOr("ALPHA", uint256(20000000000000000)); // 2%
        // uint256 delta = vm.envOr("DELTA", uint256(300000000000000000)); // 30% (unused)
        // uint256 gasBudget = vm.envOr("GAS_BUDGET", uint256(3000000)); // (unused)
        
        // Deploy contracts
        deployContracts(victimCount, distribution, totalBalance);
        
        
        
        MultiAttackResult memory optimized = runOptimizedStrategy(victimCount, distribution, alpha);
        exportMultiResult(optimized);
        
        MultiAttackResult memory sequential = runSequentialStrategy(victimCount, distribution);
        exportMultiResult(sequential);
        
        MultiAttackResult memory parallel = runParallelStrategy(victimCount, distribution);
        exportMultiResult(parallel);
    }
    
    function deployContracts(uint256 victimCount, string memory distribution, uint256 totalBalance) internal {
        // Generate balances for victims
        uint256[] memory balances = generateBalances(victimCount, distribution, totalBalance);
        
        // Deploy victim contracts and collect their addresses
        address[] memory victimAddresses = new address[](victimCount);
        victimContracts = new address[](victimCount);
        
        for (uint256 i = 0; i < victimCount; i++) {
            // Deploy different victim types based on index for variety
            if (i % 3 == 0) {
                MultiVictim1 victim = new MultiVictim1();
                victimAddresses[i] = address(victim);
                victimContracts[i] = address(victim);
            } else if (i % 3 == 1) {
                MultiVictim2 victim = new MultiVictim2();
                victimAddresses[i] = address(victim);
                victimContracts[i] = address(victim);
            } else {
                MultiVictim3 victim = new MultiVictim3();
                victimAddresses[i] = address(victim);
                victimContracts[i] = address(victim);
            }
            vm.deal(victimAddresses[i], balances[i]);
            emit log_named_uint("Victim initial balance", balances[i]);
            emit log_named_uint("Victim contract balance", address(victimAddresses[i]).balance);
        }
        
        // Deploy attacker with victim addresses
        vm.prank(attackerEOA);
        attacker = new MultiContractAttacker(victimAddresses, victimCount);
        
        // Fund attacker
        vm.deal(attackerEOA, 5 * totalBalance);
    }
    
    function generateBalances(uint256 victimCount, string memory distribution, uint256 totalBalance) 
        internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](victimCount);
        for (uint256 i = 0; i < victimCount; i++) {
            // Check for per-victim env var first
            string memory envKey = string(abi.encodePacked("VICTIM_BALANCE_", vm.toString(i)));
            // Use a default of type(uint256).max to detect unset
            uint256 envBalance = vm.envOr(envKey, type(uint256).max);
            if (envBalance != type(uint256).max) {
                balances[i] = envBalance;
                continue;
            }
            // Otherwise, use distribution logic
        if (keccak256(abi.encodePacked(distribution)) == keccak256("equal")) {
                balances[i] = totalBalance / victimCount;
        } else if (keccak256(abi.encodePacked(distribution)) == keccak256("pyramid")) {
            uint256 totalWeight = 0;
                for (uint256 j = 1; j <= victimCount; j++) {
                    totalWeight += j;
            }
                balances[i] = totalBalance * (i + 1) / totalWeight;
        } else if (keccak256(abi.encodePacked(distribution)) == keccak256("exponential")) {
            uint256 totalWeight = (2 ** victimCount) - 1;
                balances[i] = totalBalance * (2 ** i) / totalWeight;
        } else {
                balances[i] = totalBalance / victimCount;
            }
        }
        return balances;
    }
    
    // === Helper: Parse comma-separated uint array from env ===
    function parseUintArray(string memory envKey, uint256 expectedLen) internal view returns (uint256[] memory arr, bool found) {
        string memory csv = vm.envOr(envKey, string(""));
        if (bytes(csv).length == 0) return (arr, false);
        // Count commas to get length
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(csv).length; i++) {
            if (bytes(csv)[i] == ",") count++;
        }
        require(count == expectedLen, "env array length mismatch");
        arr = new uint256[](expectedLen);
        uint256 idx = 0;
        uint256 last = 0;
        for (uint256 i = 0; i <= bytes(csv).length; i++) {
            if (i == bytes(csv).length || bytes(csv)[i] == ",") {
                bytes memory numBytes = new bytes(i - last);
                for (uint256 j = last; j < i; j++) {
                    numBytes[j - last] = bytes(csv)[j];
                }
                arr[idx++] = parseUint(string(numBytes));
                last = i + 1;
            }
        }
        return (arr, true);
    }
    function parseUint(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= 0x30 && b[i] <= 0x39, "invalid uint");
            result = result * 10 + (uint8(b[i]) - 48);
        }
    }
    
    // Gas function: g_i(a_i) = g0[i] + g1[i] * a_i
    // For now, hardcode g0 and g1 arrays (can be made env-driven if needed)
    function getGasParams(uint256 victimCount) internal pure returns (uint256[] memory g0, uint256[] memory g1) {
        g0 = new uint256[](victimCount);
        g1 = new uint256[](victimCount);
        for (uint256 i = 0; i < victimCount; i++) {
            g0[i] = 35000; // default base gas per call
            g1[i] = 0;     // default: no variable gas, set to nonzero for experiments
        }
    }
    
    // --- Optimized Multi-Contract Attack (Canonical Math) ---
    // Implements the model from multicontract_reentrancy_math.md
    // Maximize: Profit = sum_i [a_i * n_i - gp * n_i * g_i(a_i)]
    // Subject to:
    //   1. a_i * n_i <= B_i (balance)
    //   2. sum_i n_i * g_i(a_i) <= G (gas)
    //   3. 1 - prod_i (1-p_i)^n_i <= P (detection)
    //   4. Atomicity
    function runOptimizedStrategy(
        uint256 victimCount, string memory distribution, uint256 alpha
    ) internal returns (MultiAttackResult memory result) {
        (uint256[] memory envAmounts, bool hasAmounts) = parseUintArray("AMOUNTS", victimCount);
        (uint256[] memory envCalls, bool hasCalls) = parseUintArray("CALLS", victimCount);
        if (hasAmounts && hasCalls) {
            // Use provided parameters directly
            vm.prank(attackerEOA);
            attacker.configureAttack(envAmounts, envCalls);
            vm.prank(attackerEOA);
            uint256 deposit = getTotalDeposit(envAmounts, envCalls);
            attacker.initiateMultiContractAttack{value: deposit}();
            vm.prank(attackerEOA);
            attacker.withdrawAll();
            uint256 postBalance = attackerEOA.balance;
            uint256 preBalance = attackerEOA.balance + deposit - postBalance; // reconstruct preBalance
            uint256 totalProfit = postBalance - preBalance + deposit;
            uint256 totalGasUsed = calculateTotalGas(envCalls);
            uint256 totalRisk = calculateCumulativeRisk(envCalls, alpha);
            result.amounts = envAmounts;
            result.calls = envCalls;
            result.totalProfit = totalProfit;
            result.totalGasUsed = totalGasUsed;
            uint256[] memory envCallsArr = new uint256[](victimCount);
            for (uint256 i = 0; i < victimCount; i++) {
                envCallsArr[i] = envCalls[i];
            }
            result.detected = checkDetection(address(attacker), envCallsArr);
            result.totalRisk = totalRisk;
            result.victimCount = victimCount;
            result.distribution = distribution;
            result.strategy = "optimized";
            return result;
        }
        (uint256[] memory g0, uint256[] memory g1) = getGasParams(victimCount);
        uint256 K = 50; // breakpoints per victim
        uint256 delta = vm.envOr("DELTA", uint256(300000000000000000)); // max risk
        uint256 gasBudget = vm.envOr("GAS_BUDGET", uint256(3000000));
        uint256[] memory balances = new uint256[](victimCount);
        for (uint256 i = 0; i < victimCount; i++) {
            balances[i] = getVictimBalance(i);
        }
        // Generate breakpoints for each victim: a_i = B_i / k, k in [1, K]
        uint256[][] memory breakpoints = new uint256[][](victimCount);
        for (uint256 i = 0; i < victimCount; i++) {
            breakpoints[i] = new uint256[](K);
            for (uint256 k = 1; k <= K; k++) {
                breakpoints[i][k-1] = balances[i] / k;
            }
        }
        // Search all combinations of breakpoints (amounts)
        uint256[] memory bestAmounts = new uint256[](victimCount);
        uint256[] memory bestCalls = new uint256[](victimCount);
        uint256 bestProfit = 0;
        for (uint256 aCombo = 0; aCombo < K**victimCount; aCombo++) {
            // Decode combination index to per-victim breakpoint indices
            uint256[] memory aIdx = new uint256[](victimCount);
            uint256 tmp = aCombo;
            for (uint256 i = 0; i < victimCount; i++) {
                aIdx[i] = tmp % K;
                tmp /= K;
            }
            // Set amounts for this combo
            uint256[] memory amounts = new uint256[](victimCount);
            bool skipCombo = false;
            for (uint256 i = 0; i < victimCount; i++) {
                amounts[i] = breakpoints[i][aIdx[i]];
                if (amounts[i] == 0) { skipCombo = true; break; }
            }
            if (skipCombo) continue;
            // For each victim, compute max feasible n_i under all constraints
            uint256[] memory nMax = new uint256[](victimCount);
            for (uint256 i = 0; i < victimCount; i++) {
                uint256 n_balance = balances[i] / amounts[i];
                uint256 gasPerCall = g0[i] + g1[i] * amounts[i];
                uint256 n_gas = gasBudget / gasPerCall;
                // Detection constraint: n_detect = floor(log(1-P)/log(1-p))
                uint256 n_detect = 0;
                if (alpha > 0 && delta > 0) {
                    // log(1-P)/log(1-p) in fixed point
                    // Use approximation: n_detect = ln(1-delta/1e18)/ln(1-alpha/1e18)
                    int256 ln1mP = ln(int256(1e18 - delta));
                    int256 ln1mp = ln(int256(1e18 - alpha));
                    if (ln1mp < 0) n_detect = uint256(-ln1mP * 1e18 / ln1mp);
                    else n_detect = n_balance; // fallback
                } else {
                    n_detect = n_balance;
                }
                uint256 n = n_balance;
                if (n > n_gas) n = n_gas;
                if (n > n_detect) n = n_detect;
                if (n == 0) { skipCombo = true; break; }
                nMax[i] = n;
            }
            if (skipCombo) continue;
            // Now, try all feasible n_i <= nMax[i] (greedy: use nMax)
            uint256[] memory calls = new uint256[](victimCount);
            for (uint256 i = 0; i < victimCount; i++) calls[i] = nMax[i];
            // Check total gas
            uint256 totalGas = 0;
            for (uint256 i = 0; i < victimCount; i++) {
                uint256 gasPerCall = g0[i] + g1[i] * amounts[i];
                totalGas += calls[i] * gasPerCall;
            }
            if (totalGas > gasBudget) continue;
            // Check detection risk
            uint256 riskE18 = 1e18;
            for (uint256 i = 0; i < victimCount; i++) {
                uint256 oneMinusP = 1e18 - alpha;
                uint256 probNotDetected = 1e18;
                for (uint256 j = 0; j < calls[i]; j++) {
                    probNotDetected = (probNotDetected * oneMinusP) / 1e18;
                }
                riskE18 = (riskE18 * probNotDetected) / 1e18;
            }
            uint256 cumulativeRisk = 1e18 - riskE18;
            if (cumulativeRisk > delta) continue;
            // Compute profit
            uint256 profit = 0;
            for (uint256 i = 0; i < victimCount; i++) {
                uint256 gasPerCall = g0[i] + g1[i] * amounts[i];
                profit += amounts[i] * calls[i];
                uint256 gasCost = GAS_PRICE * calls[i] * gasPerCall;
                if (profit >= gasCost) {
                    profit -= gasCost;
                } else {
                    profit = 0; skipCombo = true; break;
                }
            }
            if (skipCombo) continue;
            if (profit > bestProfit) {
                bestProfit = profit;
                for (uint256 i = 0; i < victimCount; i++) {
                    bestAmounts[i] = amounts[i];
                    bestCalls[i] = calls[i];
                }
            }
        }
        uint256 preBalance_opt = attackerEOA.balance;
        vm.prank(attackerEOA);
        attacker.configureAttack(bestAmounts, bestCalls);
        vm.prank(attackerEOA);
        uint256 deposit_opt = getTotalDeposit(bestAmounts, bestCalls);
        attacker.initiateMultiContractAttack{value: deposit_opt}();
        vm.prank(attackerEOA);
        attacker.withdrawAll();
        uint256 postBalance_opt = attackerEOA.balance;
        uint256 totalProfit_opt = postBalance_opt - preBalance_opt + deposit_opt;
        uint256 totalGasUsed_opt = 0;
        for (uint256 i = 0; i < victimCount; i++) {
            uint256 gasPerCall = g0[i] + g1[i] * bestAmounts[i];
            totalGasUsed_opt += bestCalls[i] * gasPerCall;
        }
        uint256 totalRisk_opt = calculateCumulativeRisk(bestCalls, alpha);
        result.amounts = bestAmounts;
        result.calls = bestCalls;
        result.totalProfit = totalProfit_opt;
        result.totalGasUsed = totalGasUsed_opt;
        result.detected = checkDetection(address(attacker), bestCalls);
        result.totalRisk = totalRisk_opt;
        result.victimCount = victimCount;
        result.distribution = distribution;
        result.strategy = "optimized";
        return result;
    }
    // --- Natural log in 1e18 fixed point ---
    function ln(int256 x) internal pure returns (int256) {
        // Approximate ln(x/1e18) in 1e18 fixed point
        // Only valid for x in (0, 1e18]
        require(x > 0, "ln domain");
        int256 y = 0;
        int256 z = (x - 1e18) * 1e18 / (x + 1e18);
        int256 z2 = (z * z) / 1e18;
        y = 2 * (z + (z2 * z) / 3e18 + (z2 * z2 * z) / 5e18);
        return y;
    }
    
    function runSequentialStrategy(uint256 victimCount, string memory distribution) 
        internal returns (MultiAttackResult memory) {
        resetForNewStrategy();
        uint256[] memory amounts = new uint256[](victimCount);
        uint256[] memory calls = new uint256[](victimCount);
        // Sequential: split withdrawal into 2 calls per victim for higher detection risk
        for (uint256 i = 0; i < victimCount; i++) {
            uint256 balance = getVictimBalance(i);
            calls[i] = 2;
            amounts[i] = balance / 2;
            if (amounts[i] == 0 && balance > 0) {
                amounts[i] = 1;
        }
        }
        uint256 preBalance = attackerEOA.balance;
        vm.prank(attackerEOA);
        attacker.configureAttack(amounts, calls);
        vm.prank(attackerEOA);
        uint256 deposit = getTotalDeposit(amounts, calls);
        attacker.initiateMultiContractAttack{value: deposit}();
        vm.prank(attackerEOA);
        attacker.withdrawAll();
        uint256 postBalance = attackerEOA.balance;
        uint256 alpha = vm.envOr("ALPHA", uint256(20000000000000000));
        uint256 totalProfit = postBalance - preBalance + deposit;
        return MultiAttackResult({
            strategy: "sequential",
            amounts: amounts,
            calls: calls,
            totalProfit: totalProfit,
            totalGasUsed: calculateTotalGas(calls),
            detected: checkDetection(address(attacker), calls),
            totalRisk: calculateCumulativeRisk(calls, alpha),
            victimCount: victimCount,
            distribution: distribution
        });
    }
    
    function runParallelStrategy(uint256 victimCount, string memory distribution) 
        internal returns (MultiAttackResult memory) {
        resetForNewStrategy();
        uint256[] memory amounts = new uint256[](victimCount);
        uint256[] memory calls = new uint256[](victimCount);
        // Parallel: small amounts, many calls
        for (uint256 i = 0; i < victimCount; i++) {
            uint256 balance = getVictimBalance(i);
            amounts[i] = balance / 10;
            if (amounts[i] == 0 && balance > 0) {
                amounts[i] = 1;
            }
            calls[i] = 5;
        }
        uint256 preBalance = attackerEOA.balance;
        vm.prank(attackerEOA);
        attacker.configureAttack(amounts, calls);
        vm.prank(attackerEOA);
        uint256 deposit = getTotalDeposit(amounts, calls);
        attacker.initiateMultiContractAttack{value: deposit}();
        vm.prank(attackerEOA);
        attacker.withdrawAll();
        uint256 postBalance = attackerEOA.balance;
        uint256 alpha = vm.envOr("ALPHA", uint256(20000000000000000));
        uint256 totalProfit = postBalance - preBalance + deposit;
        return MultiAttackResult({
            strategy: "parallel",
            amounts: amounts,
            calls: calls,
            totalProfit: totalProfit,
            totalGasUsed: calculateTotalGas(calls),
            detected: checkDetection(address(attacker), calls),
            totalRisk: calculateCumulativeRisk(calls, alpha),
            victimCount: victimCount,
            distribution: distribution
        });
    }
    
    function resetForNewStrategy() internal {
        // Reset for new test
        uint256 victimCount = vm.envOr("VICTIM_COUNT", uint256(3));
        string memory distribution = vm.envOr("DISTRIBUTION", string("equal"));
        uint256 totalBalance = vm.envOr("TOTAL_BALANCE", uint256(300000000000000000000));
        
        deployContracts(victimCount, distribution, totalBalance);
        monitor.resetAttacker(address(attacker));
    }
    
    function getVictimBalance(uint256 index) internal view returns (uint256) {
        if (index < victimContracts.length) {
            return address(victimContracts[index]).balance;
        }
        return 0;
    }
    
    function getTotalDeposit(uint256[] memory amounts, uint256[] memory calls) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            // Guard: amounts[i] * calls[i] no overflow
            if (calls[i] > 0 && amounts[i] > type(uint256).max / calls[i]) continue;
            total += amounts[i] * calls[i];
        }
        return total;
    }
    
    function calculateTotalGas(uint256[] memory calls) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            total += calls[i] * GAS_PER_CALL;
        }
        return total;
    }
    
    function calculateCumulativeRisk(uint256[] memory calls, uint256 alpha) internal pure returns (uint256) {
        // alpha is in 1e18 fixed point
        uint256 probNotDetectedE18 = 1e18;
        for (uint256 i = 0; i < calls.length; i++) {
            // (1 - alpha/1e18) ** calls[i]
            uint256 oneMinusAlphaE18 = 1e18 - alpha;
            uint256 probNotDetectedVictimE18 = 1e18;
            for (uint256 j = 0; j < calls[i]; j++) {
                probNotDetectedVictimE18 = (probNotDetectedVictimE18 * oneMinusAlphaE18) / 1e18;
            }
            probNotDetectedE18 = (probNotDetectedE18 * probNotDetectedVictimE18) / 1e18;
        }
        return 1e18 - probNotDetectedE18;
    }
    
    function checkDetection(address attacker, uint256[] memory calls) internal returns (bool) {
        for (uint256 i = 0; i < calls.length; i++) {
            for (uint256 j = 0; j < calls[i]; j++) {
                if (monitor.checkDetection(attacker, victimContracts[i])) {
                    return true;
        }
            }
        }
        return false;
    }
    
    function getEffectiveProfit(uint256[] memory amounts, uint256[] memory calls) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            // Guard: amounts[i] * calls[i] no overflow
            if (calls[i] > 0 && amounts[i] > type(uint256).max / calls[i]) continue;
            total += amounts[i] * calls[i];
        }
        return total;
    }
    
    function getRiskUsage(uint256 used, uint256 max) internal pure returns (uint256) {
        if (max == 0) return 0;
        return (used * 1e18) / max;
    }
    
    function exportMultiResult(MultiAttackResult memory result) internal {
        string memory uuid = vm.envOr("TEST_UUID", string("default-uuid"));
        string memory filename = string(abi.encodePacked("multi_", result.strategy, "_", uuid, ".json"));
        string memory amountsJson = "[";
        string memory callsJson = "[";
        for (uint256 i = 0; i < result.amounts.length; i++) {
            if (i > 0) {
                amountsJson = string(abi.encodePacked(amountsJson, ","));
                callsJson = string(abi.encodePacked(callsJson, ","));
            }
            amountsJson = string(abi.encodePacked(amountsJson, vm.toString(result.amounts[i] / 1e15))); // Convert to milliETH
            callsJson = string(abi.encodePacked(callsJson, vm.toString(result.calls[i])));
        }
        amountsJson = string(abi.encodePacked(amountsJson, "]"));
        callsJson = string(abi.encodePacked(callsJson, "]"));
        string memory json = string(abi.encodePacked(
            "{\n",
            '  "strategy": "', result.strategy, '",\n',
            '  "amounts": ', amountsJson, ',\n',
            '  "calls": ', callsJson, ',\n',
            '  "total_profit": ', vm.toString(result.totalProfit / 1e15), ',\n',
            '  "effective_profit": ', vm.toString(getEffectiveProfit(result.amounts, result.calls) / 1e15), ',\n',
            '  "risk_utilization": ', vm.toString(getRiskUsage(result.totalRisk, vm.envOr("DELTA", uint256(300000000000000000)))), ',\n',
            '  "total_gas_used": ', vm.toString(result.totalGasUsed), ',\n',
            '  "detected": ', result.detected ? "true" : "false", ',\n',
            '  "total_risk": ', vm.toString(result.totalRisk), ',\n',
            '  "victim_count": ', vm.toString(result.victimCount), ',\n',
            '  "distribution": "', result.distribution, '",\n',
            '  "alpha": "', vm.toString(vm.envOr("ALPHA", uint256(20000000000000000))), '",\n',
            '  "delta": "', vm.toString(vm.envOr("DELTA", uint256(300000000000000000))), '",\n',
            '  "gas_price": "', vm.toString(vm.envOr("GAS_PRICE", uint256(10000000000))), '",\n',
            '  "total_balance": "', vm.toString(vm.envOr("TOTAL_BALANCE", uint256(300000000000000000000))), '"\n',
            "}"
        ));
        vm.writeFile(string(abi.encodePacked("logs/", filename)), json);
    }
}
