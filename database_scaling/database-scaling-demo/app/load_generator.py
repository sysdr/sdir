import asyncio
import random
import time
from faker import Faker
from typing import Dict, List
import json

fake = Faker()

class LoadGenerator:
    def __init__(self, db_manager):
        self.db = db_manager
        self.test_users = []
        self.performance_results = {
            'single_db': [],
            'read_replicas': [],
            'sharding': []
        }

    async def setup_test_data(self):
        """Setup initial test data"""
        print("🔄 Setting up test data...")
        
        # Create test users
        for i in range(100):
            try:
                region = random.choice(['us', 'eu'])
                username = f"testuser_{i}_{int(time.time())}"
                email = f"test_{i}_{int(time.time())}@example.com"
                
                user_id = await self.db.write_user(username, email, region)
                self.test_users.append({
                    'id': user_id,
                    'username': username,
                    'email': email,
                    'region': region
                })
                
                # Add to regional shard
                preferences = {
                    'language': random.choice(['en', 'es', 'fr', 'de']),
                    'timezone': random.choice(['UTC', 'EST', 'PST', 'CET']),
                    'notifications': random.choice([True, False])
                }
                
                await self.db.write_to_shard(region, user_id, username, email, preferences)
                
                if i % 20 == 0:
                    print(f"  Created {i+1} test users...")
                    
            except Exception as e:
                print(f"⚠️  Error creating test user {i}: {e}")
        
        print(f"✅ Created {len(self.test_users)} test users")

    async def test_read_replicas(self):
        """Test read replica performance"""
        print("🧪 Testing read replica performance...")
        
        results = {
            'primary_times': [],
            'replica_times': [],
            'total_requests': 0,
            'errors': 0
        }
        
        # Test primary reads
        for _ in range(50):
            if not self.test_users:
                break
                
            user = random.choice(self.test_users)
            start_time = time.time()
            
            try:
                await self.db.read_user_from_primary(user['id'])
                results['primary_times'].append(time.time() - start_time)
                results['total_requests'] += 1
            except Exception as e:
                results['errors'] += 1
                print(f"Primary read error: {e}")
        
        # Test replica reads
        for _ in range(50):
            if not self.test_users:
                break
                
            user = random.choice(self.test_users)
            start_time = time.time()
            
            try:
                await self.db.read_user_from_replica(user['id'])
                results['replica_times'].append(time.time() - start_time)
                results['total_requests'] += 1
            except Exception as e:
                results['errors'] += 1
                print(f"Replica read error: {e}")
        
        # Calculate statistics
        if results['primary_times']:
            avg_primary = sum(results['primary_times']) / len(results['primary_times'])
        else:
            avg_primary = 0
            
        if results['replica_times']:
            avg_replica = sum(results['replica_times']) / len(results['replica_times'])
        else:
            avg_replica = 0
        
        self.performance_results['read_replicas'] = {
            'avg_primary_latency': avg_primary * 1000,  # Convert to ms
            'avg_replica_latency': avg_replica * 1000,
            'total_requests': results['total_requests'],
            'errors': results['errors'],
            'timestamp': time.time()
        }
        
        print(f"✅ Read replica test complete - Primary: {avg_primary*1000:.2f}ms, Replica: {avg_replica*1000:.2f}ms")

    async def test_sharding(self):
        """Test sharding performance"""
        print("🧪 Testing sharding performance...")
        
        results = {
            'shard_times': {'us': [], 'eu': []},
            'cross_shard_times': [],
            'total_requests': 0,
            'errors': 0
        }
        
        # Test single shard reads
        for region in ['us', 'eu']:
            region_users = [u for u in self.test_users if u['region'] == region]
            
            for _ in range(25):
                if not region_users:
                    continue
                    
                user = random.choice(region_users)
                start_time = time.time()
                
                try:
                    await self.db.read_from_shard(region, user['id'])
                    results['shard_times'][region].append(time.time() - start_time)
                    results['total_requests'] += 1
                except Exception as e:
                    results['errors'] += 1
                    print(f"Shard {region} read error: {e}")
        
        # Test cross-shard scenario (simulated)
        for _ in range(20):
            start_time = time.time()
            
            try:
                # Simulate reading from multiple shards
                us_users = [u for u in self.test_users if u['region'] == 'us'][:5]
                eu_users = [u for u in self.test_users if u['region'] == 'eu'][:5]
                
                tasks = []
                for user in us_users:
                    tasks.append(self.db.read_from_shard('us', user['id']))
                for user in eu_users:
                    tasks.append(self.db.read_from_shard('eu', user['id']))
                
                await asyncio.gather(*tasks)
                results['cross_shard_times'].append(time.time() - start_time)
                results['total_requests'] += 1
            except Exception as e:
                results['errors'] += 1
                print(f"Cross-shard read error: {e}")
        
        # Calculate statistics
        avg_us = sum(results['shard_times']['us']) / len(results['shard_times']['us']) if results['shard_times']['us'] else 0
        avg_eu = sum(results['shard_times']['eu']) / len(results['shard_times']['eu']) if results['shard_times']['eu'] else 0
        avg_cross = sum(results['cross_shard_times']) / len(results['cross_shard_times']) if results['cross_shard_times'] else 0
        
        self.performance_results['sharding'] = {
            'avg_us_latency': avg_us * 1000,
            'avg_eu_latency': avg_eu * 1000,
            'avg_cross_shard_latency': avg_cross * 1000,
            'total_requests': results['total_requests'],
            'errors': results['errors'],
            'timestamp': time.time()
        }
        
        print(f"✅ Sharding test complete - US: {avg_us*1000:.2f}ms, EU: {avg_eu*1000:.2f}ms, Cross-shard: {avg_cross*1000:.2f}ms")

    async def run_comparison_test(self):
        """Run comprehensive comparison test"""
        print("🧪 Running comprehensive performance comparison...")
        
        await self.test_read_replicas()
        await asyncio.sleep(2)
        await self.test_sharding()
        
        print("✅ Comprehensive test complete!")

    async def simulate_partition(self):
        """Simulate network partition"""
        print("🔥 Simulating network partition...")
        await self.db.simulate_replica_failure(0)
        
        # Restore after 30 seconds
        await asyncio.sleep(30)
        await self.db.restore_replica(0)
        print("✅ Network partition resolved")

    async def simulate_replica_failure(self):
        """Simulate replica failure"""
        print("🔥 Simulating replica failure...")
        replica_idx = random.randint(0, len(self.db.replica_pools) - 1)
        await self.db.simulate_replica_failure(replica_idx)
        
        # Restore after 60 seconds
        await asyncio.sleep(60)
        await self.db.restore_replica(replica_idx)
        print("✅ Replica restored")

    def get_performance_results(self):
        """Get current performance results"""
        return self.performance_results
