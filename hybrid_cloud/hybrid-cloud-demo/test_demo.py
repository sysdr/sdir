#!/usr/bin/env python3
import requests
import time
import json

def test_services():
    """Test all services are responding"""
    services = {
        "Gateway": "http://localhost:5000/status",
        "Private Cloud": "http://localhost:5001/health",
        "Public Cloud": "http://localhost:5002/health"
    }
    
    print("🧪 Testing service health...")
    for name, url in services.items():
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"✅ {name}: Healthy")
            else:
                print(f"❌ {name}: Unhealthy ({response.status_code})")
        except Exception as e:
            print(f"❌ {name}: Failed to connect - {e}")
    print()

def test_data_operations():
    """Test data operations and sync"""
    print("🧪 Testing data operations...")
    
    # Add customer via gateway
    customer_data = {
        "name": "Test Customer",
        "email": "test@example.com"
    }
    
    try:
        response = requests.post(
            "http://localhost:5000/api/customers",
            json=customer_data,
            timeout=5
        )
        if response.status_code == 200:
            print("✅ Customer creation: Success")
        else:
            print(f"❌ Customer creation: Failed ({response.status_code})")
    except Exception as e:
        print(f"❌ Customer creation: Error - {e}")
    
    # Wait for sync
    time.sleep(2)
    
    # Test sync status
    try:
        response = requests.get("http://localhost:5001/sync/status", timeout=5)
        if response.status_code == 200:
            print("✅ Sync status: Accessible")
        else:
            print(f"❌ Sync status: Failed ({response.status_code})")
    except Exception as e:
        print(f"❌ Sync status: Error - {e}")
    print()

def test_failover():
    """Test failover functionality"""
    print("🧪 Testing failover...")
    
    # Simulate private cloud failure
    try:
        response = requests.post("http://localhost:5000/simulate/failure/private", timeout=5)
        if response.status_code == 200:
            print("✅ Failure simulation: Success")
        else:
            print(f"❌ Failure simulation: Failed ({response.status_code})")
    except Exception as e:
        print(f"❌ Failure simulation: Error - {e}")
    
    # Wait for failover to activate
    time.sleep(3)
    
    # Check status
    try:
        response = requests.get("http://localhost:5000/status", timeout=5)
        if response.status_code == 200:
            status = response.json()
            if status.get("failover_active"):
                print("✅ Failover activation: Success")
            else:
                print("❌ Failover activation: Not activated")
        else:
            print(f"❌ Status check: Failed ({response.status_code})")
    except Exception as e:
        print(f"❌ Status check: Error - {e}")
    
    # Restore service
    try:
        response = requests.post("http://localhost:5000/simulate/restore/private", timeout=5)
        if response.status_code == 200:
            print("✅ Service restoration: Success")
        else:
            print(f"❌ Service restoration: Failed ({response.status_code})")
    except Exception as e:
        print(f"❌ Service restoration: Error - {e}")
    print()

if __name__ == "__main__":
    print("🚀 Starting Hybrid Cloud Demo Tests")
    print("=" * 50)
    
    # Wait for services to start
    print("⏳ Waiting for services to initialize...")
    time.sleep(10)
    
    test_services()
    test_data_operations()
    test_failover()
    
    print("✅ All tests completed!")
    print("\n🌐 Open http://localhost:5000 to see the dashboard")
