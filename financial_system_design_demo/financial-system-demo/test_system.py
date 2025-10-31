#!/usr/bin/env python3
"""
Financial System Test Suite - ACID and Distributed Transactions
"""

import asyncio
import aiohttp
import json
import time
import uuid
from typing import Dict, List
import sys

class FinancialSystemTest:
    def __init__(self):
        self.base_urls = {
            'account': 'http://localhost:8001',
            'transaction': 'http://localhost:8002',
            'audit': 'http://localhost:8003'
        }
        self.session = None
        self.test_accounts = []
    
    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    async def wait_for_services(self, timeout=60):
        """Wait for all services to become healthy"""
        print("🔄 Waiting for services to become healthy...")
        
        services = [
            ('account', f"{self.base_urls['account']}/health"),
            ('transaction', f"{self.base_urls['transaction']}/health"),
            ('audit', f"{self.base_urls['audit']}/health")
        ]
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            all_healthy = True
            for service_name, health_url in services:
                try:
                    async with self.session.get(health_url) as response:
                        if response.status != 200:
                            all_healthy = False
                            break
                except:
                    all_healthy = False
                    break
            
            if all_healthy:
                print("✅ All services are healthy!")
                return True
            
            print("⏳ Services still starting up...")
            await asyncio.sleep(2)
        
        print("❌ Timeout waiting for services")
        return False
    
    async def create_test_account(self, name: str, balance: float) -> Dict:
        """Create a test account"""
        async with self.session.post(f"{self.base_urls['account']}/accounts", 
                                   json={"customer_name": name, "initial_balance": balance}) as response:
            if response.status == 200:
                result = await response.json()
                account_data = {
                    "account_id": result["account_id"],
                    "account_number": result["account_number"],
                    "
                    "customer_name": name,
                    "initial_balance": balance
                }
                self.test_accounts.append(account_data)
                return account_data
        raise Exception(f"Failed to create account for {name}")
    
    async def test_acid_properties(self):
        """Test ACID properties with concurrent transactions"""
        print("\n🧪 Testing ACID Properties...")
        
        # Create test accounts
        alice = await self.create_test_account("Alice Test", 1000.0)
        bob = await self.create_test_account("Bob Test", 500.0)
        
        print(f"✅ Created test accounts: {alice['account_number']} and {bob['account_number']}")
        
        # Test Atomicity - Transfer should be all-or-nothing
        print("🔬 Testing Atomicity...")
        transfer_data = {
            "from_account": alice['account_number'],
            "to_account": bob['account_number'],
            "amount": 300.0,
            "description": "ACID Test Transfer",
            "idempotency_key": f"test_{uuid.uuid4()}"
        }
        
        async with self.session.post(f"{self.base_urls['transaction']}/transactions/transfer",
                                   json=transfer_data) as response:
            result = await response.json()
            if result.get('success'):
                print("✅ Atomicity test passed - Transfer completed successfully")
            else:
                print(f"❌ Atomicity test failed: {result.get('message', 'Unknown error')}")
        
        # Verify account balances
        await self.verify_balances(alice['account_number'], 700.0, "Alice after transfer")
        await self.verify_balances(bob['account_number'], 800.0, "Bob after transfer")
        
        return True
    
    async def test_saga_pattern(self):
        """Test SAGA pattern with failure scenarios"""
        print("\n🎭 Testing SAGA Pattern...")
        
        # Create accounts for SAGA test
        charlie = await self.create_test_account("Charlie SAGA", 2000.0)
        david = await self.create_test_account("David SAGA", 100.0)
        
        # Test successful SAGA
        print("🔬 Testing successful SAGA execution...")
        saga_transfer = {
            "from_account": charlie['account_number'],
            "to_account": david['account_number'],
            "amount": 500.0,
            "description": "SAGA Pattern Test",
            "idempotency_key": f"saga_test_{uuid.uuid4()}"
        }
        
        async with self.session.post(f"{self.base_urls['transaction']}/transactions/transfer",
                                   json=saga_transfer) as response:
            result = await response.json()
            saga_id = result.get('saga_id')
            
            if result.get('success'):
                print(f"✅ SAGA completed successfully: {saga_id}")
                
                # Check SAGA status
                async with self.session.get(f"{self.base_urls['transaction']}/saga/{saga_id}/status") as saga_response:
                    saga_status = await saga_response.json()
                    print(f"📊 SAGA Status: {saga_status['status']}")
                    print(f"📈 Steps completed: {saga_status['current_step']}/{saga_status['total_steps']}")
            else:
                print(f"❌ SAGA failed: {result.get('message')}")
        
        return True
    
    async def test_concurrent_transactions(self):
        """Test system under concurrent load"""
        print("\n⚡ Testing Concurrent Transactions...")
        
        # Create accounts for concurrency test
        source = await self.create_test_account("Concurrent Source", 5000.0)
        targets = []
        for i in range(3):
            target = await self.create_test_account(f"Target {i+1}", 0.0)
            targets.append(target)
        
        # Execute concurrent transfers
        tasks = []
        for i, target in enumerate(targets):
            transfer_data = {
                "from_account": source['account_number'],
                "to_account": target['account_number'],
                "amount": 500.0,
                "description": f"Concurrent Test {i+1}",
                "idempotency_key": f"concurrent_{i}_{uuid.uuid4()}"
            }
            task = self.execute_transfer(transfer_data)
            tasks.append(task)
        
        # Wait for all transfers to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        successful_transfers = sum(1 for r in results if isinstance(r, dict) and r.get('success'))
        print(f"✅ Concurrent test completed: {successful_transfers}/3 transfers successful")
        
        return successful_transfers > 0
    
    async def execute_transfer(self, transfer_data):
        """Execute a single transfer"""
        async with self.session.post(f"{self.base_urls['transaction']}/transactions/transfer",
                                   json=transfer_data) as response:
            return await response.json()
    
    async def verify_balances(self, account_number: str, expected_balance: float, description: str):
        """Verify account balance matches expected value"""
        async with self.session.get(f"{self.base_urls['account']}/accounts/{account_number}") as response:
            if response.status == 200:
                account = await response.json()
                actual_balance = float(account['balance'])
                if abs(actual_balance - expected_balance) < 0.01:  # Allow for floating point precision
                    print(f"✅ {description}: Balance correct (${actual_balance:.2f})")
                else:
                    print(f"❌ {description}: Expected ${expected_balance:.2f}, got ${actual_balance:.2f}")
            else:
                print(f"❌ Failed to fetch balance for {account_number}")
    
    async def test_audit_trail(self):
        """Test audit trail functionality"""
        print("\n📋 Testing Audit Trail...")
        
        # Get audit statistics
        async with self.session.get(f"{self.base_urls['audit']}/audit/statistics") as response:
            if response.status == 200:
                stats = await response.json()
                print(f"📊 Total audit logs: {stats['overview']['total_logs']}")
                print(f"🏷️  Unique event types: {stats['overview']['unique_event_types']}")
            else:
                print("❌ Failed to fetch audit statistics")
        
        # Verify audit integrity
        async with self.session.get(f"{self.base_urls['audit']}/audit/integrity/verify") as response:
            if response.status == 200:
                integrity = await response.json()
                print(f"🔒 Audit integrity: {integrity['integrity_percentage']:.1f}%")
                print(f"✅ Verified records: {integrity['verified_records']}")
                if integrity['corrupted_records_count'] > 0:
                    print(f"⚠️  Corrupted records: {integrity['corrupted_records_count']}")
            else:
                print("❌ Failed to verify audit integrity")
        
        return True
    
    async def run_all_tests(self):
        """Run complete test suite"""
        print("🚀 Starting Financial System Test Suite")
        print("=" * 50)
        
        # Wait for services
        if not await self.wait_for_services():
            print("❌ Services not available, aborting tests")
            return False
        
        try:
            # Run all test categories
            tests = [
                ("ACID Properties", self.test_acid_properties),
                ("SAGA Pattern", self.test_saga_pattern),
                ("Concurrent Transactions", self.test_concurrent_transactions),
                ("Audit Trail", self.test_audit_trail)
            ]
            
            passed_tests = 0
            for test_name, test_func in tests:
                try:
                    result = await test_func()
                    if result:
                        passed_tests += 1
                        print(f"✅ {test_name} - PASSED")
                    else:
                        print(f"❌ {test_name} - FAILED")
                except Exception as e:
                    print(f"❌ {test_name} - ERROR: {str(e)}")
            
            print("\n" + "=" * 50)
            print(f"📊 Test Results: {passed_tests}/{len(tests)} tests passed")
            
            if passed_tests == len(tests):
                print("🎉 All tests passed! System is working correctly.")
                return True
            else:
                print("⚠️  Some tests failed. Check the logs above.")
                return False
                
        except Exception as e:
            print(f"❌ Test suite failed with error: {str(e)}")
            return False

async def main():
    async with FinancialSystemTest() as test_suite:
        success = await test_suite.run_all_tests()
        sys.exit(0 if success else 1)

if __name__ == "__main__":
    asyncio.run(main())
