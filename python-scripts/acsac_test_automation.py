import os
import subprocess
import time
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import json
from itertools import product
from concurrent.futures import ThreadPoolExecutor, as_completed
import uuid
import numpy as np

# ---------- CONFIG ----------
TEST_COMMAND = "forge test -vv"
DATA_DIR = "logs"
CSV_OUTPUT = "acsac_results.csv"

# Parameter sweep ranges (expanded for large-scale data)
# BALANCES = np.logspace(3, 7, 15, dtype=int)  # 1e3 to 1e7 wei, 15 values
# GAS_PRICES = np.logspace(0, 3, 15, dtype=int)  # 1 to 1000 gwei, 15 values
# ALPHAS = np.linspace(0.01, 0.5, 20)  # 20 values
# DELTAS = np.linspace(0.01, 0.5, 20)  # 20 values

# Parameter sweep ranges (expanded for large-scale data)
BALANCES = np.logspace(3, 7, 5, dtype=int)  # 5 values
GAS_PRICES = np.logspace(0, 3, 5, dtype=int)  # 5 values
ALPHAS = np.linspace(0.01, 0.5, 5)  # 5 values
DELTAS = np.linspace(0.01, 0.5, 5)  # 5 values

def run_foundry_tests_with_env(alpha, delta, gas_price, victim_balance, unique_id=None):
    env = os.environ.copy()
    env["ALPHA"] = str(alpha)
    env["DELTA"] = str(delta)
    env["GAS_PRICE"] = str(gas_price)
    env["VICTIM_BALANCE"] = str(victim_balance)
    if unique_id is not None:
        env["TEST_UUID"] = unique_id
    print(f"Running test with ALPHA={alpha}, DELTA={delta}, GAS_PRICE={gas_price}, VICTIM_BALANCE={victim_balance}, UUID={unique_id}")
    result = subprocess.run(TEST_COMMAND, shell=True, check=False, env=env)
    if result.returncode != 0:
        print(f"Test failed for ALPHA={alpha}, DELTA={delta}, GAS_PRICE={gas_price}, VICTIM_BALANCE={victim_balance}, UUID={unique_id}")
    # No sleep needed in parallel mode

def collect_logs_to_csv():
    rows = []
    for fname in os.listdir(DATA_DIR):
        if fname.endswith(".json"):
            with open(os.path.join(DATA_DIR, fname)) as f:
                try:
                    data = json.load(f)
                    data["logfile"] = fname
                    rows.append(data)
                except Exception as e:
                    print(f"Error reading {fname}: {e}")
    if not rows:
        print("No logs found.")
        return
    df = pd.DataFrame(rows)
    df.to_csv(CSV_OUTPUT, index=False)
    print(f"Saved {len(df)} rows to {CSV_OUTPUT}")
    return df

def plot_summary(df):
    if df is None or df.empty:
        print("No data to plot.")
        return
    plt.figure(figsize=(10,6))
    sns.boxplot(x="strategy", y="profit", data=df)
    plt.title("Profit by Strategy")
    plt.savefig("acsac_profit_by_strategy.png")
    plt.close()

    plt.figure(figsize=(10,6))
    sns.heatmap(pd.pivot_table(df, values="profit", index="n", columns="strategy", aggfunc="mean"), annot=True)
    plt.title("Profit Heatmap (n vs. strategy)")
    plt.savefig("acsac_heatmap_profit.png")
    plt.close()

def main():
    tasks = []
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
        for balance, gas_price, alpha, delta in product(BALANCES, GAS_PRICES, ALPHAS, DELTAS):
            unique_id = str(uuid.uuid4())
            tasks.append(executor.submit(
                run_foundry_tests_with_env, alpha, delta, gas_price, balance, unique_id
            ))
        for future in as_completed(tasks):
            future.result()  # To catch exceptions if any
    df = collect_logs_to_csv()
    plot_summary(df)

if __name__ == "__main__":
    main()
