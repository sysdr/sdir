import asyncio
import time
import json
import hashlib
from typing import Optional, Any, Dict
from dataclasses import dataclass
from enum import Enum

class CacheLayer(Enum):
    L1_PROCESS = "l1_process"
    L2_DISTRIBUTED = "l2_distributed"
    L3_DATABASE = "l3_database"

@dataclass
class CacheEntry:
    data: Any
    version: int
    temperature: float  # Access frequency
    last_access: float
    ttl: float
    layer_affinity: CacheLayer

class ThermalCacheManager:
    def __init__(self):
        self.l1_cache = {}  # Process memory
        self.l2_client = None  # Redis client placeholder
        self.access_patterns = {}
        self.version_vector = {}
    
    def calculate_temperature(self, key: str) -> float:
        """Calculate data temperature based on access patterns"""
        now = time.time()
        pattern = self.access_patterns.get(key, [])
        
        # Remove old access records (older than 1 hour)
        recent_accesses = [t for t in pattern if now - t < 3600]
        self.access_patterns[key] = recent_accesses
        
        if not recent_accesses:
            return 0.0
        
        # Temperature = access frequency + recency bonus
        frequency = len(recent_accesses) / 3600  # accesses per second
        recency_bonus = 1.0 / (now - recent_accesses[-1] + 1)
        
        return frequency + recency_bonus
    
    def determine_optimal_layer(self, temperature: float, data_size: int) -> CacheLayer:
        """Determine which cache layer should hold this data"""
        if temperature > 0.1 and data_size < 1024:  # Hot and small
            return CacheLayer.L1_PROCESS
        elif temperature > 0.01:  # Warm data
            return CacheLayer.L2_DISTRIBUTED
        else:  # Cold data
            return CacheLayer.L3_DATABASE
    
    async def get(self, key: str) -> Optional[Any]:
        """Get data with automatic layer promotion"""
        now = time.time()
        
        # Record access pattern
        if key not in self.access_patterns:
            self.access_patterns[key] = []
        self.access_patterns[key].append(now)
        
        # Try L1 first (process memory)
        if key in self.l1_cache:
            entry = self.l1_cache[key]
            if now < entry.last_access + entry.ttl:
                entry.last_access = now
                return entry.data
            else:
                del self.l1_cache[key]
        
        # Try L2 (distributed cache) - placeholder
        # In real implementation, this would be Redis/Memcached
        data = await self.get_from_l2(key)
        if data:
            # Promote to L1 if temperature is high enough
            temperature = self.calculate_temperature(key)
            if temperature > 0.1:
                await self.promote_to_l1(key, data, temperature)
            return data
        
        # Fallback to L3 (database)
        data = await self.get_from_database(key)
        if data:
            # Cache in appropriate layer
            temperature = self.calculate_temperature(key)
            await self.cache_at_optimal_layer(key, data, temperature)
        
        return data
    
    async def set(self, key: str, data: Any, consistency_level: str = "eventual"):
        """Set data with consistency guarantees"""
        now = time.time()
        version = self.version_vector.get(key, 0) + 1
        self.version_vector[key] = version
        
        temperature = self.calculate_temperature(key)
        data_size = len(json.dumps(data, default=str))
        
        entry = CacheEntry(
            data=data,
            version=version,
            temperature=temperature,
            last_access=now,
            ttl=self.calculate_ttl(temperature),
            layer_affinity=self.determine_optimal_layer(temperature, data_size)
        )
        
        if consistency_level == "strong":
            # Write-through: update all layers synchronously
            await self.write_through(key, entry)
        else:
            # Write-behind: update cache immediately, database async
            await self.write_behind(key, entry)
    
    def calculate_ttl(self, temperature: float) -> float:
        """Calculate TTL based on data temperature"""
        # Hot data lives longer in cache
        base_ttl = 3600  # 1 hour
        temperature_multiplier = min(temperature * 10, 5.0)
        return base_ttl * (1 + temperature_multiplier)
    
    async def promote_to_l1(self, key: str, data: Any, temperature: float):
        """Promote frequently accessed data to L1 cache"""
        if len(self.l1_cache) > 1000:  # L1 size limit
            # Evict coldest entry
            coldest_key = min(self.l1_cache.keys(), 
                            key=lambda k: self.l1_cache[k].temperature)
            del self.l1_cache[coldest_key]
        
        entry = CacheEntry(
            data=data,
            version=self.version_vector.get(key, 1),
            temperature=temperature,
            last_access=time.time(),
            ttl=self.calculate_ttl(temperature),
            layer_affinity=CacheLayer.L1_PROCESS
        )
        self.l1_cache[key] = entry
    
    async def get_from_l2(self, key: str) -> Optional[Any]:
        """Placeholder for distributed cache lookup"""
        # In real implementation: return await redis_client.get(key)
        return None
    
    async def get_from_database(self, key: str) -> Optional[Any]:
        """Placeholder for database lookup"""
        # In real implementation: return await db.fetch(key)
        return f"database_value_for_{key}"
    
    async def write_through(self, key: str, entry: CacheEntry):
        """Write to all cache layers synchronously"""
        # Update L1 if appropriate
        if entry.layer_affinity == CacheLayer.L1_PROCESS:
            self.l1_cache[key] = entry
        
        # Update L2 (distributed cache)
        # await self.l2_client.set(key, entry.data, ex=int(entry.ttl))
        
        # Update database
        # await self.database.update(key, entry.data)
        pass
    
    async def write_behind(self, key: str, entry: CacheEntry):
        """Write to cache immediately, database asynchronously"""
        # Update cache layers immediately
        if entry.layer_affinity == CacheLayer.L1_PROCESS:
            self.l1_cache[key] = entry
        
        # Schedule async database write
        asyncio.create_task(self.async_database_write(key, entry))
    
    async def async_database_write(self, key: str, entry: CacheEntry):
        """Asynchronous database write with retry logic"""
        max_retries = 3
        for attempt in range(max_retries):
            try:
                # await self.database.update(key, entry.data)
                break
            except Exception as e:
                if attempt == max_retries - 1:
                    # Log failure, possibly send to dead letter queue
                    print(f"Failed to write {key} to database after {max_retries} attempts")
                else:
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff

# Usage example
async def main():
    cache = ThermalCacheManager()
    
    # Simulate hot data access pattern
    for i in range(10):
        await cache.set(f"user:123", {"name": "Alice", "age": 30})
        data = await cache.get("user:123")
        print(f"Access {i}: {data}")
        await asyncio.sleep(0.1)
    
    # Check final temperature
    temp = cache.calculate_temperature("user:123")
    print(f"Final temperature for user:123: {temp}")

if __name__ == "__main__":
    asyncio.run(main())