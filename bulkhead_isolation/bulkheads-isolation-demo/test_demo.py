#!/usr/bin/env python3
"""
Test script for Bulkheads and Isolation Demo
Validates that all functionality works correctly
"""

import requests
import time
import json
import sys
from concurrent.futures import ThreadPoolExecutor
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BASE_URL = "http://localhost:5000"

def test_basic_connectivity():
    """Test basic connectivity to the application"""
    try:
        response = requests.get(f"{BASE_URL}/", timeout=10)
        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        logger.info("✅ Basic connectivity test passed")
        return True
    except Exception as e:
        logger.error(f"❌ Basic connectivity test failed: {e}")
        return False

def test_service_status_api():
    """Test service status API endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/api/services/status", timeout=10)
        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        
        data = response.json()
        required_services = ['payment', 'analytics', 'user_mgmt', 'notification']
        
        for service in required_services:
            assert service in data, f"Service {service} not found in status"
            assert 'active_threads' in data[service], f"active_threads missing for {service}"
            assert 'success_rate' in data[service], f"success_rate missing for {service}"
        
        assert 'system' in data, "System metrics not found"
        logger.info("✅ Service status API test passed")
        return True
    except Exception as e:
        logger.error(f"❌ Service status API test failed: {e}")
        return False

def test_service_request_submission():
    """Test submitting requests to individual services"""
    services = ['payment', 'analytics', 'user_mgmt', 'notification']
    
    for service in services:
        try:
            response = requests.post(
                f"{BASE_URL}/api/services/{service}/request",
                json={'work_type': 'light'},
                timeout=10
            )
            assert response.status_code == 200, f"Expected 200, got {response.status_code}"
            
            data = response.json()
            assert data['success'] == True, f"Request submission failed for {service}"
            logger.info(f"✅ Service request test passed for {service}")
        except Exception as e:
            logger.error(f"❌ Service request test failed for {service}: {e}")
            return False
    
    return True

def test_failure_rate_setting():
    """Test setting failure rates for services"""
    try:
        response = requests.post(
            f"{BASE_URL}/api/services/analytics/failure_rate",
            json={'failure_rate': 50},
            timeout=10
        )
        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        
        data = response.json()
        assert data['success'] == True, "Failure rate setting failed"
        assert data['failure_rate'] == 50, "Failure rate not set correctly"
        
        # Reset to 0
        requests.post(
            f"{BASE_URL}/api/services/analytics/failure_rate",
            json={'failure_rate': 0},
            timeout=10
        )
        
        logger.info("✅ Failure rate setting test passed")
        return True
    except Exception as e:
        logger.error(f"❌ Failure rate setting test failed: {e}")
        return False

def test_load_test_api():
    """Test load testing functionality"""
    try:
        response = requests.post(
            f"{BASE_URL}/api/load_test",
            json={'requests_per_service': 5, 'work_type': 'light'},
            timeout=10
        )
        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        
        data = response.json()
        assert data['success'] == True, "Load test submission failed"
        logger.info("✅ Load test API test passed")
        return True
    except Exception as e:
        logger.error(f"❌ Load test API test failed: {e}")
        return False

def test_bulkhead_isolation():
    """Test that bulkhead isolation actually works"""
    logger.info("🧪 Testing bulkhead isolation...")
    
    # First, set analytics service to high failure rate
    requests.post(
        f"{BASE_URL}/api/services/analytics/failure_rate",
        json={'failure_rate': 90},
        timeout=10
    )
    
    # Submit load to analytics service
    requests.post(
        f"{BASE_URL}/api/load_test",
        json={'requests_per_service': 10, 'work_type': 'heavy'},
        timeout=10
    )
    
    # Wait a bit for requests to process
    time.sleep(3)
    
    # Check that other services are still healthy
    response = requests.get(f"{BASE_URL}/api/services/status", timeout=10)
    data = response.json()
    
    # Payment service should still be healthy
    payment_success_rate = data['payment']['success_rate']
    if payment_success_rate < 80:
        logger.error(f"❌ Bulkhead isolation failed: Payment service affected by analytics failures")
        return False
    
    # Reset analytics failure rate
    requests.post(
        f"{BASE_URL}/api/services/analytics/failure_rate",
        json={'failure_rate': 0},
        timeout=10
    )
    
    logger.info("✅ Bulkhead isolation test passed")
    return True

def run_all_tests():
    """Run all tests and return overall result"""
    tests = [
        ("Basic Connectivity", test_basic_connectivity),
        ("Service Status API", test_service_status_api),
        ("Service Request Submission", test_service_request_submission),
        ("Failure Rate Setting", test_failure_rate_setting),
        ("Load Test API", test_load_test_api),
        ("Bulkhead Isolation", test_bulkhead_isolation)
    ]
    
    results = []
    
    logger.info("🧪 Starting Bulkheads Demo Test Suite...")
    logger.info("=" * 50)
    
    for test_name, test_func in tests:
        logger.info(f"Running: {test_name}")
        result = test_func()
        results.append(result)
        time.sleep(1)  # Brief pause between tests
    
    logger.info("=" * 50)
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        logger.info(f"🎉 All tests passed! ({passed}/{total})")
        return True
    else:
        logger.error(f"❌ Some tests failed. ({passed}/{total} passed)")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
