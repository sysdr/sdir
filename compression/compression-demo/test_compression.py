#!/usr/bin/env python3

import requests
import json
import sys
import time

def test_api():
    base_url = "http://localhost:5000"
    
    print("🧪 Testing Compression API...")
    
    # Test 1: Check if server is running
    try:
        response = requests.get(f"{base_url}/")
        assert response.status_code == 200
        print("✅ Server is running")
    except Exception as e:
        print(f"❌ Server not accessible: {e}")
        return False
    
    # Test 2: Get sample data
    try:
        response = requests.get(f"{base_url}/api/sample-data")
        assert response.status_code == 200
        samples = response.json()
        assert 'json' in samples
        print("✅ Sample data endpoint working")
    except Exception as e:
        print(f"❌ Sample data test failed: {e}")
        return False
    
    # Test 3: Compression analysis
    try:
        test_data = {"text": "This is a test string for compression analysis. " * 10}
        response = requests.post(
            f"{base_url}/api/compress",
            headers={"Content-Type": "application/json"},
            json=test_data
        )
        assert response.status_code == 200
        results = response.json()
        assert 'results' in results
        assert len(results['results']) > 0
        print("✅ Compression analysis working")
    except Exception as e:
        print(f"❌ Compression analysis test failed: {e}")
        return False
    
    # Test 4: Chart generation
    try:
        response = requests.get(f"{base_url}/api/chart")
        assert response.status_code == 200
        chart_data = response.json()
        assert 'chart' in chart_data
        print("✅ Chart generation working")
    except Exception as e:
        print(f"❌ Chart generation test failed: {e}")
        return False
    
    print("🎉 All tests passed!")
    return True

if __name__ == "__main__":
    # Wait for server to start
    time.sleep(5)
    success = test_api()
    sys.exit(0 if success else 1)
