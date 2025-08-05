# Profit-Maximizing Reentrancy Attack Simulation

This repository implements a simulation framework based on the paper:

**Profit-Maximizing Reentrancy Attacks: A Formal Model of Exploitation under Detection, Gas, and Atomicity Constraints**

The codebase models, simulates, and analyzes reentrancy attacks on smart contracts, considering detection, gas, and atomicity constraints. It provides tools to reproduce the paper's results and visualize the attacker's profit landscape.

---

## Table of Contents
- [Overview](#overview)
- [Main Components](#main-components)
- [How It Works](#how-it-works)
- [Results and Graphs](#results-and-graphs)
- [Usage](#usage)
- [Dependencies](#dependencies)

---

## Overview

This project simulates reentrancy attacks on Ethereum smart contracts, focusing on maximizing attacker profit under realistic constraints. It models both the attacker and the victim, simulates attack scenarios, and analyzes outcomes. The results help understand the optimal strategies and the impact of various parameters (e.g., detection probability, gas limits).

---

## Main Components

- `src/attacker2.py`: Implements the attacker's logic and profit calculation.
- `src/victim2.py`: Models the vulnerable contract and its response to attacks.
- `src/a_runner.py`: Orchestrates the simulation, running attacker and victim models together.
- `test/test.t.sol`: Solidity test suite for validating the smart contract logic.
- `logs/`: Stores JSON logs of simulation runs for later analysis.
- `result/`: Contains output data and graphs from simulation runs (see below).

---

## How It Works

1. **Setup**: Configure simulation parameters (detection probability, gas limits, etc.).
2. **Simulation**: `a_runner.py` runs the attack scenario using `attacker2.py` and `victim2.py`.
3. **Logging**: Results are saved as JSON in the `logs/` directory for traceability.
4. **Analysis**: Output data is processed to generate graphs and summary statistics, stored in `result/`.
5. **Testing**: Solidity tests in `test/test.t.sol` ensure correctness of the contract logic.

---

## Results and Graphs

The `result/` directory contains:
- **Mathematical Results**: Data files summarizing simulation outcomes (e.g., optimal number of calls, expected profit).
- **Graphs**: Visualizations (e.g., profit vs. number of calls, detection probability curves) that reproduce figures from the paper.

**How to interpret:**
- The graphs show how the attacker's profit varies with different parameters.
- Use these to compare with the theoretical predictions in the paper.

---

## Usage

### 1. Install Dependencies
```bash
pip install -r requirements.txt
```

### 2. Run the Simulation
```bash
python3 src/a_runner.py
```

- Adjust parameters in the script or via command-line arguments as needed.
- Simulation logs will be saved in `logs/`.

### 3. Analyze Results
- Processed results and graphs will appear in `result/`.
- Review the output files and visualizations to interpret the findings.

### 4. Run Solidity Tests
If you have Foundry installed:
```bash
forge test
```
This runs the tests in `test/test.t.sol` to validate contract behavior.

---

## Foundry Installation

To install [Foundry](https://getfoundry.sh/) (required for Solidity testing):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

This will install the `forge` and `cast` tools. For more details, see the [Foundry Book](https://book.getfoundry.sh/).

---

## Dependencies
- Python 3.8+
- See `requirements.txt` for Python packages
- [Foundry](https://getfoundry.sh/) (for Solidity testing)

---

## References
- [Profit-Maximizing Reentrancy Attacks: A Formal Model of Exploitation under Detection, Gas, and Atomicity Constraints](https://arxiv.org/)

---

For questions or contributions, please open an issue or pull request.

