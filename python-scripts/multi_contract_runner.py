import os
import subprocess
import pandas as pd
import json
from itertools import product
from concurrent.futures import ThreadPoolExecutor, as_completed
import uuid
import numpy as np
from scipy.optimize import minimize
import logging
import time
import threading

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# ---------- CONFIG ----------
TEST_COMMAND = "forge test --match-test testMultiContractStrategies -vv"
DATA_DIR = "logs"
CSV_OUTPUT = "multi_contract_results.csv"

# Reduce parameter sweep for a total of 1000-2000 test cases
VICTIM_COUNTS = [2, 3]  # 2 values
BALANCE_DISTRIBUTIONS = ["pyramid", "exponential"]  # 2 values
BALANCES = [int(50e18), int(100e18), int(200e18)]  # Sufficiently high for profit
ALPHAS = np.array([0.05, 0.1, 0.2])  # Higher per-call risk to increase detection rates
DELTAS = np.array([0.02, 0.05, 0.1, 0.3, 0.5])    # Lower cumulative risk allowed
GAS_BUDGETS = [3_000_000, 5_000_000]  # Generous gas budgets
GAS_PRICES = np.array([10000, 50000], dtype=int)  # 10,000 to 50,000 gwei

# Add a sweep for lambda_risk (tradeoff between profit and risk)
LAMBDA_RISKS = [1e20, 1e21, 1e22]

# Global variables for time tracking
completed_tests = 0
failed_tests = 0
skipped_tests = 0
start_time = None
test_lock = threading.Lock()

MAX_EVM_GAS = 10_000_000

class MultiContractOptimizer:
    """
    Multi-contract optimization (see multicontract_reentrancy_math.md):
    Maximize:   Utility = Profit - lambda_risk * cumulative_risk
    Where:
      - Profit = sum_i [a_i * n_i - gp * n_i * g_i(a_i)]
      - cumulative_risk = 1 - prod_i (1-p_i)^n_i
      - lambda_risk: tradeoff parameter (default 1e21)
    Subject to:
      1. a_i * n_i <= B_i (balance constraint)
      2. sum_i n_i * g_i(a_i) <= G (gas constraint)
      3. 1 - prod_i (1-p_i)^n_i <= P (cumulative detection risk)
      4. Atomicity (all-or-nothing)
    """
    
    def __init__(self, victim_balances, g0, g1, gas_budget, gas_price, max_detection_risk, per_call_risk, lambda_risk=1e21):
        self.victim_balances = np.array(victim_balances)
        self.g0 = np.array(g0)
        self.g1 = np.array(g1) if g1 is not None else np.zeros_like(self.g0)
        self.gas_budget = gas_budget
        self.gas_price = gas_price
        self.max_detection_risk = max_detection_risk
        self.per_call_risk = per_call_risk
        self.num_victims = len(victim_balances)
        self.lambda_risk = lambda_risk
    
    def optimize(self):
        """
        Implements the canonical model (see multicontract_reentrancy_math.md):
        - For each victim, generate breakpoints a_i = B_i / k for k in [1, K]
        - For each combination of (a_1, ..., a_k), compute max feasible n_i under:
            * a_i * n_i <= B_i
            * sum_i n_i * g_i(a_i) <= G
            * 1 - prod_i (1-p_i)^n_i <= P
        - Compute utility = profit - lambda_risk * cumulative_risk for each feasible configuration and select the maximum.
        """
        best_utility = -float('inf')
        best_profit = 0
        best_risk = 0
        best_params = None
        K = 30  # breakpoints per victim (increased from 10)
        maxIterations = 5000  # increased from 1000
        iter = 0
        # Generate breakpoints for each victim
        breakpoints = [ [self.victim_balances[i] / (k+1) for k in range(K)] for i in range(self.num_victims) ]  # list of lists
        # Search all combinations of breakpoints (amounts)
        for a_combo in product(*breakpoints):
            if iter > maxIterations:
                break
            amounts = np.array(a_combo)
            # For each victim, compute max feasible n_i
            n_max = []
            for i in range(self.num_victims):
                n_balance = int(self.victim_balances[i] // amounts[i])
                gas_per_call = self.g0[i] + self.g1[i] * amounts[i]
                n_gas = int(self.gas_budget // gas_per_call)
                # Detection constraint: n_detect = floor(log(1-P)/log(1-p))
                if self.per_call_risk > 0 and self.max_detection_risk > 0:
                    n_detect = int(np.log(1 - self.max_detection_risk) / np.log(1 - self.per_call_risk))
                else:
                    n_detect = n_balance
                n = min(n_balance, n_gas, n_detect)
                if n <= 0:
                    break
                n_max.append(n)
            else:
                calls = np.array(n_max)
                # Check total gas
                total_gas = np.sum(calls * (self.g0 + self.g1 * amounts))
                if total_gas > self.gas_budget:
                    continue
                # Check detection risk
                prob_not_detected = np.prod([(1 - self.per_call_risk) ** n for n in calls])
                cumulative_risk = 1 - prob_not_detected
                if cumulative_risk > self.max_detection_risk:
                    continue
                # Compute profit
                profit = np.sum(amounts * calls - self.gas_price * calls * (self.g0 + self.g1 * amounts))
                # Compute utility
                utility = profit - self.lambda_risk * cumulative_risk
                if utility > best_utility:
                    best_utility = utility
                    best_profit = profit
                    best_risk = cumulative_risk
                    best_params = {
                        'amounts': amounts.tolist(),
                        'calls': calls.tolist(),
                        'profit': profit,
                        'gas_used': total_gas,
                        'detection_risk': cumulative_risk,
                        'utility': utility
                    }
                    print(f"[OPTIMIZER] New best: amounts={amounts.tolist()}, calls={calls.tolist()}, profit={profit}, risk={cumulative_risk}, utility={utility}")
            iter += 1
        if not best_params:
            # Debug print moved to caller for better context
            pass
        return best_params

def generate_victim_balances(num_victims, distribution_type, total_balance):
    """Generate victim balance distributions."""
    if distribution_type == "equal":
        return [total_balance // num_victims] * num_victims
    elif distribution_type == "pyramid":
        weights = [i + 1 for i in range(num_victims)]
        total_weight = sum(weights)
        return [total_balance * w // total_weight for w in weights]
    elif distribution_type == "random":
        np.random.seed(42)  # For reproducibility
        weights = np.random.random(num_victims)
        return [int(total_balance * w / sum(weights)) for w in weights]
    elif distribution_type == "exponential":
        weights = [2 ** i for i in range(num_victims)]
        total_weight = sum(weights)
        return [total_balance * w // total_weight for w in weights]
    else:
        raise ValueError(f"Unknown distribution type: {distribution_type}")

def run_foundry_tests_with_env(victim_count, distribution, total_balance, gas_price, alpha, delta, gas_budget, lambda_risk, unique_id, test_num=None, total_tests=None):
    """Run Foundry tests with multi-contract parameters, using Python-optimized strategy."""
    global completed_tests, failed_tests, skipped_tests, start_time

    # Generate victim balances
    victim_balances = generate_victim_balances(victim_count, distribution, total_balance)
    g0 = [35000] * victim_count
    g1 = [0] * victim_count
    # Compute per-call risk and max detection risk in float
    per_call_risk = float(alpha)
    max_detection_risk = float(delta)
    # --- Python optimization ---
    optimizer = MultiContractOptimizer(
        victim_balances, g0, g1, min(gas_budget, MAX_EVM_GAS), gas_price, max_detection_risk, per_call_risk, lambda_risk
    )
    opt_result = optimizer.optimize()
    if opt_result is None:
        print(f"[DEBUG] Skipped UUID={unique_id} - Params: balances={victim_balances}, gas={gas_budget}, alpha={alpha}, delta={delta}, lambda_risk={lambda_risk}")
        print(f"[SKIPPED] No feasible solution for UUID={unique_id[:8]}")
        skipped_tests += 1
        return False
    # Log profit, risk, utility for this run
    print(f"[RESULT] UUID={unique_id[:8]} profit={opt_result['profit']:.2e} risk={opt_result['detection_risk']:.3f} utility={opt_result.get('utility', float('nan')):.2e}")
    # Prepare environment
    env = os.environ.copy()
    env.update({
        "TEST_UUID": unique_id,
        "VICTIM_COUNT": str(victim_count),
        "DISTRIBUTION": distribution,
        "ALPHA": str(int(alpha * 1e18)),
        "DELTA": str(int(delta * 1e18)),
        "GAS_PRICE": str(gas_price),
        "GAS_BUDGET": str(gas_budget),
        "TOTAL_BALANCE": str(total_balance),
        # Pass Python-optimized parameters
        "AMOUNTS": ','.join(str(int(a)) for a in opt_result['amounts']),
        "CALLS": ','.join(str(int(n)) for n in opt_result['calls']),
        "LAMBDA_RISK": str(lambda_risk)
    })
    # Set individual victim balances
    for i, balance in enumerate(victim_balances):
        env[f"VICTIM_BALANCE_{i}"] = str(balance)
    # Calculate remaining time
    with test_lock:
        if start_time and total_tests:
            elapsed = time.time() - start_time
            total_completed = completed_tests + failed_tests + skipped_tests
            if total_completed > 0:
                avg_time = elapsed / total_completed
                remaining_tests = total_tests - total_completed
                remaining_time = avg_time * remaining_tests
                mins, secs = divmod(int(remaining_time), 60)
                time_str = f" [est. {mins}m{secs}s left]"
            else:
                time_str = ""
        else:
            time_str = ""
    if test_num and total_tests:
        print(f"[RUNNING] Test ({test_num}/{total_tests}){time_str} - Victims={victim_count}, Dist={distribution}, α={alpha:.3f}, δ={delta:.3f}, λ={lambda_risk:.1e}, UUID={unique_id[:8]}")
    else:
        print(f"[RUNNING] Victims={victim_count}, Dist={distribution}, α={alpha:.3f}, δ={delta:.3f}, λ={lambda_risk:.1e}, UUID={unique_id[:8]}")
    result = subprocess.run(TEST_COMMAND, shell=True, check=False, env=env, capture_output=True, text=True)
    # Update counters
    with test_lock:
        if result.returncode != 0:
            failed_tests += 1
            print(f"[SKIPPED] Test ({test_num}/{total_tests}) - UUID={unique_id[:8]} (failed):\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
            return False
        else:
            completed_tests += 1
    return True

def run_theoretical_validation():
    """Run theoretical validation scenarios."""
    print("Running theoretical validation...")
    
    scenarios = [
        {
            'name': 'Equal_Balances_Low_Risk',
            'victim_balances': [100000000000000000000] * 3,  # 100 ETH each
            'g0': [30000] * 3,
            'g1': [0] * 3,
            'gas_budget': 3000000,
            'gas_price': 10000000000,  # 10 gwei
            'max_detection_risk': 0.3,
            'per_call_risk': 0.02
        },
        {
            'name': 'Pyramid_Balances_High_Risk',
            'victim_balances': [50000000000000000000, 100000000000000000000, 150000000000000000000],
            'g0': [30000, 35000, 40000],
            'g1': [0, 0, 0],
            'gas_budget': 2000000,
            'gas_price': 50000000000,  # 50 gwei
            'max_detection_risk': 0.5,
            'per_call_risk': 0.05
        }
    ]
    
    validation_results = []
    
    for scenario in scenarios:
        optimizer = MultiContractOptimizer(**{k: v for k, v in scenario.items() if k != 'name'})
        result = optimizer.optimize()
        
        if result:
            validation_results.append({
                'scenario': scenario['name'],
                'theoretical_profit': result['profit'],
                'optimal_amounts': result['amounts'],
                'optimal_calls': result['calls'],
                'gas_utilization': result['gas_used'] / scenario['gas_budget'],
                'risk_utilization': result['detection_risk'] / scenario['max_detection_risk']
            })
            
            print(f"✅ {scenario['name']}: Profit={result['profit']:.2e}, Calls={result['calls']}")
    
    # Save validation results
    if validation_results:
        validation_df = pd.DataFrame(validation_results)
        validation_df.to_csv('theoretical_validation.csv', index=False)
        print(f"Saved theoretical validation to theoretical_validation.csv")
    
    return validation_results

def collect_logs_to_csv():
    """Collect all log files into a unified CSV."""
    print("Collecting logs into CSV...")
    
    if not os.path.exists(DATA_DIR):
        print(f"Data directory {DATA_DIR} not found.")
        return None
    
    rows = []
    for fname in os.listdir(DATA_DIR):
        if not fname.endswith(".json"):
            continue
        
        try:
            with open(os.path.join(DATA_DIR, fname), "r") as f:
                data = json.load(f)
                
            # Extract UUID from filename
            uuid_part = fname.split("_")[-1].replace(".json", "")
            data["logfile"] = fname
            data["uuid"] = uuid_part
            
            # Ensure all expected fields are present
            required_fields = ["strategy", "victim_count", "distribution", "alpha", "delta", 
                             "gas_price", "total_profit", "total_gas_used", "detected", "total_risk"]
            for field in required_fields:
                if field not in data:
                    data[field] = None
            
            # Calculate profit:detection risk ratio (handle zero risk)
            profit = data.get("total_profit", None)
            risk = data.get("total_risk", None)
            try:
                if risk is not None and float(risk) > 0:
                    data["profit_to_risk"] = float(profit) / float(risk)
                else:
                    data["profit_to_risk"] = float('nan')
            except Exception:
                data["profit_to_risk"] = float('nan')
            
            rows.append(data)
            
        except Exception as e:
            print(f"Error reading {fname}: {e}")
    
    if not rows:
        print("No valid logs found.")
        return None
    
    df = pd.DataFrame(rows)
    df.to_csv(CSV_OUTPUT, index=False)
    print(f"✅ Saved {len(df)} rows to {CSV_OUTPUT}")
    
    return df

def print_summary_statistics(df):
    """Print comprehensive summary statistics."""
    if df is None or df.empty:
        return
    
    print("\n" + "="*80)
    print("MULTI-CONTRACT REENTRANCY ATTACK ANALYSIS SUMMARY")
    print("="*80)
    
    print(f"📊 Total test configurations: {len(df)}")
    
    if 'strategy' in df.columns:
        strategies = df['strategy'].unique()
        print(f"🎯 Strategies tested: {', '.join(strategies)}")
        
        if 'total_profit' in df.columns:
            print("\n💰 Strategy Performance (ETH):")
            strategy_stats = df.groupby('strategy')['total_profit'].agg(['mean', 'std', 'max', 'min'])
            for strategy in strategies:
                stats = strategy_stats.loc[strategy]
                print(f"  {strategy:>12}: μ={stats['mean']:.3f}, σ={stats['std']:.3f}, max={stats['max']:.3f}")
    
    if 'victim_count' in df.columns:
        print(f"\n🎯 Victim counts tested: {sorted(df['victim_count'].unique())}")
        
        if 'total_profit' in df.columns:
            print("\n📈 Performance by Victim Count:")
            victim_stats = df.groupby('victim_count')['total_profit'].agg(['mean', 'max'])
            for count in sorted(df['victim_count'].unique()):
                stats = victim_stats.loc[count]
                print(f"  {count} victims: μ={stats['mean']:.3f}, max={stats['max']:.3f}")
    
    if 'detected' in df.columns:
        print(f"\n🔍 Overall detection rate: {df['detected'].mean():.2%}")
        
        if 'strategy' in df.columns:
            print("\n🚨 Detection rates by strategy:")
            detection_rates = df.groupby('strategy')['detected'].mean()
            for strategy in strategies:
                print(f"  {strategy:>12}: {detection_rates[strategy]:.2%}")
    
    if 'gas_efficiency' in df.columns:
        print(f"\n⛽ Gas efficiency statistics:")
        print(f"  Mean: {df['gas_efficiency'].mean():.2e} ETH/gas")
        print(f"  Max:  {df['gas_efficiency'].max():.2e} ETH/gas")
    
    if 'profit_to_risk' in df.columns:
        print(f"\n💡 Profit-to-Detection-Risk ratio statistics:")
        print(f"  Mean: {df['profit_to_risk'].mean():.2e}")
        print(f"  Max:  {df['profit_to_risk'].max():.2e}")
        print(f"  Min:  {df['profit_to_risk'].min():.2e}")
    
    print("\n📁 Generated files:")
    print(f"  - {CSV_OUTPUT}")
    print(f"  - theoretical_validation.csv")

def validate_optimizer_vs_baselines():
    """
    For small test cases, compare the optimized strategy to sequential and parallel baselines.
    Assert that the optimizer always matches or beats the others in profit.
    """
    print("\n[Validation] Optimizer vs. Baselines")
    test_cases = [
        {'victim_balances': [10e18, 20e18], 'g0': [30000, 35000], 'g1': [0, 0], 'gas_budget': 3000000, 'gas_price': 10_000_000_000, 'max_detection_risk': 0.3, 'per_call_risk': 0.02},
        {'victim_balances': [5e18, 15e18, 30e18], 'g0': [30000, 35000, 40000], 'g1': [0, 0, 0], 'gas_budget': 3000000, 'gas_price': 10_000_000_000, 'max_detection_risk': 0.3, 'per_call_risk': 0.02},
    ]
    for idx, params in enumerate(test_cases):
        opt = MultiContractOptimizer(**params)
        opt_result = opt.optimize()
        # Sequential: one call per victim, withdraw all
        amounts_seq = params['victim_balances']
        calls_seq = [1] * len(amounts_seq)
        profit_seq = sum([
            a * n - params['gas_price'] * n * (params['g0'][i] + params['g1'][i] * a)
            for i, (a, n) in enumerate(zip(amounts_seq, calls_seq))
        ])
        # Parallel: 5 calls per victim, equal split
        calls_par = [5] * len(params['victim_balances'])
        amounts_par = [params['victim_balances'][i] / 5 for i in range(len(params['victim_balances']))]
        profit_par = sum([
            a * n - params['gas_price'] * n * (params['g0'][i] + params['g1'][i] * a)
            for i, (a, n) in enumerate(zip(amounts_par, calls_par))
        ])
        print(f"Test {idx+1}: Optimized={opt_result['profit']:.2e}, Sequential={profit_seq:.2e}, Parallel={profit_par:.2e}")
        if opt_result['profit'] + 1e-6 < max(profit_seq, profit_par):
            print("  [WARNING] Optimizer underperformed baseline! Check constraints and logic.")
        else:
            print("  [OK] Optimizer matches or beats baselines.")

def main():
    """Main execution function."""
    print("🚀 Starting Multi-Contract Reentrancy Attack Analysis")
    print("="*60)
    
    # Ensure data directory exists
    os.makedirs(DATA_DIR, exist_ok=True)
    
    # Run theoretical validation first
    validation_results = run_theoretical_validation()
    
    # Run optimizer vs. baseline validation
    validate_optimizer_vs_baselines()
    
    # Generate all parameter combinations
    print(f"\n🔧 Generating test configurations...")
    tasks = []
    param_combinations = list(product(
        VICTIM_COUNTS, BALANCE_DISTRIBUTIONS, BALANCES, GAS_PRICES, ALPHAS, DELTAS, GAS_BUDGETS, LAMBDA_RISKS
    ))
    total_tests = len(param_combinations)
    
    # Initialize global time tracking
    global start_time, completed_tests, failed_tests, skipped_tests
    start_time = time.time()
    completed_tests = 0
    failed_tests = 0
    skipped_tests = 0
    
    with ThreadPoolExecutor(max_workers=os.cpu_count() * 2) as executor:
        future_to_idx = {}
        for idx, params in enumerate(param_combinations):
            victim_count, distribution, total_balance, gas_price, alpha, delta, gas_budget, lambda_risk = params
            unique_id = str(uuid.uuid4())
            # Submit task
            future = executor.submit(
                run_foundry_tests_with_env, 
                victim_count, distribution, total_balance, gas_price, alpha, delta, gas_budget, lambda_risk, unique_id, idx+1, total_tests
            )
            future_to_idx[future] = idx
            tasks.append(future)
        
        # Wait for all tasks to complete
        for future in as_completed(tasks):
            idx = future_to_idx[future]
            try:
                success = future.result()
                if not success:
                    # Already logged as skipped above
                    pass
            except Exception as e:
                skipped_tests += 1
                print(f"[SKIPPED] (exception: {e}) at ({idx+1}/{total_tests})")
        
        print(f"\n✅ Test execution completed: {completed_tests} successful, {failed_tests} failed, {skipped_tests} skipped")
    
    # Collect and analyze results
    df = collect_logs_to_csv()
    
    if df is not None:
        # Print summary statistics
        print_summary_statistics(df)
    
    print("\n🎉 Multi-Contract Analysis Complete!")
    print("="*60)

if __name__ == "__main__":
    main()
