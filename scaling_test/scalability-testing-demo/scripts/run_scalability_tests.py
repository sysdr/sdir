#!/usr/bin/env python3

import subprocess
import time
import requests
import json
import sys
from datetime import datetime

class ScalabilityTestRunner:
    def __init__(self, target_url="http://localhost:8000"):
        self.target_url = target_url
        self.test_results = {}
        
    def wait_for_service(self, timeout=60):
        """Wait for the service to be ready"""
        print("🔍 Waiting for service to be ready...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = requests.get(f"{self.target_url}/health")
                if response.status_code == 200:
                    print("✅ Service is ready!")
                    return True
            except requests.exceptions.ConnectionError:
                print("⏳ Service not ready yet, waiting...")
                time.sleep(2)
                
        print("❌ Service failed to start within timeout")
        return False
        
    def run_baseline_test(self):
        """Run baseline performance test"""
        print("\n📊 Running baseline performance test...")
        
        cmd = [
            "locust", 
            "-f", "tests/locustfile.py",
            "--host", self.target_url,
            "--users", "10",
            "--spawn-rate", "2",
            "--run-time", "30s",
            "--headless",
            "--csv", "results/baseline"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ Baseline test completed")
        else:
            print(f"❌ Baseline test failed: {result.stderr}")
            
    def run_load_ramp_test(self):
        """Run load ramping test"""
        print("\n🚀 Running load ramp test...")
        
        user_levels = [10, 25, 50, 100]
        for users in user_levels:
            print(f"Testing with {users} users...")
            
            cmd = [
                "locust",
                "-f", "tests/locustfile.py", 
                "--host", self.target_url,
                "--users", str(users),
                "--spawn-rate", "5",
                "--run-time", "60s",
                "--headless",
                "--csv", f"results/ramp_{users}_users"
            ]
            
            subprocess.run(cmd, capture_output=True)
            
            # Collect metrics
            try:
                health_response = requests.get(f"{self.target_url}/health")
                if health_response.status_code == 200:
                    metrics = health_response.json()
                    self.test_results[f"{users}_users"] = metrics
                    print(f"  CPU: {metrics['cpu_percent']:.1f}%, Memory: {metrics['memory_percent']:.1f}%")
                    
            except Exception as e:
                print(f"  Failed to collect metrics: {e}")
                
            time.sleep(10)  # Cool-down period
            
    def run_sustained_load_test(self):
        """Run sustained load test"""
        print("\n⏱️  Running sustained load test (5 minutes)...")
        
        cmd = [
            "locust",
            "-f", "tests/locustfile.py",
            "--host", self.target_url, 
            "--users", "50",
            "--spawn-rate", "5",
            "--run-time", "300s",
            "--headless",
            "--csv", "results/sustained"
        ]
        
        subprocess.run(cmd)
        print("✅ Sustained load test completed")
        
    def generate_report(self):
        """Generate test report"""
        print("\n📋 Generating test report...")
        
        report = {
            "test_timestamp": datetime.now().isoformat(),
            "target_url": self.target_url,
            "test_results": self.test_results
        }
        
        with open("results/test_report.json", "w") as f:
            json.dump(report, f, indent=2)
            
        print("✅ Test report saved to results/test_report.json")

def main():
    # Create results directory
    import os
    os.makedirs("results", exist_ok=True)
    
    runner = ScalabilityTestRunner()
    
    if not runner.wait_for_service():
        sys.exit(1)
        
    print("\n🧪 Starting Scalability Testing Suite")
    print("=====================================")
    
    runner.run_baseline_test()
    runner.run_load_ramp_test() 
    runner.run_sustained_load_test()
    runner.generate_report()
    
    print("\n🎉 All tests completed!")
    print("📊 View results in the results/ directory")
    print("🌐 Access dashboard at: http://localhost:8000/dashboard")
    print("📈 View Prometheus metrics at: http://localhost:9090")

if __name__ == "__main__":
    main()
