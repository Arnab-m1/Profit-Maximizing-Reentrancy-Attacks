import os
import subprocess
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

BALANCES = np.logspace(3, 7, 5, dtype=int)       # 1e3 to 1e7 wei
GAS_PRICES = np.logspace(0, 3, 5, dtype=int)     # 1 to 1000 gwei
ALPHAS = np.linspace(0.01, 0.5, 5)               # per-call risk
DELTAS = np.linspace(0.01, 0.5, 5)               # max total risk

def run_foundry_tests_with_env(alpha, delta, gas_price, victim_balance, unique_id=None):
    env = os.environ.copy()
    env["ALPHA"] = str(int(alpha * 1e18))
    env["DELTA"] = str(int(delta * 1e18))
    env["GAS_PRICE"] = str(gas_price)
    env["VICTIM_BALANCE"] = str(victim_balance)
    if unique_id is not None:
        env["TEST_UUID"] = unique_id
    print(f"[RUNNING] ALPHA={alpha:.3f}, DELTA={delta:.3f}, GAS_PRICE={gas_price}, BALANCE={victim_balance}, UUID={unique_id}")
    result = subprocess.run(TEST_COMMAND, shell=True, check=False, env=env)
    if result.returncode != 0:
        print(f"[FAILED] UUID={unique_id}")

def collect_logs_to_csv():
    print("Collecting logs into CSV...")
    rows = []
    for fname in os.listdir(DATA_DIR):
        if not fname.endswith(".json"):
            continue
        try:
            with open(os.path.join(DATA_DIR, fname), "r") as f:
                data = json.load(f)
                uuid_part = fname.split("_")[-1].replace(".json", "")
                data["logfile"] = fname
                data["uuid"] = uuid_part

                # Safely attempt to read test params from JSON (if logged by Solidity)
                for param in ["alpha", "delta", "gas_price", "victim_balance"]:
                    if param not in data:
                        data[param] = None  # placeholder if missing

                rows.append(data)
        except Exception as e:
            print(f"Error reading {fname}: {e}")

    if not rows:
        print("No valid logs found.")
        return

    df = pd.DataFrame(rows)
    df.to_csv(CSV_OUTPUT, index=False)
    print(f"✅ Saved {len(df)} rows to {CSV_OUTPUT}")
    return df


def plot_summary(df):
    if df is None or df.empty:
        print("No data to plot.")
        return

    sns.set(style="whitegrid", font_scale=1.1)

    # Profit distribution
    plt.figure(figsize=(8, 5))
    sns.boxplot(x="strategy", y="profit", data=df, hue="strategy", palette="Set2", legend=False)
    plt.title("Profit by Strategy")
    plt.savefig("acsac_profit_by_strategy.png")
    plt.close()

    # Profit vs. Gas Used
    plt.figure(figsize=(8, 5))
    sns.scatterplot(data=df, x="gas_used", y="profit", hue="strategy", palette="Set1")
    plt.title("Profit vs Gas Used")
    plt.savefig("acsac_profit_vs_gas.png")
    plt.close()

    # Heatmap: n vs strategy
    if "n" in df.columns:
        heatmap_data = pd.pivot_table(df, values="profit", index="n", columns="strategy", aggfunc="mean")
        plt.figure(figsize=(8, 5))
        sns.heatmap(heatmap_data, annot=True, fmt=".1f", cmap="YlGnBu")
        plt.title("Profit Heatmap: n vs Strategy")
        plt.savefig("acsac_heatmap_profit.png")
        plt.close()

    # Detection risk vs strategy
    if "detection_risk" in df.columns:
        plt.figure(figsize=(8, 5))
        sns.boxplot(data=df, x="strategy", y="detection_risk", hue="strategy", palette="coolwarm", legend=False)
        plt.title("Detection Risk by Strategy")
        plt.ylabel("Detection Risk (%)")
        plt.savefig("acsac_detection_risk_by_strategy.png")
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
            future.result()  # catch exceptions

    df = collect_logs_to_csv()
    plot_summary(df)

if __name__ == "__main__":
    main()
