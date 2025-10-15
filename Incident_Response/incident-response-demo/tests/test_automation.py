import requests
import time
import json

def test_system_integration():
    """Test the complete incident response automation flow"""
    
    print("🧪 Testing Incident Response Automation System...")
    
    # Test 1: Check all services are healthy
    services = {
        'monitoring': 'http://localhost:5001/health',
        'alerting': 'http://localhost:5002/health',
        'automation': 'http://localhost:5003/health',
        'dashboard': 'http://localhost:5000'
    }
    
    print("\n1. Checking service health...")
    for service, url in services.items():
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"   ✅ {service.capitalize()} service: OK")
            else:
                print(f"   ❌ {service.capitalize()} service: ERROR")
        except Exception as e:
            print(f"   ❌ {service.capitalize()} service: {e}")
    
    # Test 2: Trigger incident and verify automation
    print("\n2. Testing incident simulation...")
    incidents = ['high_cpu', 'memory_leak', 'high_errors', 'slow_response']
    
    for incident in incidents:
        try:
            response = requests.get(f'http://localhost:5001/simulate/{incident}')
            if response.status_code == 200:
                print(f"   ✅ {incident} incident: Triggered")
            time.sleep(2)
        except Exception as e:
            print(f"   ❌ {incident} incident: {e}")
    
    # Test 3: Verify alerts are generated
    print("\n3. Checking alert generation...")
    time.sleep(10)  # Wait for alerts to be processed
    try:
        response = requests.get('http://localhost:5002/alerts')
        if response.status_code == 200:
            alerts = response.json()
            print(f"   ✅ Generated {len(alerts)} alerts")
        else:
            print("   ❌ Failed to fetch alerts")
    except Exception as e:
        print(f"   ❌ Alert check failed: {e}")
    
    # Test 4: Verify automated actions
    print("\n4. Checking automated actions...")
    try:
        response = requests.get('http://localhost:5003/actions')
        if response.status_code == 200:
            actions = response.json()
            print(f"   ✅ Executed {len(actions)} automated actions")
            for action in actions[-3:]:  # Show last 3 actions
                print(f"      - {action['action']}: {action['details']}")
        else:
            print("   ❌ Failed to fetch actions")
    except Exception as e:
        print(f"   ❌ Action check failed: {e}")
    
    print("\n🎉 Incident Response Automation Test Complete!")
    print("\n📊 Access the dashboard at: http://localhost:5000")
    print("🎛️ Try the incident simulation buttons to see automation in action!")

if __name__ == '__main__':
    test_system_integration()
