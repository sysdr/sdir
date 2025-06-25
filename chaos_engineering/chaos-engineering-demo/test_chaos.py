#!/usr/bin/env python3
"""
Chaos Engineering Platform Test Suite
Validates all functionality and demonstrates capabilities
"""

import asyncio
import aiohttp
import time
import json
import sys

async def test_chaos_platform():
    """Comprehensive test of chaos engineering platform"""
    
    print("🧪 Testing Chaos Engineering Platform...")
    
    base_url = "http://localhost:8000"
    
    async with aiohttp.ClientSession() as session:
        # Test 1: Check platform health
        print("\n1. Testing platform health...")
        try:
            async with session.get(f"{base_url}/api/metrics") as response:
                if response.status == 200:
                    metrics = await response.json()
                    print(f"✅ Platform healthy - CPU: {metrics['cpu_usage']:.1f}%, Memory: {metrics['memory_usage']:.1f}%")
                else:
                    print(f"❌ Platform health check failed: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
        
        # Test 2: Create experiment
        print("\n2. Creating chaos experiment...")
        experiment_data = {
            "name": "Test CPU Load Injection",
            "target_service": "user-service",
            "failure_type": "cpu_load",
            "intensity": 0.7,
            "duration": 15
        }
        
        try:
            async with session.post(f"{base_url}/api/experiments", 
                                  json=experiment_data) as response:
                if response.status == 200:
                    result = await response.json()
                    experiment_id = result["id"]
                    print(f"✅ Experiment created: {experiment_id}")
                else:
                    print(f"❌ Failed to create experiment: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Experiment creation failed: {e}")
            return False
        
        # Test 3: Run experiment
        print("\n3. Running chaos experiment...")
        try:
            async with session.post(f"{base_url}/api/experiments/{experiment_id}/run") as response:
                if response.status == 200:
                    print("✅ Experiment started successfully")
                    
                    # Monitor for 20 seconds
                    print("📊 Monitoring system during experiment...")
                    for i in range(10):
                        await asyncio.sleep(2)
                        async with session.get(f"{base_url}/api/metrics") as metrics_response:
                            if metrics_response.status == 200:
                                metrics = await metrics_response.json()
                                print(f"   CPU: {metrics['cpu_usage']:.1f}%, Memory: {metrics['memory_usage']:.1f}%, Active Failures: {metrics['active_failures']}")
                else:
                    print(f"❌ Failed to run experiment: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Experiment execution failed: {e}")
            return False
        
        # Test 4: Check active failures
        print("\n4. Checking active failures...")
        try:
            async with session.get(f"{base_url}/api/failures") as response:
                if response.status == 200:
                    failures = await response.json()
                    print(f"✅ Active failures retrieved: {len(failures)} active")
                    for service, failure in failures.items():
                        print(f"   - {service}: {failure['type']} (duration: {failure['duration']}s)")
                else:
                    print(f"❌ Failed to get failures: {response.status}")
        except Exception as e:
            print(f"❌ Failures check failed: {e}")
        
        # Test 5: Verify mock services
        print("\n5. Testing mock services...")
        mock_services = [
            ("user-service", 8001),
            ("order-service", 8002),
            ("payment-service", 8003),
            ("inventory-service", 8004)
        ]
        
        for service_name, port in mock_services:
            try:
                async with session.get(f"http://localhost:{port}/health") as response:
                    if response.status == 200:
                        health = await response.json()
                        print(f"✅ {service_name} is healthy: {health['status']}")
                    else:
                        print(f"⚠️  {service_name} returned status: {response.status}")
            except Exception as e:
                print(f"❌ {service_name} unreachable: {e}")
    
    print("\n🎉 Chaos Engineering Platform test completed!")
    return True

def run_tests():
    """Run all tests"""
    return asyncio.run(test_chaos_platform())

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
