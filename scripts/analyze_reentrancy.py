#!/usr/bin/env python3
import subprocess
import json
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import os
import numpy as np

def run_forge_test(alpha, delta, gas_price, victim_balance):
    """Run forge test with custom parameters and extract results"""
    # Check if forge is installed
    if subprocess.run(['which', 'forge'], capture_output=True).returncode != 0:
        print("Error: forge not found. Please install Foundry first.")
        print("Run: curl -L https://foundry.paradigm.xyz | bash")
        print("Then: foundryup")
        return None
        
    cmd = [
        "forge", "test",
        "--match-test", "testOptimalAttackParameters",
        "--match-contract", "ReentrancyTest",
        "-vvv",
        f"--gas-price={gas_price}",
        f"--block-gas-limit=30000000",
        f"--via-ir",  # Use intermediate representation for better output
    ]
    
    # Set environment variables for test parameters
    env = os.environ.copy()  # Copy current environment
    env.update({
        "ALPHA": str(alpha),
        "DELTA": str(delta),
        "GAS_PRICE": str(gas_price),
        "VICTIM_BALANCE": str(victim_balance)
    })
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        output = result.stdout + result.stderr
        
        # Extract parameters from test output
        params = {}
        for line in output.split('\n'):
            if "===" in line or "ETH" in line or "calls:" in line or "risk:" in line:
                if ":" in line:
                    key, value = line.split(":", 1)
                    # Try to convert numeric values
                    try:
                        params[key.strip()] = float(value.strip().split()[0])  # Take first word and convert to float
                    except:
                        params[key.strip()] = value.strip()
        
        return params
    except Exception as e:
        print(f"Error running test: {e}")
        return None

def collect_data():
    """Collect data by running tests with different parameters"""
    data = []
    
    # Parameter ranges to test
    alphas = [0.001, 0.005, 0.01, 0.05]  # Detection rates
    deltas = [0.3, 0.4, 0.5, 0.6]  # Max detection risks
    gas_prices = [5, 10, 20, 30]  # Gas prices in gwei
    balances = [10, 50, 100, 200]  # Victim balances in ETH
    
    total_runs = len(alphas) * len(deltas) * len(gas_prices) * len(balances)
    current_run = 0
    
    # First check if forge is available
    if subprocess.run(['which', 'forge'], capture_output=True).returncode != 0:
        print("Error: forge not found. Please install Foundry first:")
        print("1. Run: curl -L https://foundry.paradigm.xyz | bash")
        print("2. Then: foundryup")
        return pd.DataFrame()  # Return empty dataframe
    
    for alpha in alphas:
        for delta in deltas:
            for gas_price in gas_prices:
                for balance in balances:
                    current_run += 1
                    print(f"Running test {current_run}/{total_runs}")
                    
                    alpha_scaled = int(alpha * 1e18)
                    delta_scaled = int(delta * 1e18)
                    balance_scaled = int(balance * 1e18)
                    
                    result = run_forge_test(alpha_scaled, delta_scaled, gas_price, balance_scaled)
                    if result:
                        data.append({
                            'alpha': alpha,
                            'delta': delta,
                            'gas_price': gas_price,
                            'victim_balance': balance,
                            **result
                        })
    
    return pd.DataFrame(data)

def generate_graphs(df):
    """Generate various analysis graphs"""
    if df.empty:
        print("No data to generate graphs. Please ensure Foundry is installed and tests are passing.")
        return
        
    # Create output directory
    Path("analysis").mkdir(exist_ok=True)
    
    # Use a simple style
    plt.style.use('default')
    
    # Convert numeric columns if they're strings
    numeric_columns = ['Expected profit', 'Number of calls', 'Detection risk']
    for col in numeric_columns:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
    
    # 1. Profitability vs Gas Price
    plt.figure(figsize=(10, 6))
    for balance in sorted(df['victim_balance'].unique()):
        subset = df[df['victim_balance'] == balance]
        plt.plot(subset['gas_price'], subset['Expected profit'], 
                label=f'Balance: {balance} ETH', marker='o')
    plt.title('Attack Profitability vs Gas Price')
    plt.xlabel('Gas Price (gwei)')
    plt.ylabel('Expected Profit (ETH)')
    plt.legend()
    plt.grid(True)
    plt.savefig('analysis/profitability_vs_gas.png')
    plt.close()
    
    # 2. Detection Risk vs Number of Calls
    plt.figure(figsize=(10, 6))
    # Normalize profit for marker sizes
    max_profit = df['Expected profit'].max()
    min_profit = df['Expected profit'].min()
    
    for alpha in sorted(df['alpha'].unique()):
        subset = df[df['alpha'] == alpha]
        # Normalize profits to reasonable marker sizes (between 50 and 500)
        sizes = 50 + 450 * (subset['Expected profit'] - min_profit) / (max_profit - min_profit)
        plt.scatter(subset['Number of calls'], subset['Detection risk'],
                   label=f'Detection Rate: {alpha:.3%}', 
                   s=sizes)
    plt.title('Detection Risk vs Number of Calls')
    plt.xlabel('Number of Calls')
    plt.ylabel('Detection Risk (%)')
    plt.legend()
    plt.grid(True)
    plt.savefig('analysis/risk_vs_calls.png')
    plt.close()
    
    # 3. Withdrawal Amount Distribution
    plt.figure(figsize=(10, 6))
    balances = sorted(df['victim_balance'].unique())
    data = [df[df['victim_balance'] == b]['Withdrawal amount'] for b in balances]
    plt.boxplot(data, labels=[f'{b} ETH' for b in balances])
    plt.title('Withdrawal Amount Distribution by Victim Balance')
    plt.xlabel('Victim Balance (ETH)')
    plt.ylabel('Withdrawal Amount (ETH)')
    plt.grid(True)
    plt.savefig('analysis/withdrawal_distribution.png')
    plt.close()
    
    # 4. Profit Heatmap
    plt.figure(figsize=(10, 8))
    pivot = df.pivot_table(
        values='Expected profit',
        index='gas_price',
        columns='victim_balance',
        aggfunc='mean'
    )
    plt.imshow(pivot, cmap='YlOrRd', aspect='auto')
    plt.colorbar(label='Expected Profit (ETH)')
    plt.title('Profit Heatmap: Gas Price vs Victim Balance')
    plt.xlabel('Victim Balance (ETH)')
    plt.ylabel('Gas Price (gwei)')
    plt.xticks(range(len(pivot.columns)), pivot.columns)
    plt.yticks(range(len(pivot.index)), pivot.index)
    for i in range(len(pivot.index)):
        for j in range(len(pivot.columns)):
            plt.text(j, i, f'{pivot.iloc[i, j]:.2f}', 
                    ha='center', va='center')
    plt.savefig('analysis/profit_heatmap.png')
    plt.close()
    
    # Save raw data
    df.to_csv('analysis/reentrancy_data.csv', index=False)
    
    # Generate summary statistics
    summary = df.groupby(['alpha', 'delta']).agg({
        'Expected profit': ['mean', 'std', 'min', 'max'],
        'Detection risk': ['mean', 'std'],
        'Number of calls': ['mean', 'max']
    }).round(2)
    
    summary.to_csv('analysis/summary_statistics.csv')

def main():
    print("Starting data collection...")
    df = collect_data()
    
    print("Generating graphs...")
    generate_graphs(df)
    
    if not df.empty:
        print("Analysis complete! Check the 'analysis' directory for results.")
    else:
        print("\nNo data was collected. Please install Foundry and try again.")
        print("To install Foundry:")
        print("1. Run: curl -L https://foundry.paradigm.xyz | bash")
        print("2. Then: foundryup")

if __name__ == "__main__":
    main() 