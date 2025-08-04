#!/usr/bin/env python3

import json
import pandas as pd
import matplotlib.pyplot as plt
import os

def analyze_locust_results():
    """Analyze Locust CSV results"""
    results_dir = "results"
    
    if not os.path.exists(results_dir):
        print("No results directory found. Run tests first!")
        return
        
    print("📊 Analyzing test results...")
    
    # Find all CSV files
    csv_files = [f for f in os.listdir(results_dir) if f.endswith('_stats.csv')]
    
    for csv_file in csv_files:
        try:
            df = pd.read_csv(os.path.join(results_dir, csv_file))
            print(f"\n📈 Results for {csv_file}:")
            print(f"  Average Response Time: {df['Average Response Time'].mean():.2f}ms")
            print(f"  Max Response Time: {df['Max Response Time'].max():.2f}ms") 
            print(f"  Requests per Second: {df['Requests/s'].sum():.2f}")
            print(f"  Failure Rate: {(df['Failure Count'].sum() / df['Request Count'].sum() * 100):.2f}%")
            
        except Exception as e:
            print(f"Error analyzing {csv_file}: {e}")

if __name__ == "__main__":
    analyze_locust_results()
