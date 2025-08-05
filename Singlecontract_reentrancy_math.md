# Single-Contract Reentrancy Attack: Mathematical Model

This README outlines the formal mathematical model used to optimize profit-maximizing reentrancy attacks against a **single vulnerable smart contract**, subject to constraints such as gas limits, detection risk, and atomic execution.

---

## 🧠 Attacker Objective

The attacker aims to maximize their **expected utility** from a reentrancy attack by choosing:
- `a`: the amount withdrawn per reentrant call
- `n`: the number of reentrant calls

---

## 📈 Utility Function

The expected profit (utility) is defined as:

GasCost(n) = g_base + n × g_recurse


Where:
- `g_base`: base gas for transaction
- `g_recurse`: additional gas per recursive call

---

## 🎯 Constraints

The optimization is subject to:

1. **Victim Balance Constraint**:

a × n ≤ B


Where `B` is the contract’s available balance.

2. **Gas Budget Constraint**:
g_base + n × g_recurse ≤ G

Where `G` is the attacker’s available gas.

3. **Atomicity**:
- All `n` calls must be executed in the same transaction (no partial execution).
- `n ∈ ℕ⁺`, `a > 0`

---

## 🔍 Optimization Goal

Find `(a*, n*)` ∈ ℝ⁺ × ℕ⁺ such that:

maximize U(a, n)
subject to:
a × n ≤ B
g_base + n × g_recurse ≤ G



Due to discrete `n`, the search space is piecewise and bounded by:

n ∈ {1, 2, ..., ⌊min(B / a, (G − g_base) / g_recurse)⌋}


We solve this using **breakpoint-based grid search** for small `n`.

---

## 📦 Outputs

- Optimal call count `n*`
- Optimal withdrawal per call `a*`
- Expected utility `U(a*, n*)`

---

For full details and implementation, see the paper:  
**"Profit-Maximizing Reentrancy Attacks: A Formal Model of Exploitation under Detection, Gas, and Atomicity Constraints"**

