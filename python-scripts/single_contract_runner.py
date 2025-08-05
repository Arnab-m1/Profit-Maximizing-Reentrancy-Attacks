import os
import subprocess
import pandas as pd
import json
import numpy as np
from itertools import product
from concurrent.futures import ThreadPoolExecutor, as_completed
import uuid
import time
from tqdm import tqdm

# ---------------- CONFIG ----------------                # <== edit only this section
TEST_COMMAND  = "forge test --match-path test/Test.t.sol -vv"

DATA_DIR      = "logs"           # where JSON results are written
CSV_OUTPUT    = "results_single_contract.csv"

# Contract balances to pre-fund the victim with (wei)
BALANCES      = [
    int(10e18),    # 10  ETH
    int(50e18),    # 50  ETH
    int(100e18),   # 100 ETH
    int(200e18)
    ]
   

# Gas-price sweep (wei per gas)
GAS_PRICES    = [
    int(10e9),     # 10  gwei
    int(20e9),     # 20  gwei
    int(50e9),     # 50  gwei
    int(100e9),    # 100 gwei
    int(200e9)
    ]

# Per-call detection probability α  (0.01 → 0.15 in 1 percent steps)
ALPHAS        = np.linspace(0.01, 0.15, 15)

# Maximum cumulative detection risk δ (0.05 → 0.30 in 20 linear steps)
DELTAS        = np.linspace(0.05, 0.30, 20)
# -------------------------------------------------------  # end config


# ---------------- Foundry Execution ----------------
def run_foundry_test(params):
    alpha, delta, gas_price, victim_balance, unique_id = params
    env = os.environ.copy()
    env["ALPHA"] = str(int(alpha * 1e18))
    env["DELTA"] = str(int(delta * 1e18))
    env["GAS_PRICE"] = str(gas_price)
    env["VICTIM_BALANCE"] = str(victim_balance)
    env["TEST_UUID"] = unique_id

    result = subprocess.run(TEST_COMMAND, shell=True, env=env, capture_output=True, text=True)

    if result.returncode != 0:
        return {'status': 'failed', 'uuid': unique_id, 'stderr': result.stderr}

    return {'status': 'completed', 'uuid': unique_id}

# ---------------- Log Aggregation ----------------
def collect_logs():
    print("\nCollecting logs...")
    if not os.path.exists(DATA_DIR):
        print(f"⚠️ Data directory {DATA_DIR} not found.")
        return None

    rows = []
    log_files = [f for f in os.listdir(DATA_DIR) if f.endswith(".json")]

    if not log_files:
        print("⚠️ No valid log files found.")
        return None

    for fname in tqdm(log_files, desc="Aggregating Logs"):
        try:
            with open(os.path.join(DATA_DIR, fname), 'r') as f:
                data = json.load(f)
            uuid_part = fname.split("_")[-1].replace(".json", "")
            data["logfile"] = fname
            data["uuid"] = uuid_part
            rows.append(data)
        except Exception as e:
            print(f"[ERROR] Reading {fname}: {e}")

    if not rows:
        print("⚠️ No valid data rows could be aggregated.")
        return None

    df = pd.DataFrame(rows)
    df.to_csv(CSV_OUTPUT, index=False)
    print(f"✅ Saved {len(df.index)} rows to {CSV_OUTPUT}")
    return df



# ---------------- Summary Statistics ----------------
def print_summary_statistics(df):
    if df is None or df.empty:
        return

    # A list of possible names for the detection risk column
    possible_risk_columns = ['detection_risk', 'riskE18', 'total_risk']
    
    # Find which risk column actually exists in the DataFrame
    risk_col_name = None
    for col in possible_risk_columns:
        if col in df.columns:
            risk_col_name = col
            break

    if risk_col_name is None:
        print("\n⚠️  Could not find a detection risk column to analyze.")
        return

    # Ensure all relevant numeric columns are correctly typed
    for col in ['profit', risk_col_name, 'gas_used', 'a', 'n']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    df['profit_eth'] = df['profit'] / 1e18
    # Use the dynamically found risk column name
    df['risk_pct']   = df[risk_col_name] / 1e18

    print("\n" + "="*80)
    print("SINGLE-CONTRACT REENTRANCY ATTACK ANALYSIS SUMMARY")
    print("="*80)
    print(f"📊 Total test results analyzed: {len(df.index)}")
    
    if 'strategy' in df.columns:
        strategies = df['strategy'].unique()
        print(f"🎯 Strategies tested: {', '.join(strategies)}")
        
        if 'profit_eth' in df.columns:
            print("\n💰 Strategy Performance (Average Profit in ETH):")
            strategy_stats = df.groupby('strategy')['profit_eth'].agg(['mean', 'std', 'max']).fillna(0)
            print(strategy_stats.to_string(float_format="%.4f"))

    if 'detected' in df.columns:
        df['detected_bool'] = df['detected'].apply(lambda x: str(x).lower() == 'true')
        print(f"\n🔍 Overall detection rate: {df['detected_bool'].mean():.2%}")
        
    print("\n" + "-"*80)
    print("💡 INSIGHTS: BEST ATTACK PERFORMANCES")
    print("-" * 80)

    best_profit_run = df.loc[df['profit'].idxmax()]
    print("\n🏆 HIGHEST PROFIT RUN:")
    print(f"   - Strategy: {best_profit_run['strategy']}")
    print(f"   - Profit: {best_profit_run['profit_eth']:.4f} ETH")
    print(f"   - Calls (n): {int(best_profit_run['n'])}")
    print(f"   - Risk: {best_profit_run['risk_pct']:.2%}")

    df['profit_to_risk'] = df['profit_eth'] / df['risk_pct']
    df_safe = df[df['risk_pct'] > 0]
    if not df_safe.empty:
        best_ratio_run = df_safe.loc[df_safe['profit_to_risk'].idxmax()]
        print("\n🤫 MOST RISK-EFFICIENT RUN (Profit per 1% Risk):")
        print(f"   - Strategy: {best_ratio_run['strategy']}")
        print(f"   - Profit-to-Risk Ratio: {best_ratio_run['profit_to_risk'] / 100:.4f} ETH / 1% risk")
        print(f"   - Actual Profit: {best_ratio_run['profit_eth']:.4f} ETH")
        print(f"   - Actual Risk: {best_ratio_run['risk_pct']:.2%}")

    print("\n" + "="*80)

# ---------------- Main Batch Driver ----------------
def main():
    print("🚀 Starting Single-Contract Reentrancy Attack Analysis")
    print("="*60)
    os.makedirs(DATA_DIR, exist_ok=True)

    param_combinations = list(product(ALPHAS, DELTAS, GAS_PRICES, BALANCES))
    total_tests = len(param_combinations)
    print(f"\n🔧 Generated {total_tests} test configurations...")

    tasks_to_submit = [params + (str(uuid.uuid4()),) for params in param_combinations]
    
    completed_count = 0
    failed_count = 0
    start_time = time.time()

    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
        future_to_params = {executor.submit(run_foundry_test, task): task for task in tasks_to_submit}

        for future in as_completed(future_to_params):
            completed_total = completed_count + failed_count
            elapsed = time.time() - start_time
            avg_time_per_test = elapsed / (completed_total + 1)
            remaining_tests = total_tests - (completed_total + 1)
            eta_seconds = int(remaining_tests * avg_time_per_test)
            mins, secs = divmod(eta_seconds, 60)
            time_str = f" [est. {mins}m{secs}s left]"

            params = future_to_params[future]
            alpha, delta, gas_price, balance, unique_id = params

            print(
                f"[RUNNING] Test ({completed_total + 1}/{total_tests}){time_str} - "
                f"Balance={balance}, GasPrice={gas_price}, α={alpha:.3f}, δ={delta:.3f}, "
                f"UUID={unique_id[:8]}"
            )

            try:
                result = future.result()
                if result['status'] == 'completed':
                    completed_count += 1
                elif result['status'] == 'failed':
                    failed_count += 1
            except Exception as e:
                failed_count += 1
                print(f"\n[ERROR] An exception occurred for UUID {unique_id}: {e}")

    print(f"\n\n✅ Test execution completed: {completed_count} successful, {failed_count} failed.")

    df = collect_logs()
    print_summary_statistics(df)
    
    print("\n🎉 Single-Contract Analysis Complete!")

# ---------------- Entry ----------------
if __name__ == "__main__":
    main()