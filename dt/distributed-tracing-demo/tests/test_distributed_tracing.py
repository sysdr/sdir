#!/usr/bin/env python3
"""Test script for distributed tracing demo."""

import asyncio
import httpx
import json
import time
from typing import Dict, Any

API_GATEWAY_URL = "http://localhost:8000"
JAEGER_UI_URL = "http://localhost:16686"

async def test_successful_order():
    """Test a successful order flow."""
    print("🧪 Testing successful order flow...")
    
    async with httpx.AsyncClient() as client:
        order_data = {
            "user_id": "test-user-123",
            "items": [
                {"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2},
                {"id": "item-2", "name": "Gadget", "price": 19.99, "quantity": 1}
            ],
            "payment_method": "credit_card"
        }
        
        start_time = time.time()
        response = await client.post(f"{API_GATEWAY_URL}/orders", json=order_data, timeout=30.0)
        end_time = time.time()
        
        print(f"⏱️  Request completed in {end_time - start_time:.2f} seconds")
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Order created successfully: {result['order_id']}")
            print(f"🔍 Trace ID: {result['trace_id']}")
            print(f"📊 View trace: {JAEGER_UI_URL}/trace/{result['trace_id']}")
            return True
        else:
            print(f"❌ Order failed: {response.status_code} - {response.text}")
            return False

async def test_payment_failure():
    """Test payment failure scenario."""
    print("🧪 Testing payment failure scenario...")
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_GATEWAY_URL}/orders/simulate-error",
            json={
                "user_id": "error-user",
                "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
                "payment_method": "credit_card"
            },
            timeout=30.0
        )
        
        result = response.json()
        print(f"⚠️  Payment failure simulated: {result.get('message', 'Unknown error')}")
        print(f"🔍 Trace ID: {result.get('trace_id', 'N/A')}")
        
        if result.get('trace_id'):
            print(f"📊 View trace: {JAEGER_UI_URL}/trace/{result['trace_id']}")
        
        return True

async def test_service_health():
    """Test health endpoints of all services."""
    print("🧪 Testing service health...")
    
    services = [
        ("API Gateway", "http://localhost:8000/health"),
        ("Order Service", "http://localhost:8001/health"),
        ("Payment Service", "http://localhost:8002/health"),
        ("Inventory Service", "http://localhost:8003/health"),
        ("Notification Service", "http://localhost:8004/health")
    ]
    
    async with httpx.AsyncClient() as client:
        for service_name, health_url in services:
            try:
                response = await client.get(health_url, timeout=5.0)
                if response.status_code == 200:
                    print(f"✅ {service_name} is healthy")
                else:
                    print(f"⚠️  {service_name} health check failed: {response.status_code}")
            except Exception as e:
                print(f"❌ {service_name} is unreachable: {str(e)}")

async def run_load_test():
    """Run a simple load test to generate multiple traces."""
    print("🧪 Running load test (10 concurrent orders)...")
    
    async def create_order(order_id: int):
        async with httpx.AsyncClient() as client:
            order_data = {
                "user_id": f"load-test-user-{order_id}",
                "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
                "payment_method": "credit_card"
            }
            
            try:
                response = await client.post(f"{API_GATEWAY_URL}/orders", json=order_data, timeout=30.0)
                if response.status_code == 200:
                    result = response.json()
                    return f"✅ Order {order_id}: {result['order_id']}"
                else:
                    return f"❌ Order {order_id} failed: {response.status_code}"
            except Exception as e:
                return f"❌ Order {order_id} error: {str(e)}"
    
    # Create 10 concurrent orders
    tasks = [create_order(i) for i in range(1, 11)]
    results = await asyncio.gather(*tasks)
    
    for result in results:
        print(result)
    
    print(f"📊 View all traces: {JAEGER_UI_URL}")

async def main():
    """Run all tests."""
    print("🚀 Starting Distributed Tracing Demo Tests")
    print("=" * 50)
    
    # Wait for services to be ready
    print("⏳ Waiting for services to be ready...")
    await asyncio.sleep(10)
    
    # Test service health
    await test_service_health()
    print()
    
    # Test successful order
    await test_successful_order()
    print()
    
    # Test payment failure
    await test_payment_failure()
    print()
    
    # Run load test
    await run_load_test()
    print()
    
    print("🎉 All tests completed!")
    print(f"🔍 Open Jaeger UI: {JAEGER_UI_URL}")
    print(f"🌐 Open Demo Web Interface: http://localhost:3000")

if __name__ == "__main__":
    asyncio.run(main())
