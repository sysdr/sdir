#!/usr/bin/env python3
import asyncio
import httpx
import time

async def test_services():
    """Test all SAGA scenarios"""
    print("🧪 Testing SAGA Pattern...")
    
    # Wait for services
    await asyncio.sleep(10)
    
    base_url = "http://localhost:8000"
    
    # Test 1: Success
    print("🎯 Testing success scenario...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-1",
            "product_id": "product-1",
            "quantity": 2,
            "amount": 50.0,
            "should_fail": "none"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPLETED"
        print("✅ Success test passed")
    
    # Test 2: Payment failure
    print("💳 Testing payment failure...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-2",
            "product_id": "product-2",
            "quantity": 1,
            "amount": 100.0,
            "should_fail": "payment"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPENSATED"
        print("✅ Payment failure test passed")
    
    # Test 3: Shipping failure  
    print("🚚 Testing shipping failure...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-3",
            "product_id": "product-3",
            "quantity": 1,
            "amount": 150.0,
            "should_fail": "shipping"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPENSATED"
        print("✅ Shipping failure test passed")
    
    print("🎉 All tests passed!")
    return True

if __name__ == "__main__":
    success = asyncio.run(test_services())
    exit(0 if success else 1)
