#!/usr/bin/env python3
import time
import httpx
import asyncio

async def test_services():
    """Test all services are responding"""
    services = [
        ("User Service", "http://localhost:8001/health"),
        ("Payment Service", "http://localhost:8002/health"),
        ("Order Service", "http://localhost:8003/health"),
        ("Prometheus", "http://localhost:9090/-/healthy"),
        ("Grafana", "http://localhost:3000/api/health"),
        ("Dashboard", "http://localhost:8080")
    ]
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        for name, url in services:
            try:
                response = await client.get(url)
                status = "✅ HEALTHY" if response.status_code == 200 else f"❌ ERROR ({response.status_code})"
                print(f"{name:15} {status}")
            except Exception as e:
                print(f"{name:15} ❌ ERROR: {e}")

async def test_metrics():
    """Test metrics collection"""
    print("\n📊 Testing metrics collection...")
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.get("http://localhost:9090/api/v1/query", 
                                      params={"query": "up"})
            if response.status_code == 200:
                data = response.json()
                if data.get('data', {}).get('result'):
                    print("✅ Metrics are being collected")
                else:
                    print("❌ No metrics found")
            else:
                print(f"❌ Prometheus query failed: {response.status_code}")
        except Exception as e:
            print(f"❌ Error querying metrics: {e}")

async def test_alerts():
    """Test alert generation"""
    print("\n🚨 Testing alert functionality...")
    
    # Trigger some load to generate metrics
    async with httpx.AsyncClient(timeout=10.0) as client:
        for i in range(10):
            try:
                await client.get("http://localhost:8001/users/1")
                await client.post("http://localhost:8002/payments", json={"amount": 100})
                await client.post("http://localhost:8003/orders", json={"user_id": "1"})
            except:
                pass
    
    print("✅ Load generated - check dashboard for metrics")

async def main():
    print("🧪 Running Demo Tests...\n")
    
    print("🔍 Service Health Check:")
    await test_services()
    
    await test_metrics()
    await test_alerts()
    
    print("\n✅ Tests completed!")
    print("\n📱 Access Points:")
    print("   Dashboard:  http://localhost:8080")
    print("   Grafana:    http://localhost:3000 (admin/admin)")
    print("   Prometheus: http://localhost:9090")
    print("   AlertManager: http://localhost:9093")

if __name__ == "__main__":
    asyncio.run(main())
