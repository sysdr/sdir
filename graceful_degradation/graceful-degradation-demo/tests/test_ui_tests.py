#!/usr/bin/env python3
"""
Test script for UI testing functionality
"""

import asyncio
import httpx
import json
from datetime import datetime

async def test_ui_test_endpoints():
    """Test the UI testing API endpoints"""
    base_url = "http://localhost:8080"
    
    async with httpx.AsyncClient() as client:
        print("🧪 Testing UI Testing Endpoints...")
        
        # Test running UI tests
        print("1. Testing /api/ui-tests/run endpoint...")
        try:
            response = await client.post(f"{base_url}/api/ui-tests/run")
            if response.status_code == 200:
                results = response.json()
                print(f"   ✅ UI tests ran successfully")
                print(f"   📊 Results: {results['summary']['passed']}/{results['summary']['total']} passed")
                
                # Display individual test results
                for test in results['tests']:
                    status_emoji = "✅" if test['status'] == 'passed' else "❌" if test['status'] == 'failed' else "⚠️"
                    print(f"   {status_emoji} {test['test_name']}: {test['status']}")
            else:
                print(f"   ❌ Failed to run UI tests: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error running UI tests: {e}")
        
        # Test getting test results
        print("\n2. Testing /api/ui-tests/results endpoint...")
        try:
            response = await client.get(f"{base_url}/api/ui-tests/results")
            if response.status_code == 200:
                results = response.json()
                if results['tests']:
                    print(f"   ✅ Retrieved test results successfully")
                    print(f"   📊 Summary: {results['summary']['passed']}/{results['summary']['total']} passed")
                else:
                    print("   ⚠️ No test results available")
            else:
                print(f"   ❌ Failed to get test results: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error getting test results: {e}")
        
        # Test status endpoint
        print("\n3. Testing /api/status endpoint...")
        try:
            response = await client.get(f"{base_url}/api/status")
            if response.status_code == 200:
                status = response.json()
                print(f"   ✅ Status API working")
                print(f"   📊 System pressure: {status['system_pressure']:.2f}")
                print(f"   🔧 Active features: {len(status['active_features'])}")
            else:
                print(f"   ❌ Status API failed: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error getting status: {e}")

async def test_ui_components():
    """Test individual UI components"""
    base_url = "http://localhost:8080"
    
    async with httpx.AsyncClient() as client:
        print("\n🔍 Testing Individual UI Components...")
        
        # Test load simulation
        print("1. Testing load simulation...")
        try:
            response = await client.get(f"{base_url}/api/load/50")
            if response.status_code == 200:
                result = response.json()
                print(f"   ✅ Load simulation working (duration: {result['duration']:.2f}s)")
            else:
                print(f"   ❌ Load simulation failed: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error testing load simulation: {e}")
        
        # Test recommendations
        print("2. Testing recommendations...")
        try:
            response = await client.get(f"{base_url}/api/recommendations/123")
            if response.status_code == 200:
                result = response.json()
                print(f"   ✅ Recommendations working (source: {result.get('source', 'unknown')})")
            else:
                print(f"   ❌ Recommendations failed: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error testing recommendations: {e}")
        
        # Test reviews
        print("3. Testing reviews...")
        try:
            response = await client.get(f"{base_url}/api/reviews/1")
            if response.status_code == 200:
                result = response.json()
                print(f"   ✅ Reviews working (source: {result.get('source', 'unknown')})")
            else:
                print(f"   ❌ Reviews failed: {response.status_code}")
        except Exception as e:
            print(f"   ❌ Error testing reviews: {e}")

async def main():
    """Main test function"""
    print("🚀 Starting UI Testing Verification...")
    print("=" * 50)
    
    try:
        await test_ui_test_endpoints()
        await test_ui_components()
        
        print("\n" + "=" * 50)
        print("✅ UI Testing Verification Complete!")
        print("\n📋 To test the UI manually:")
        print("1. Open http://localhost:8080 in your browser")
        print("2. Click 'Run UI Tests' button")
        print("3. View the test results displayed on the page")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")

if __name__ == "__main__":
    asyncio.run(main()) 