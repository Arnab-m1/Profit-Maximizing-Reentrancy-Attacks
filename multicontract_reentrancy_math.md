# Multi-Contract Reentrancy Attack: Mathematical Model

This document describes the mathematical model and optimization problem underlying the multi-contract reentrancy attack simulation and analysis, as implemented in `MultiContractTest.t.sol` (Solidity) and `multi_contract_runner.py` (Python).

## Problem Setting

- There are $N$ victim contracts, each with balance $B_i$.
- The attacker can perform $n_i$ reentrant calls to each victim $i$, withdrawing $a_i$ per call.
- Each call incurs a gas cost $g_i(a_i)$ and a per-call detection risk $\alpha$.
- The attacker has a total gas budget $G$ and faces a cumulative detection risk constraint $\Delta$.
- The attacker seeks to maximize profit while minimizing detection risk, possibly trading off between the two.

## Variables

- $N$: Number of victim contracts
- $B_i$: Balance of victim $i$
- $a_i$: Amount withdrawn per call from victim $i$
- $n_i$: Number of calls to victim $i$
- $g_i(a_i)$: Gas used per call to victim $i$ (typically $g_0[i] + g_1[i] \cdot a_i$)
- $G$: Total gas budget
- $gp$: Gas price (in wei)
- $\alpha$: Per-call detection probability (risk)
- $\Delta$: Maximum allowed cumulative detection risk
- $\lambda_{risk}$: Tradeoff parameter for risk in the utility function

## Objective Function

The attacker seeks to maximize a utility function that trades off profit and detection risk:

\[
\text{Utility} = \text{Profit} - \lambda_{risk} \cdot \text{CumulativeRisk}
\]

where

\[
\text{Profit} = \sum_{i=1}^N \left[ a_i n_i - gp \cdot n_i \cdot g_i(a_i) \right]
\]

and

\[
\text{CumulativeRisk} = 1 - \prod_{i=1}^N (1 - \alpha)^{n_i}
\]

## Constraints

1. **Balance constraint:**
   \[
   a_i n_i \leq B_i \quad \forall i
   \]
2. **Gas constraint:**
   \[
   \sum_{i=1}^N n_i \cdot g_i(a_i) \leq G
   \]
3. **Detection risk constraint:**
   \[
   1 - \prod_{i=1}^N (1 - \alpha)^{n_i} \leq \Delta
   \]
4. **Atomicity:**
   All calls must fit in a single transaction (enforced by the gas constraint).

## Optimization Approach

- For each victim $i$, generate breakpoints for $a_i$ (e.g., $a_i = B_i / k$ for $k = 1, \ldots, K$).
- For each combination $(a_1, \ldots, a_N)$, compute the maximum feasible $n_i$ for each victim under all constraints.
- Evaluate the utility for each feasible configuration and select the one with the highest utility.

## Baseline Strategies

### Sequential
- For each victim $i$, withdraw the full balance in $n_i = 2$ calls (i.e., $a_i = B_i / 2$, $n_i = 2$).
- This increases detection risk compared to a single call, but is still less aggressive than parallel.

### Parallel
- For each victim $i$, withdraw in $n_i = 5$ calls of $a_i = B_i / 10$ each.
- This maximizes the number of calls (and thus detection risk), but each call is small.

### Optimized
- The optimized strategy solves the above utility maximization problem, choosing $a_i$ and $n_i$ for each victim to maximize profit minus risk penalty, subject to all constraints.

## Summary Table

| Strategy    | $a_i$ per victim         | $n_i$ per victim | Risk Profile         |
|-------------|--------------------------|------------------|---------------------|
| Sequential  | $B_i / 2$                | $2$              | Moderate            |
| Parallel    | $B_i / 10$               | $5$              | High                |
| Optimized   | Variable (solved)        | Variable (solved)| Tuned (max utility) |

## Notes
- The per-call detection risk $\alpha$ and cumulative risk $\Delta$ are typically set as environment variables.
- The optimizer can be tuned via $\lambda_{risk}$ to prioritize profit or stealth.
- All strategies are executed atomically in a single transaction, subject to the EVM gas limit.
