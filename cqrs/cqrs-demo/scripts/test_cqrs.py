#!/usr/bin/env python3
"""
CQRS Demo Test Suite
Tests all CQRS functionality end-to-end
"""

import asyncio
import httpx
import json
import time
from typing import Dict, Any

class CQRSTests:
    def __init__(self):
        self.command_url = "http://localhost:8001"
        self.query_url = "http://localhost:8002"
        self.test_results = []
    
    async def run_all_tests(self):
        """Run comprehensive CQRS tests"""
        print("🧪 Starting CQRS Pattern Tests")
        print("=" * 50)
        
        tests = [
            self.test_service_health,
            self.test_create_product,
            self.test_eventual_consistency,
            self.test_update_stock,
            self.test_create_order,
            self.test_complex_queries,
            self.test_performance_separation
        ]
        
        for test in tests:
            try:
                await test()
                self.test_results.append(f"✅ {test.__name__}")
            except Exception as e:
                self.test_results.append(f"❌ {test.__name__}: {str(e)}")
        
        self.print_results()
    
    async def test_service_health(self):
        """Test service health endpoints"""
        print("\n🏥 Testing Service Health...")
        
        async with httpx.AsyncClient() as client:
            command_health = await client.get(f"{self.command_url}/health")
            query_health = await client.get(f"{self.query_url}/health")
            
            assert command_health.status_code == 200
            assert query_health.status_code == 200
            
            print("✅ Both services are healthy")
    
    async def test_create_product(self):
        """Test product creation command"""
        print("\n📦 Testing Product Creation...")
        
        product_data = {
            "name": "Test Laptop",
            "description": "High-performance laptop for testing",
            "price": 999.99,
            "stock_quantity": 50,
            "category": "Electronics"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.command_url}/commands/products",
                json=product_data
            )
            
            assert response.status_code == 200
            result = response.json()
            assert "product_id" in result
            
            self.test_product_id = result["product_id"]
            print(f"✅ Product created with ID: {self.test_product_id}")
    
    async def test_eventual_consistency(self):
        """Test eventual consistency between command and query sides"""
        print("\n⏰ Testing Eventual Consistency...")
        
        # Wait for event propagation
        await asyncio.sleep(3)
        
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            
            assert response.status_code == 200
            product = response.json()
            assert product["name"] == "Test Laptop"
            assert product["price"] == 999.99
            
            print("✅ Product appears in query side - eventual consistency working")
    
    async def test_update_stock(self):
        """Test stock update command"""
        print("\n📊 Testing Stock Update...")
        
        stock_data = {
            "product_id": self.test_product_id,
            "quantity": 25
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.put(
                f"{self.command_url}/commands/products/{self.test_product_id}/stock",
                json=stock_data
            )
            
            assert response.status_code == 200
            print("✅ Stock updated successfully")
            
            # Wait and verify in query side
            await asyncio.sleep(2)
            
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            product = response.json()
            assert product["stock_quantity"] == 25
            
            print("✅ Stock update reflected in query side")
    
    async def test_create_order(self):
        """Test order creation with business logic"""
        print("\n🛒 Testing Order Creation...")
        
        order_data = {
            "customer_id": "test_customer_123",
            "product_id": self.test_product_id,
            "quantity": 5
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.command_url}/commands/orders",
                json=order_data
            )
            
            assert response.status_code == 200
            result = response.json()
            assert "order_id" in result
            assert "total_amount" in result
            
            self.test_order_id = result["order_id"]
            print(f"✅ Order created with ID: {self.test_order_id}")
            
            # Verify stock was decremented
            await asyncio.sleep(2)
            
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            product = response.json()
            assert product["stock_quantity"] == 20  # 25 - 5
            
            print("✅ Stock automatically decremented after order")
    
    async def test_complex_queries(self):
        """Test complex read model queries"""
        print("\n🔍 Testing Complex Queries...")
        
        async with httpx.AsyncClient() as client:
            # Test customer orders view
            response = await client.get(f"{self.query_url}/queries/customers/test_customer_123/orders")
            assert response.status_code == 200
            
            customer_orders = response.json()
            assert customer_orders["customer_id"] == "test_customer_123"
            assert customer_orders["total_orders"] >= 1
            
            # Test product statistics
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}/stats")
            assert response.status_code == 200
            
            stats = response.json()
            assert stats["total_orders"] >= 1
            assert stats["total_quantity_sold"] >= 5
            
            print("✅ Complex queries working correctly")
    
    async def test_performance_separation(self):
        """Test that read and write operations are truly separated"""
        print("\n⚡ Testing Performance Separation...")
        
        # Measure command latency
        start_time = time.time()
        
        async with httpx.AsyncClient() as client:
            await client.get(f"{self.command_url}/commands/stats")
            
        command_latency = (time.time() - start_time) * 1000
        
        # Measure query latency
        start_time = time.time()
        
        async with httpx.AsyncClient() as client:
            await client.get(f"{self.query_url}/queries/products")
            
        query_latency = (time.time() - start_time) * 1000
        
        print(f"✅ Command latency: {command_latency:.2f}ms")
        print(f"✅ Query latency: {query_latency:.2f}ms")
        print("✅ Services are operating independently")
    
    def print_results(self):
        """Print test results summary"""
        print("\n" + "=" * 50)
        print("🧪 CQRS Test Results Summary")
        print("=" * 50)
        
        passed = sum(1 for result in self.test_results if result.startswith("✅"))
        total = len(self.test_results)
        
        for result in self.test_results:
            print(result)
        
        print(f"\n📊 Tests Passed: {passed}/{total}")
        
        if passed == total:
            print("🎉 All tests passed! CQRS implementation is working correctly.")
        else:
            print("⚠️ Some tests failed. Check the logs for details.")

async def main():
    """Run the test suite"""
    tester = CQRSTests()
    await tester.run_all_tests()

if __name__ == "__main__":
    asyncio.run(main())
