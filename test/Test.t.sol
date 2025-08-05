// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/Victim2.sol";
import "../src/Attacker2.sol";

contract MonitorMock {
    uint256 public seed;
    uint256 public alphaE18;
    mapping(address => bool) public caught;

    constructor(uint256 _alphaE18) {
        alphaE18 = _alphaE18;
    }

    function checkDetection(address attacker) external returns (bool) {
        seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), attacker, seed))
        );
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
    uint256 constant GAS_PER_CALL = 30_000;

    struct AttackResult {
        string  strategy;
        uint256 a;
        uint256 n;
        uint256 profit;      // now “net profit” in wei
        uint256 gasUsed;     // = GAS_PER_CALL * n
        bool    detected;
        uint256 riskE18;
    }

  

    function setUp() public {
    monitor = new MonitorMock(0.01e18);
    
}


    function testManualRun() public {
        runTestOnce();
    }

    function runTestOnce() internal {
        //
        //  read in your env vars
        victim = new Victim2();
        //
        uint256 B0    = vm.parseUint(vm.envString("VICTIM_BALANCE"));
        uint256 p     = vm.parseUint(vm.envString("GAS_PRICE"));    // in wei/gas
        uint256 alpha = vm.parseUint(vm.envString("ALPHA"));        // 1e18 units
        uint256 delta = vm.parseUint(vm.envString("DELTA"));        // 1e18 units

        // fund the victim _contract_ so it actually has ETH to steal
        vm.deal(address(victim), B0);
        // fund your EOA so it can call
        vm.deal(attackerEOA, B0 * 3);

        // deploy attacker
        vm.startPrank(attackerEOA);
        attacker = new Attacker2(payable(address(victim)));
        vm.stopPrank();

        uint256 Ng = 3_000_000 / GAS_PER_CALL;                 // max calls by gas
        int256  Nd_int = int256(victim.logBase(1e18 - alpha, 1e18 - delta));
        if (Nd_int < 0) Nd_int = 0;
        uint256 Nd = uint256(Nd_int);

        exportResult( runOptimized(B0, GAS_PER_CALL, p, alpha, Ng, Nd) );
        exportResult( runGreedy   (B0,                 p, alpha) );
        exportResult( runUniform  (B0, 5,              p, alpha) );
    }

    // function exportResult(AttackResult memory r) internal {
    //     string memory uuid = vm.envString("TEST_UUID");
        // string memory json = string(
        //     abi.encodePacked(
        //         "{",
        //           '"strategy":"', r.strategy,'",',
        //           '"a":',        vm.toString(r.a),       ",",
        //           '"n":',        vm.toString(r.n),       ",",
        //           '"profit":',   vm.toString(r.profit),  ",",
        //           '"gas_used":', vm.toString(r.gasUsed), ",",
        //           '"detected":', r.detected ? "true" : "false", ",",
        //           '"risk":',     vm.toString(r.riskE18),
        //         "}"  
        //     )
        // );

    //     string memory json = string(
    //     abi.encodePacked(
    //         "{\n",
    //         '  "strategy": "',        r.strategy,               '",\n',
    //         '  "a": ',               vm.toString(r.a),          ',\n',
    //         '  "n": ',               vm.toString(r.n),          ',\n',
    //         '  "profit": ',          vm.toString(r.profit),     ',\n',
    //         '  "gas_used": ',        vm.toString(r.gasUsed),    ',\n',
    //         '  "detected": ',        r.detected ? "true" : "false", ',\n',
    //         '  "detection_risk": ',  vm.toString(r.riskE18 / 1e16), ',\n',
    //         '  "alpha": ',           alphaStr,                   ',\n',
    //         '  "delta": ',           deltaStr,                   ',\n',
    //         '  "gas_price": ',       gasPriceStr,                ',\n',
    //         '  "victim_balance": ',  victimBalanceStr,           '\n',
    //         "}"
    //     )
    // );
        
    //     vm.writeFile(
    //         string(abi.encodePacked("logs/", r.strategy, "_", uuid, ".json")),
    //         json
    //     );
    // }


    function exportResult(AttackResult memory r) internal {
    string memory uuid = vm.envString("TEST_UUID");

    /* ➊ bring the values you want to embed into scope */
    string memory alphaStr         = vm.envString("ALPHA");
    string memory deltaStr         = vm.envString("DELTA");
    string memory gasPriceStr      = vm.envString("GAS_PRICE");
    string memory victimBalanceStr = vm.envString("VICTIM_BALANCE");

    /* ➋ build the JSON */
    string memory json = string(
        abi.encodePacked(
            "{\n",
            '  "strategy": "',        r.strategy,               '",\n',
            '  "a": ',                vm.toString(r.a),         ',\n',
            '  "n": ',                vm.toString(r.n),         ',\n',
            '  "profit": ',           vm.toString(r.profit),    ',\n',
            '  "gas_used": ',         vm.toString(r.gasUsed),   ',\n',
            '  "detected": ',         r.detected ? "true" : "false", ',\n',
            '  "detection_risk": ',   vm.toString(r.riskE18 / 1e16), ',\n',
            '  "alpha": ',            alphaStr,                 ',\n',
            '  "delta": ',            deltaStr,                 ',\n',
            '  "gas_price": ',        gasPriceStr,              ',\n',
            '  "victim_balance": ',   victimBalanceStr,         '\n',
            "}"
        )
    );

    /* ➌ write the file (make sure the “logs” folder exists) */
    vm.writeFile(
        string(abi.encodePacked("logs/", r.strategy, "_", uuid, ".json")),
        json
    );
}

    function runOptimized(
        uint256 B0,
        uint256 g0,
        uint256 p,
        uint256 alpha,
        uint256 Ng,
        uint256 Nd
    ) internal returns (AttackResult memory) {
        // 1) find (a*, n*)
        uint256 bestProfit;
        uint256 aStar;
        uint256 nStar;

        uint256 maxK = Ng < Nd ? Ng : Nd;
        if (maxK > 50) maxK = 50;

        for (uint256 k = 1; k <= maxK; k++) {
            uint256 a_k   = B0 / k;
            uint256 n_k   = victim.min(k, Ng);
            uint256 gross = a_k * n_k;
            uint256 cost  = p * g0 * n_k;

            if (gross > cost) {
                uint256 net = gross - cost;
                if (net > bestProfit) {
                    bestProfit = net;
                    aStar      = a_k;
                    nStar      = n_k;
                }
            }
        }

        if (aStar == 0) {
            return AttackResult("optimized", 0, 0, 0, 0, false, 0);
        }

        // 2) execute
        vm.startPrank(attackerEOA);
        attacker.initiateAttack{value: aStar}(aStar, nStar);
        attacker.withdrawFunds();
        vm.stopPrank();

        // 3) detection & risk
        bool detected = false;
        for (uint256 i = 0; i < nStar; i++) {
            if (monitor.checkDetection(address(attacker))) {
                detected = true;
                break;
            }
        }
        uint256 risk = 1e18 - victim.pow((1e18 - alpha), nStar);

        return AttackResult({
            strategy : "optimized",
            a        : aStar,
            n        : nStar,
            profit   : bestProfit,
            gasUsed  : g0 * nStar,
            detected : detected,
            riskE18  : risk
        });
    }

    function runGreedy(
        uint256 B0,
        uint256 p,
        uint256 alpha
    ) internal returns (AttackResult memory) {
        uint256 a = B0;
        uint256 n = 1;
        uint256 gasUsed = GAS_PER_CALL * n;

        // if we can't even cover gas, bail
        if (a <= p * GAS_PER_CALL) {
            return AttackResult("greedy", a, n, 0, gasUsed, false, 0);
        }

        // run
        vm.startPrank(attackerEOA);
        attacker.initiateAttack{value: a}(a, n);
        attacker.withdrawFunds();
        vm.stopPrank();

        bool detected = false;
        for (uint256 i = 0; i < n; i++) {
            if (monitor.checkDetection(address(attacker))) {
                detected = true;
                break;
            }
        }
        uint256 gross = a * n;
        uint256 cost  = p * GAS_PER_CALL * n;
        uint256 net   = gross > cost ? gross - cost : 0;
        uint256 risk  = 1e18 - victim.pow((1e18 - alpha), n);

        return AttackResult("greedy", a, n, net, gasUsed, detected, risk);
    }

    function runUniform(
        uint256 B0,
        uint256 n,
        uint256 p,
        uint256 alpha
    ) internal returns (AttackResult memory) {
        if (n == 0) {
            return AttackResult("uniform", 0, 0, 0, 0, false, 0);
        }
        uint256 a = B0 / n;
        uint256 gasUsed = GAS_PER_CALL * n;

        // can't cover total gas?
        if (a * n <= p * gasUsed) {
            return AttackResult("uniform", a, n, 0, gasUsed, false, 0);
        }

        vm.startPrank(attackerEOA);
        attacker.initiateAttack{value: a}(a, n);
        attacker.withdrawFunds();
        vm.stopPrank();

        bool detected = false;
        for (uint256 i = 0; i < n; i++) {
            if (monitor.checkDetection(address(attacker))) {
                detected = true;
                break;
            }
        }
        uint256 gross = a * n;
        uint256 cost  = p * gasUsed;
        uint256 net   = gross > cost ? gross - cost : 0;
        uint256 risk  = 1e18 - victim.pow((1e18 - alpha), n);

        return AttackResult("uniform", a, n, net, gasUsed, detected, risk);
    }
}
