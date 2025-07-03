"""
Load testing script for stateless vs stateful comparison
"""
import asyncio
import aiohttp
import time
import json
import random
from datetime import datetime

class LoadTester:
    def __init__(self, base_url, service_type):
        self.base_url = base_url
        self.service_type = service_type
        self.session = None
        self.results = []
    
    async def create_session(self):
        """Create HTTP session"""
        connector = aiohttp.TCPConnector(limit=100)
        self.session = aiohttp.ClientSession(connector=connector)
    
    async def close_session(self):
        """Close HTTP session"""
        if self.session:
            await self.session.close()
    
    async def login_user(self, user_id):
        """Login a user"""
        try:
            data = aiohttp.FormData()
            data.add_field('username', f'user_{user_id}')
            data.add_field('email', f'user_{user_id}@example.com')
            
            start_time = time.time()
            async with self.session.post(f'{self.base_url}/login', data=data) as response:
                duration = time.time() - start_time
                success = response.status == 200
                
                self.results.append({
                    'operation': 'login',
                    'duration': duration,
                    'success': success,
                    'timestamp': datetime.now()
                })
                
                return success
        except Exception as e:
            print(f"Login failed for user {user_id}: {e}")
            return False
    
    async def add_items_to_cart(self, user_id, num_items=3):
        """Add multiple items to cart"""
        for i in range(num_items):
            try:
                item_data = {
                    'product_id': f'prod_{user_id}_{i}',
                    'name': f'Product {i} for User {user_id}',
                    'price': random.uniform(10.0, 100.0),
                    'quantity': random.randint(1, 3)
                }
                
                start_time = time.time()
                async with self.session.post(f'{self.base_url}/cart/add', 
                                           json=item_data) as response:
                    duration = time.time() - start_time
                    success = response.status == 200
                    
                    self.results.append({
                        'operation': 'add_to_cart',
                        'duration': duration,
                        'success': success,
                        'timestamp': datetime.now()
                    })
                    
                    if not success:
                        print(f"Add to cart failed for user {user_id}: {response.status}")
                        
                # Small delay between items
                await asyncio.sleep(0.1)
                
            except Exception as e:
                print(f"Add to cart failed for user {user_id}: {e}")
    
    async def get_cart(self, user_id):
        """Get user's cart"""
        try:
            start_time = time.time()
            async with self.session.get(f'{self.base_url}/cart') as response:
                duration = time.time() - start_time
                success = response.status == 200
                
                self.results.append({
                    'operation': 'get_cart',
                    'duration': duration,
                    'success': success,
                    'timestamp': datetime.now()
                })
                
                return success
        except Exception as e:
            print(f"Get cart failed for user {user_id}: {e}")
            return False
    
    async def simulate_user_session(self, user_id):
        """Simulate a complete user session"""
        # Login
        if not await self.login_user(user_id):
            return
        
        # Add items to cart
        await self.add_items_to_cart(user_id)
        
        # Check cart multiple times
        for _ in range(3):
            await self.get_cart(user_id)
            await asyncio.sleep(random.uniform(0.5, 2.0))
    
    async def run_load_test(self, num_users=50, concurrent_users=10):
        """Run load test with specified parameters"""
        print(f"Starting load test for {self.service_type} service")
        print(f"Users: {num_users}, Concurrent: {concurrent_users}")
        
        await self.create_session()
        
        # Create semaphore to limit concurrent users
        semaphore = asyncio.Semaphore(concurrent_users)
        
        async def user_with_semaphore(user_id):
            async with semaphore:
                await self.simulate_user_session(user_id)
        
        # Run all user sessions
        start_time = time.time()
        tasks = [user_with_semaphore(i) for i in range(num_users)]
        await asyncio.gather(*tasks, return_exceptions=True)
        total_time = time.time() - start_time
        
        await self.close_session()
        
        # Analyze results
        self.analyze_results(total_time)
    
    def analyze_results(self, total_time):
        """Analyze and print test results"""
        if not self.results:
            print("No results to analyze")
            return
        
        # Group by operation
        operations = {}
        for result in self.results:
            op = result['operation']
            if op not in operations:
                operations[op] = []
            operations[op].append(result)
        
        print(f"\n{'='*50}")
        print(f"LOAD TEST RESULTS - {self.service_type.upper()} SERVICE")
        print(f"{'='*50}")
        print(f"Total test time: {total_time:.2f} seconds")
        print(f"Total operations: {len(self.results)}")
        
        for op_name, op_results in operations.items():
            success_count = sum(1 for r in op_results if r['success'])
            total_count = len(op_results)
            success_rate = (success_count / total_count) * 100
            
            durations = [r['duration'] for r in op_results if r['success']]
            if durations:
                avg_duration = sum(durations) / len(durations)
                min_duration = min(durations)
                max_duration = max(durations)
            else:
                avg_duration = min_duration = max_duration = 0
            
            print(f"\n{op_name.upper()}:")
            print(f"  Success rate: {success_rate:.1f}% ({success_count}/{total_count})")
            print(f"  Avg duration: {avg_duration*1000:.1f}ms")
            print(f"  Min duration: {min_duration*1000:.1f}ms")
            print(f"  Max duration: {max_duration*1000:.1f}ms")

async def main():
    """Run load tests on both services"""
    services = [
        {'url': 'http://stateless-service:8000', 'type': 'stateless'},
        {'url': 'http://stateful-service:8001', 'type': 'stateful'}
    ]
    
    print("Starting comparative load test...")
    
    for service in services:
        tester = LoadTester(service['url'], service['type'])
        try:
            await tester.run_load_test(num_users=20, concurrent_users=5)
        except Exception as e:
            print(f"Load test failed for {service['type']}: {e}")
        
        # Wait between tests
        await asyncio.sleep(5)
    
    print("\nLoad testing complete!")

if __name__ == "__main__":
    asyncio.run(main())
