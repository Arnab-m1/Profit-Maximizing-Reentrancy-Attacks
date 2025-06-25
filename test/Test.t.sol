// // pragma solidity ^0.8.0;

// // import "../lib/forge-std/src/Test.sol";
// // import "../src/Victim2.sol";
// // import "../src/Attacker2.sol";

// // contract MonitorMock {
// //     uint256 public seed;
// //     uint256 public alphaE18; // per-call detection risk in 1e18 fixed point
// //     mapping(address => bool) public caught;

// //     constructor(uint256 _alphaE18) {
// //         alphaE18 = _alphaE18;
// //     }

// //     function checkDetection(address attacker) external returns (bool) {
// //         seed = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), attacker, seed)));
// //         uint256 roll = seed % 1e18;
// //         if (roll < alphaE18) {
// //             caught[attacker] = true;
// //             return true;
// //         }
// //         return false;
// //     }
// // }

// // contract ReentrancyOptimizerTest is Test {
// //     Victim2 victim;
// //     Attacker2 attacker;
// //     MonitorMock monitor;

// //     address attackerEOA = address(100);
// //     uint256 constant INITIAL_VICTIM_BALANCE = 100 ether;
// //     uint256 constant GAS_PRICE = 0.00001 ether / 1e5; // 0.00001 ETH/gas
// //     uint256 constant GAS_PER_CALL = 30000;
    
    


// //     struct AttackResult {
// //     string strategy;
// //     uint256 a;
// //     uint256 n;
// //     uint256 profit;
// //     uint256 gasUsed;
// //     bool detected;
// //     uint256 riskE18; // ← Add this
// // }


// //     function setUp() public {
// //         monitor = new MonitorMock(0.01e18); // 1% per-call detection risk
// //     }

// //     function testRepeatedStrategySweeps() public {
// //         for (uint256 i = 0; i < 50; i++) {
// //             runTestOnce();
// //         }
// //     }

// //     function runTestOnce() internal {
// //         victim = new Victim2();
// //         vm.deal(address(victim), INITIAL_VICTIM_BALANCE);

// //         vm.prank(attackerEOA);
// //         attacker = new Attacker2(address(victim));
// //         vm.deal(attackerEOA, 3 * INITIAL_VICTIM_BALANCE);

// //         uint256 B0 = INITIAL_VICTIM_BALANCE;
// //         uint256 g0 = GAS_PER_CALL;
// //         uint256 Gmax = 3000000;
// //         uint256 alpha = 0.01e18;
// //         uint256 delta = 0.3e18;
// //         uint256 p = GAS_PRICE;

// //         uint256 Ng = Gmax / g0;
// //         uint256 Nd = uint256(victim.logBase((1e18 - delta), (1e18 - alpha)));
        

// //         AttackResult memory opt = runOptimized(B0, g0, p, Ng, Nd);
// //         exportResult(opt);

        


// //         AttackResult memory greedy = runGreedy(B0);
// //         exportResult(greedy);

// //         AttackResult memory uniform = runUniformSplit(B0, 5);
// //         exportResult(uniform);
// //     }

// //     function exportResult(AttackResult memory r) internal {
// //         string memory json = string(
// //             abi.encodePacked(
// //                 "{\n",
// //                 '  "strategy": "', r.strategy, '",\n',
// //                 '  "a": ', vm.toString(r.a / 1e18), ",\n",
// //                 '  "n": ', vm.toString(r.n), ",\n",
// //                 '  "profit": ', vm.toString(r.profit / 1e18), ",\n",
// //                 '  "gas_used": ', vm.toString(r.gasUsed), ",\n",
// //                 '  "detected": ', r.detected ? "true" : "false", "\n",
// //                 "}"
// //             )
// //         );

// //         string memory uuid = vm.envString("TEST_UUID");
// //         string memory path = string(
// //             abi.encodePacked("logs/", r.strategy, "_", uuid, ".json")
// //         );
// //         vm.writeFile(path, json);
// //     }

// //     function runOptimized(uint256 B0, uint256 g0, uint256 p, uint256 Ng, uint256 Nd) internal returns (AttackResult memory) {
// //     uint256 bestProfit = 0;
// //     uint256 aStar;
// //     uint256 nStar;

// //         uint256 maxK = Ng < Nd ? Ng : Nd;
// //     for (uint256 k = 1; k <= maxK; k++) {
// //         uint256 a_k = B0 / k;
// //             uint256 n_k = victim.min(victim.min(k, Ng), Nd);
// //         uint256 profit = (a_k - p * g0) * n_k;
// //         if (profit > bestProfit) {
// //             bestProfit = profit;
// //             aStar = a_k;
// //             nStar = n_k;
// //             }
// //         }

// //     vm.prank(attackerEOA);
// //     attacker.initiateAttack{value: aStar}(aStar, nStar);

// //         bool detected = false;
// //         for (uint256 i = 0; i < nStar; i++) {
// //             detected = monitor.checkDetection(address(attacker));
// //             if (detected) break;
// //         }

// //         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), nStar);
// //         return AttackResult("optimized", aStar, nStar, attackerEOA.balance, GAS_PER_CALL * nStar, detected, risk);
// //     }

// //     function runGreedy(uint256 B0) internal returns (AttackResult memory) {
// //         uint256 a = B0;
// //         uint256 n = 1;

// //         vm.prank(attackerEOA);
// //         attacker.initiateAttack{value: a}(a, n);

// //         bool detected = monitor.checkDetection(address(attacker));

// //         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
// //         return AttackResult("greedy", a, n, attackerEOA.balance, GAS_PER_CALL * n, detected, risk);
// //     }

// //     function runUniformSplit(uint256 B0, uint256 n) internal returns (AttackResult memory) {
// //         uint256 a = B0 / n;

// //         vm.prank(attackerEOA);
// //         attacker.initiateAttack{value: a}(a, n);

// //         bool detected = false;
// //         for (uint256 i = 0; i < n; i++) {
// //             detected = monitor.checkDetection(address(attacker));
// //             if (detected) break;
// //         }

// //         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
// //         return AttackResult("uniform", a, n, attackerEOA.balance, GAS_PER_CALL * n, detected, risk);
// //     }
// // }






// pragma solidity ^0.8.0;

// import "../lib/forge-std/src/Test.sol";
// import "../src/Victim2.sol";
// import "../src/Attacker2.sol";

// contract MonitorMock {

//     uint256 public seed;
    
//     uint256 public alphaE18; // per-call detection risk in 1e18 fixed point
//     mapping(address => bool) public caught;

//     constructor(uint256 _alphaE18) {
//         alphaE18 = _alphaE18;
//     }

//     function checkDetection(address attacker) external returns (bool) {
//         seed = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), attacker, seed)));
//         uint256 roll = seed % 1e18;
//         if (roll < alphaE18) {
//             caught[attacker] = true;
//             return true;
//         }
//         return false;
//     }
// }



// contract ReentrancyOptimizerTest is Test {
//     Victim2 victim;
//     Attacker2 attacker;
//     MonitorMock monitor;

//     address attackerEOA = address(100);
//     uint256 constant INITIAL_VICTIM_BALANCE = 100 ether;
//     uint256 constant GAS_PRICE = 0.00001 ether / 1e5; // 0.00001 ETH/gas
//     uint256 constant GAS_PER_CALL = 30000;

//     struct AttackResult {
//         string strategy;
//         uint256 a;
//         uint256 n;
//         uint256 profit;
//         uint256 gasUsed;
//         bool detected;
//         uint256 riskE18; // 1e18-based fixed-point cumulative detection risk

//     }

//     function setUp() public {
//         monitor = new MonitorMock(0.01e18); // 1% per-call detection probability
//     }

//     function testRepeatedStrategySweeps() public {
//         for (uint256 i = 0; i < 50; i++) {
//             runTestOnce();
//         }
//     }

//     function runTestOnce() internal {
//         victim = new Victim2();
//         vm.deal(address(victim), INITIAL_VICTIM_BALANCE);

//         vm.prank(attackerEOA);
//         attacker = new Attacker2(address(victim));
//         vm.deal(attackerEOA, 3 * INITIAL_VICTIM_BALANCE);

//         uint256 B0 = INITIAL_VICTIM_BALANCE;
//         uint256 g0 = GAS_PER_CALL;
//         uint256 Gmax = 3000000;
//         uint256 alpha = 0.01e18;
//         uint256 delta = 0.3e18;
//         uint256 p = GAS_PRICE;

//         uint256 Ng = Gmax / g0;    
//         int256 Nd_int = victim.logBase((1e18 - delta), (1e18 - alpha));
//         require(Nd_int >= 0, "Nd must be non-negative");
//         uint256 Nd = uint256(Nd_int);

//         AttackResult memory opt = runOptimized(B0, g0, p, alpha, Ng, Nd);
//         exportResult(opt);

//         AttackResult memory greedy = runGreedy(B0, alpha);
//         exportResult(greedy);

//         AttackResult memory uniform = runUniformSplit(B0, 5, alpha);
//         exportResult(uniform);
//     }






//     function exportResult(AttackResult memory r) internal {
//         string memory json = string(
//             abi.encodePacked(
//                 "{\n",
//                 '  "strategy": "', r.strategy, '",\n',
//                 '  "a": ', vm.toString(r.a / 1e18), ",\n",
//                 '  "n": ', vm.toString(r.n), ",\n",
//                 '  "profit": ', vm.toString(r.profit / 1e18), ",\n",
//                 '  "gas_used": ', vm.toString(r.gasUsed), ",\n",
//                 '  "detected": ', r.detected ? "true" : "false", ",\n",
//                 '  "detection_risk": ', vm.toString(r.riskE18 / 1e16), "\n", // percent format
//                 "}"
//             )
//         );

//         string memory uuid = vm.envString("TEST_UUID");
//         string memory path = string(
//             abi.encodePacked("logs/", r.strategy, "_", uuid, ".json")
//         );
//         vm.writeFile(path, json);
//     }

//     function runOptimized(
//         uint256 B0,
//         uint256 g0,
//         uint256 p,
//         uint256 alpha,
//         uint256 Ng,
//         uint256 Nd
//     ) internal returns (AttackResult memory) {
//         uint256 bestProfit = 0;
//         uint256 aStar;
//         uint256 nStar;

//         uint256 maxK = Ng < Nd ? Ng : Nd;
//         for (uint256 k = 1; k <= maxK; k++) {
//             uint256 a_k = B0 / k;
//             uint256 n_k = victim.min(victim.min(k, Ng), Nd);
//             uint256 loopProfit = (a_k - p * g0) * n_k;
//             if (loopProfit > bestProfit) {
//                 bestProfit = loopProfit;
//                 aStar = a_k;
//                 nStar = n_k;
//             }
//         }

//         uint256 preAttackBalance = attackerEOA.balance;

//         vm.prank(attackerEOA);
//         attacker.initiateAttack{value: aStar}(aStar, nStar);

//         bool detected = false;
//         for (uint256 i = 0; i < nStar; i++) {
//             if (monitor.checkDetection(address(attacker))) {
//                 detected = true;
//                 break;
//             }
//         }

//         uint256 profit = attackerEOA.balance - preAttackBalance;
//         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), nStar);
//         return AttackResult("optimized", aStar, nStar, profit, GAS_PER_CALL * nStar, detected, risk);
//     }

//     function runGreedy(uint256 B0, uint256 alpha) internal returns (AttackResult memory) {
//         uint256 a = B0;
//         uint256 n = 1;
//         if (a == 0) {
//             return AttackResult("greedy", 0, 0, 0, 0, false, 0);
//         }
//         if (a <= GAS_PRICE * GAS_PER_CALL) {
//             return AttackResult("greedy", a, n, 0, GAS_PER_CALL * n, false, 0);
//         }
//         uint256 preAttackBalance = attackerEOA.balance;

//         vm.prank(attackerEOA);
//         attacker.initiateAttack{value: a}(a, n);

//         bool detected = monitor.checkDetection(address(attacker));

//         uint256 profit = attackerEOA.balance >= preAttackBalance ? (attackerEOA.balance - preAttackBalance) : 0;
//         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
//         return AttackResult("greedy", a, n, profit, GAS_PER_CALL * n, detected, risk);
//     }

//     function runUniformSplit(uint256 B0, uint256 n, uint256 alpha) internal returns (AttackResult memory) {
//         if (n == 0) {
//             return AttackResult("uniform", 0, 0, 0, 0, false, 0);
//         }
//         uint256 a = B0 / n;
//         if (a == 0) {
//             return AttackResult("uniform", 0, n, 0, GAS_PER_CALL * n, false, 0);
//         }
//         if (a <= GAS_PRICE * GAS_PER_CALL) {
//             return AttackResult("uniform", a, n, 0, GAS_PER_CALL * n, false, 0);
//         }
//         uint256 preAttackBalance = attackerEOA.balance;

//         vm.prank(attackerEOA);
//         attacker.initiateAttack{value: a}(a, n);

//         bool detected = false;
//         for (uint256 i = 0; i < n; i++) {
//             if (monitor.checkDetection(address(attacker))) {
//                 detected = true;
//                 break;
//             }
//         }

//         uint256 profit = attackerEOA.balance >= preAttackBalance ? (attackerEOA.balance - preAttackBalance) : 0;
//         uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
//         return AttackResult("uniform", a, n, profit, GAS_PER_CALL * n, detected, risk);
//     }
// }












































// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/Victim2.sol";
import "../src/Attacker2.sol";

contract MonitorMock {
    uint256 public seed;
    uint256 public alphaE18; // per-call detection risk in 1e18 fixed point
    mapping(address => bool) public caught;

    constructor(uint256 _alphaE18) {
        alphaE18 = _alphaE18;
    }

    function checkDetection(address attacker) external returns (bool) {
        seed = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), attacker, seed)));
        uint256 roll = seed % 1e18;
        if (roll < alphaE18) {
            caught[attacker] = true;
            return true;
        }
        return false;
    }
}

contract ReentrancyOptimizerTest is Test {
    Victim2 victim;
    Attacker2 attacker;
    MonitorMock monitor;

    address attackerEOA = address(100);
    uint256 constant INITIAL_VICTIM_BALANCE = 100 ether;
    uint256 constant GAS_PRICE = 0.00001 ether / 1e5; // 0.00001 ETH/gas
    uint256 constant GAS_PER_CALL = 30000;

    struct AttackResult {
        string strategy;
        uint256 a;
        uint256 n;
        uint256 profit;
        uint256 gasUsed;
        bool detected;
        uint256 riskE18;
    }

    function setUp() public {
        monitor = new MonitorMock(0.01e18); // 1% per-call detection probability
    }

    function testRepeatedStrategySweeps() public {
        for (uint256 i = 0; i < 50; i++) {
            runTestOnce();
        }
    }

    function runTestOnce() internal {
        victim = new Victim2();
        vm.deal(address(victim), INITIAL_VICTIM_BALANCE);

        vm.prank(attackerEOA);
        attacker = new Attacker2(address(victim));
        vm.deal(attackerEOA, 3 * INITIAL_VICTIM_BALANCE);

        uint256 B0 = INITIAL_VICTIM_BALANCE;
        uint256 g0 = GAS_PER_CALL;
        uint256 Gmax = 3000000;
        uint256 alpha = vm.parseUint(vm.envString("ALPHA"));
        uint256 delta = vm.parseUint(vm.envString("DELTA"));
        uint256 p = GAS_PRICE;

        uint256 Ng = Gmax / g0;
        int256 Nd_int = victim.logBase((1e18 - delta), (1e18 - alpha));
        if (Nd_int < 0) {
            Nd_int = 0;
        }
        uint256 Nd = uint256(Nd_int);

        AttackResult memory opt = runOptimized(B0, g0, p, alpha, Ng, Nd);
        exportResult(opt);

        AttackResult memory greedy = runGreedy(B0, alpha);
        exportResult(greedy);

        AttackResult memory uniform = runUniformSplit(B0, 5, alpha);
        exportResult(uniform);
    }

    function exportResult(AttackResult memory r) internal {
        string memory alphaStr = vm.envString("ALPHA");
        string memory deltaStr = vm.envString("DELTA");
        string memory gasStr = vm.envString("GAS_PRICE");
        string memory balanceStr = vm.envString("VICTIM_BALANCE");

        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "strategy": "', r.strategy, '",\n',
                '  "a": ', vm.toString(r.a / 1e18), ",\n",
                '  "n": ', vm.toString(r.n), ",\n",
                '  "profit": ', vm.toString(r.profit / 1e18), ",\n",
                '  "gas_used": ', vm.toString(r.gasUsed), ",\n",
                '  "detected": ', r.detected ? "true" : "false", ",\n",
                '  "detection_risk": ', vm.toString(r.riskE18 / 1e16), ",\n",
                '  "alpha": ', alphaStr, ",\n",
                '  "delta": ', deltaStr, ",\n",
                '  "gas_price": ', gasStr, ",\n",
                '  "victim_balance": ', balanceStr, "\n",
                "}"
            )
        );

        string memory uuid = vm.envString("TEST_UUID");
        string memory path = string(abi.encodePacked("logs/", r.strategy, "_", uuid, ".json"));
        vm.writeFile(path, json);
    }

    function runOptimized(
        uint256 B0,
        uint256 g0,
        uint256 p,
        uint256 alpha,
        uint256 Ng,
        uint256 Nd
    ) internal returns (AttackResult memory) {
        uint256 bestProfit = 0;
        uint256 aStar;
        uint256 nStar;

        uint256 maxK = Ng < Nd ? Ng : Nd;
        for (uint256 k = 1; k <= maxK; k++) {
            uint256 a_k = B0 / k;
            if (a_k == 0) continue;
            uint256 n_k = victim.min(victim.min(k, Ng), Nd);
            if (n_k == 0) continue;
            if (a_k <= p * g0) continue; // not profitable, would underflow
            uint256 loopProfit = (a_k - p * g0) * n_k;
            if (loopProfit > bestProfit) {
                bestProfit = loopProfit;
                aStar = a_k;
                nStar = n_k;
            }
        }
        if (aStar == 0 || nStar == 0) {
            return AttackResult("optimized", 0, 0, 0, 0, false, 0);
        }

        uint256 preAttackBalance = attackerEOA.balance;

        vm.prank(attackerEOA);
        attacker.initiateAttack{value: aStar}(aStar, nStar);

        bool detected = false;
        for (uint256 i = 0; i < nStar; i++) {
            if (monitor.checkDetection(address(attacker))) {
                detected = true;
                break;
            }
        }

        uint256 profit = attackerEOA.balance >= preAttackBalance ? (attackerEOA.balance - preAttackBalance) : 0;
        uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), nStar);
        return AttackResult("optimized", aStar, nStar, profit, GAS_PER_CALL * nStar, detected, risk);
    }

    function runGreedy(uint256 B0, uint256 alpha) internal returns (AttackResult memory) {
        uint256 a = B0;
        uint256 n = 1;
        if (a == 0) {
            return AttackResult("greedy", 0, 0, 0, 0, false, 0);
        }
        if (a <= GAS_PRICE * GAS_PER_CALL) {
            return AttackResult("greedy", a, n, 0, GAS_PER_CALL * n, false, 0);
        }
        uint256 preAttackBalance = attackerEOA.balance;

        vm.prank(attackerEOA);
        attacker.initiateAttack{value: a}(a, n);

        bool detected = monitor.checkDetection(address(attacker));

        uint256 profit = attackerEOA.balance >= preAttackBalance ? (attackerEOA.balance - preAttackBalance) : 0;
        uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
        return AttackResult("greedy", a, n, profit, GAS_PER_CALL * n, detected, risk);
    }

    function runUniformSplit(uint256 B0, uint256 n, uint256 alpha) internal returns (AttackResult memory) {
        if (n == 0) {
            return AttackResult("uniform", 0, 0, 0, 0, false, 0);
        }
        uint256 a = B0 / n;
        if (a == 0) {
            return AttackResult("uniform", 0, n, 0, GAS_PER_CALL * n, false, 0);
        }
        if (a <= GAS_PRICE * GAS_PER_CALL) {
            return AttackResult("uniform", a, n, 0, GAS_PER_CALL * n, false, 0);
        }
        uint256 preAttackBalance = attackerEOA.balance;

        vm.prank(attackerEOA);
        attacker.initiateAttack{value: a}(a, n);

        bool detected = false;
        for (uint256 i = 0; i < n; i++) {
            if (monitor.checkDetection(address(attacker))) {
                detected = true;
                break;
            }
        }

        uint256 profit = attackerEOA.balance >= preAttackBalance ? (attackerEOA.balance - preAttackBalance) : 0;
        uint256 risk = 1e18 - Victim2(address(victim)).pow((1e18 - alpha), n);
        return AttackResult("uniform", a, n, profit, GAS_PER_CALL * n, detected, risk);
    }
}
