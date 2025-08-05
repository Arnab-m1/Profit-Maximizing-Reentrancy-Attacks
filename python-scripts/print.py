import os
import pandas as pd
import numpy as np

# ---------------- CONFIG ----------------
# The CSV file to read results from.
CSV_OUTPUT = "results_single_contract.csv"

# ---------------- CSV Loading ----------------
def load_df_from_csv():
    """Loads a DataFrame directly from the CSV output file."""
    if not os.path.exists(CSV_OUTPUT):
        print(f"⚠️ CSV file not found at '{CSV_OUTPUT}'.")
        print("Please run the full test suite first to generate the results file.")
        return None
    print(f"📄 Loading results directly from {CSV_OUTPUT}...")
    return pd.read_csv(CSV_OUTPUT)

# ---------------- Summary Statistics ----------------
def print_summary_statistics(df):
    """Prints a detailed analysis summary from a DataFrame."""
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

    # Ensure all relevant numeric columns are correctly typed
    numeric_cols = ['profit', 'gas_used', 'a', 'n']
    if risk_col_name:
        numeric_cols.append(risk_col_name)

    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    df['profit_eth'] = df['profit'] / 1e18
    if risk_col_name:
        df['risk_pct'] = df[risk_col_name] / 1e18

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
        
    if risk_col_name and 'risk_pct' in df.columns:
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

# ---------------- Main Entry ----------------
def main():
    """
    Main function to load data from the CSV and print the summary.
    """
    df = load_df_from_csv()
    print_summary_statistics(df)
    print("\n🎉 Analysis Complete!")


if __name__ == "__main__":
    main()