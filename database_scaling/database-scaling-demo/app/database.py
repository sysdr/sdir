import asyncio
import asyncpg
import os
import random
from typing import List, Dict, Any, Optional
from datetime import datetime
import json

class DatabaseManager:
    def __init__(self):
        self.primary_url = os.getenv("DATABASE_PRIMARY_URL")
        self.replica_urls = [
            os.getenv("DATABASE_REPLICA1_URL"),
            os.getenv("DATABASE_REPLICA2_URL")
        ]
        self.shard_urls = {
            'us': os.getenv("DATABASE_SHARD_US_URL"),
            'eu': os.getenv("DATABASE_SHARD_EU_URL")
        }
        
        self.primary_pool = None
        self.replica_pools = []
        self.shard_pools = {}
        self.replica_available = [True, True]

    async def initialize(self):
        """Initialize database connections and create tables"""
        # Primary connection
        self.primary_pool = await asyncpg.create_pool(
            self.primary_url,
            min_size=5,
            max_size=20
        )
        
        # Replica connections
        for replica_url in self.replica_urls:
            try:
                pool = await asyncpg.create_pool(
                    replica_url,
                    min_size=3,
                    max_size=15
                )
                self.replica_pools.append(pool)
            except Exception as e:
                print(f"⚠️  Replica connection failed: {e}")
                self.replica_pools.append(None)
        
        # Shard connections
        for region, shard_url in self.shard_urls.items():
            self.shard_pools[region] = await asyncpg.create_pool(
                shard_url,
                min_size=3,
                max_size=15
            )
        
        # Create tables
        await self.create_tables()
        print("✅ Database connections initialized")

    async def create_tables(self):
        """Create necessary tables in all databases"""
        
        # Primary and replicas schema
        primary_schema = """
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(50) UNIQUE NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            region VARCHAR(10) DEFAULT 'us'
        );
        
        CREATE TABLE IF NOT EXISTS user_events (
            id SERIAL PRIMARY KEY,
            user_id INTEGER REFERENCES users(id),
            event_type VARCHAR(50) NOT NULL,
            event_data JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX IF NOT EXISTS idx_user_events_user_id ON user_events(user_id);
        CREATE INDEX IF NOT EXISTS idx_user_events_created_at ON user_events(created_at);
        """
        
        # Execute on primary
        async with self.primary_pool.acquire() as conn:
            await conn.execute(primary_schema)
        
        # Shard schema (region-specific users)
        shard_schema = """
        CREATE TABLE IF NOT EXISTS regional_users (
            id SERIAL PRIMARY KEY,
            global_user_id INTEGER NOT NULL,
            username VARCHAR(50) NOT NULL,
            email VARCHAR(100) NOT NULL,
            preferences JSONB,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS regional_analytics (
            id SERIAL PRIMARY KEY,
            user_id INTEGER NOT NULL,
            page_views INTEGER DEFAULT 0,
            session_duration INTEGER DEFAULT 0,
            last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX IF NOT EXISTS idx_regional_users_global_id ON regional_users(global_user_id);
        CREATE INDEX IF NOT EXISTS idx_regional_analytics_user_id ON regional_analytics(user_id);
        """
        
        # Execute on shards
        for pool in self.shard_pools.values():
            async with pool.acquire() as conn:
                await conn.execute(shard_schema)

    async def write_user(self, username: str, email: str, region: str = 'us') -> int:
        """Write user to primary database"""
        async with self.primary_pool.acquire() as conn:
            user_id = await conn.fetchval(
                "INSERT INTO users (username, email, region) VALUES ($1, $2, $3) RETURNING id",
                username, email, region
            )
            return user_id

    async def read_user_from_replica(self, user_id: int) -> Optional[Dict]:
        """Read user from available replica"""
        available_replicas = [
            i for i, (pool, available) in enumerate(zip(self.replica_pools, self.replica_available))
            if pool is not None and available
        ]
        
        if not available_replicas:
            # Fallback to primary
            return await self.read_user_from_primary(user_id)
        
        replica_idx = random.choice(available_replicas)
        pool = self.replica_pools[replica_idx]
        
        try:
            async with pool.acquire() as conn:
                row = await conn.fetchrow(
                    "SELECT id, username, email, created_at, region FROM users WHERE id = $1",
                    user_id
                )
                return dict(row) if row else None
        except Exception as e:
            print(f"⚠️  Replica {replica_idx} error: {e}")
            self.replica_available[replica_idx] = False
            return await self.read_user_from_primary(user_id)

    async def read_user_from_primary(self, user_id: int) -> Optional[Dict]:
        """Read user from primary database"""
        async with self.primary_pool.acquire() as conn:
            row = await conn.fetchrow(
                "SELECT id, username, email, created_at, region FROM users WHERE id = $1",
                user_id
            )
            return dict(row) if row else None

    async def write_to_shard(self, region: str, global_user_id: int, username: str, email: str, preferences: Dict):
        """Write regional user data to appropriate shard"""
        pool = self.shard_pools.get(region)
        if not pool:
            raise ValueError(f"No shard available for region: {region}")
        
        async with pool.acquire() as conn:
            await conn.execute(
                """INSERT INTO regional_users (global_user_id, username, email, preferences) 
                   VALUES ($1, $2, $3, $4)""",
                global_user_id, username, email, json.dumps(preferences)
            )

    async def read_from_shard(self, region: str, global_user_id: int) -> Optional[Dict]:
        """Read regional user data from appropriate shard"""
        pool = self.shard_pools.get(region)
        if not pool:
            return None
        
        async with pool.acquire() as conn:
            row = await conn.fetchrow(
                """SELECT global_user_id, username, email, preferences, created_at 
                   FROM regional_users WHERE global_user_id = $1""",
                global_user_id
            )
            return dict(row) if row else None

    async def get_connection_stats(self) -> Dict[str, Any]:
        """Get connection pool statistics"""
        stats = {
            'primary': {
                'size': self.primary_pool.get_size(),
                'available': len(self.primary_pool._queue._queue) if self.primary_pool._queue else 0
            },
            'replicas': [],
            'shards': {}
        }
        
        for i, pool in enumerate(self.replica_pools):
            if pool:
                stats['replicas'].append({
                    'id': i,
                    'available': self.replica_available[i],
                    'size': pool.get_size(),
                    'free': len(pool._queue._queue) if pool._queue else 0
                })
        
        for region, pool in self.shard_pools.items():
            stats['shards'][region] = {
                'size': pool.get_size(),
                'free': len(pool._queue._queue) if pool._queue else 0
            }
        
        return stats

    async def simulate_replica_failure(self, replica_idx: int):
        """Simulate replica failure"""
        if replica_idx < len(self.replica_available):
            self.replica_available[replica_idx] = False
            print(f"🔥 Simulated failure of replica {replica_idx}")

    async def restore_replica(self, replica_idx: int):
        """Restore failed replica"""
        if replica_idx < len(self.replica_available):
            self.replica_available[replica_idx] = True
            print(f"✅ Restored replica {replica_idx}")
