import asyncio
import time
import random
import json
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from typing import Optional, Dict, List
from contextlib import asynccontextmanager
import redis.asyncio as aioredis
import uuid
from threading import Thread
import weakref

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class LockConfig:
    ttl_seconds: int = 30
    retry_attempts: int = 3
    backoff_base: float = 0.1
    fencing_enabled: bool = True

@dataclass
class LockEvent:
    timestamp: float
    event_type: str  # acquire, release, expire, reject
    client_id: str
    resource_id: str
    token: Optional[str] = None
    details: Optional[str] = None

class LockMetrics:
    def __init__(self):
        self.events: List[LockEvent] = []
        self.active_locks: Dict[str, dict] = {}
        
    def record_event(self, event: LockEvent):
        self.events.append(event)
        logger.info(f"Lock Event: {event.event_type} - Client: {event.client_id} - Resource: {event.resource_id}")
        
    def get_recent_events(self, limit: int = 20) -> List[dict]:
        return [asdict(event) for event in self.events[-limit:]]

# Global metrics instance
metrics = LockMetrics()

class DistributedLock(ABC):
    @abstractmethod
    async def acquire(self, resource_id: str, client_id: str, config: LockConfig) -> Optional[str]:
        """Returns fencing token on success, None on failure"""
        pass
    
    @abstractmethod
    async def release(self, resource_id: str, client_id: str, token: str) -> bool:
        pass
    
    @abstractmethod
    async def validate_token(self, resource_id: str, token: str) -> bool:
        pass
    
    @abstractmethod
    async def get_lock_info(self, resource_id: str) -> Optional[dict]:
        pass

class RedisDistributedLock(DistributedLock):
    def __init__(self, redis_url: str = "redis://redis:6379"):
        self.redis_url = redis_url
        self.redis = None
        self.token_counter = 1000
        
    async def _get_redis(self):
        if not self.redis:
            self.redis = await aioredis.from_url(self.redis_url, decode_responses=True)
        return self.redis
        
    async def acquire(self, resource_id: str, client_id: str, config: LockConfig) -> Optional[str]:
        redis = await self._get_redis()
        
        # Generate monotonic token for fencing
        self.token_counter += 1
        token = f"{self.token_counter}:{client_id}:{int(time.time())}"
        
        lock_key = f"lock:{resource_id}"
        lock_value = json.dumps({
            "client_id": client_id,
            "token": token,
            "acquired_at": time.time(),
            "ttl": config.ttl_seconds
        })
        
        # Use SET with NX (only if not exists) and EX (expiration)
        result = await redis.set(lock_key, lock_value, nx=True, ex=config.ttl_seconds)
        
        if result:
            metrics.record_event(LockEvent(
                timestamp=time.time(),
                event_type="acquire",
                client_id=client_id,
                resource_id=resource_id,
                token=token,
                details=f"Redis lock acquired with TTL {config.ttl_seconds}s"
            ))
            metrics.active_locks[resource_id] = {
                "client_id": client_id,
                "token": token,
                "mechanism": "Redis",
                "acquired_at": time.time()
            }
            return token
        else:
            metrics.record_event(LockEvent(
                timestamp=time.time(),
                event_type="acquire_failed",
                client_id=client_id,
                resource_id=resource_id,
                details="Lock already held by another client"
            ))
            return None
    
    async def release(self, resource_id: str, client_id: str, token: str) -> bool:
        redis = await self._get_redis()
        lock_key = f"lock:{resource_id}"
        
        # Lua script for atomic check-and-release
        lua_script = """
        local current = redis.call('GET', KEYS[1])
        if current then
            local data = cjson.decode(current)
            if data.client_id == ARGV[1] and data.token == ARGV[2] then
                redis.call('DEL', KEYS[1])
                return 1
            end
        end
        return 0
        """
        
        result = await redis.eval(lua_script, 1, lock_key, client_id, token)
        
        if result:
            metrics.record_event(LockEvent(
                timestamp=time.time(),
                event_type="release",
                client_id=client_id,
                resource_id=resource_id,
                token=token
            ))
            if resource_id in metrics.active_locks:
                del metrics.active_locks[resource_id]
            return True
        return False
    
    async def validate_token(self, resource_id: str, token: str) -> bool:
        redis = await self._get_redis()
        lock_key = f"lock:{resource_id}"
        
        current = await redis.get(lock_key)
        if current:
            data = json.loads(current)
            return data["token"] == token
        return False
    
    async def get_lock_info(self, resource_id: str) -> Optional[dict]:
        redis = await self._get_redis()
        lock_key = f"lock:{resource_id}"
        
        current = await redis.get(lock_key)
        if current:
            return json.loads(current)
        return None

class DatabaseDistributedLock(DistributedLock):
    """Simulated database-based locking using in-memory storage"""
    
    def __init__(self):
        self.locks: Dict[str, dict] = {}
        self.token_counter = 2000
        self._lock = asyncio.Lock()
    
    async def acquire(self, resource_id: str, client_id: str, config: LockConfig) -> Optional[str]:
        async with self._lock:
            current_time = time.time()
            
            # Check if lock exists and is not expired
            if resource_id in self.locks:
                lock_info = self.locks[resource_id]
                if current_time < lock_info["expires_at"]:
                    metrics.record_event(LockEvent(
                        timestamp=current_time,
                        event_type="acquire_failed",
                        client_id=client_id,
                        resource_id=resource_id,
                        details="Lock still held and not expired"
                    ))
                    return None
                else:
                    # Lock expired, remove it
                    del self.locks[resource_id]
                    metrics.record_event(LockEvent(
                        timestamp=current_time,
                        event_type="expire",
                        client_id=lock_info["client_id"],
                        resource_id=resource_id,
                        token=lock_info["token"],
                        details="Lock expired due to TTL"
                    ))
            
            # Acquire new lock
            self.token_counter += 1
            token = f"{self.token_counter}:{client_id}:{int(current_time)}"
            
            self.locks[resource_id] = {
                "client_id": client_id,
                "token": token,
                "acquired_at": current_time,
                "expires_at": current_time + config.ttl_seconds
            }
            
            metrics.record_event(LockEvent(
                timestamp=current_time,
                event_type="acquire",
                client_id=client_id,
                resource_id=resource_id,
                token=token,
                details=f"Database lock acquired with TTL {config.ttl_seconds}s"
            ))
            
            metrics.active_locks[resource_id] = {
                "client_id": client_id,
                "token": token,
                "mechanism": "Database",
                "acquired_at": current_time
            }
            
            return token
    
    async def release(self, resource_id: str, client_id: str, token: str) -> bool:
        async with self._lock:
            if resource_id in self.locks:
                lock_info = self.locks[resource_id]
                if lock_info["client_id"] == client_id and lock_info["token"] == token:
                    del self.locks[resource_id]
                    metrics.record_event(LockEvent(
                        timestamp=time.time(),
                        event_type="release",
                        client_id=client_id,
                        resource_id=resource_id,
                        token=token
                    ))
                    if resource_id in metrics.active_locks:
                        del metrics.active_locks[resource_id]
                    return True
            return False
    
    async def validate_token(self, resource_id: str, token: str) -> bool:
        if resource_id in self.locks:
            lock_info = self.locks[resource_id]
            if time.time() < lock_info["expires_at"]:
                return lock_info["token"] == token
        return False
    
    async def get_lock_info(self, resource_id: str) -> Optional[dict]:
        if resource_id in self.locks:
            lock_info = self.locks[resource_id].copy()
            if time.time() < lock_info["expires_at"]:
                return lock_info
            else:
                # Clean up expired lock
                del self.locks[resource_id]
        return None

class ProtectedResource:
    """Simulates a protected resource that validates fencing tokens"""
    
    def __init__(self):
        self.data = {}
        self.highest_token_seen = {}
        self._lock = asyncio.Lock()
    
    async def write(self, resource_id: str, data: dict, token: str, client_id: str) -> bool:
        async with self._lock:
            # Extract token number for comparison
            try:
                token_num = int(token.split(':')[0])
            except (ValueError, IndexError):
                metrics.record_event(LockEvent(
                    timestamp=time.time(),
                    event_type="reject",
                    client_id=client_id,
                    resource_id=resource_id,
                    token=token,
                    details="Invalid token format"
                ))
                return False
            
            # Check if this token is newer than the highest seen
            if resource_id in self.highest_token_seen:
                if token_num <= self.highest_token_seen[resource_id]:
                    metrics.record_event(LockEvent(
                        timestamp=time.time(),
                        event_type="reject",
                        client_id=client_id,
                        resource_id=resource_id,
                        token=token,
                        details=f"Stale token: {token_num} <= {self.highest_token_seen[resource_id]}"
                    ))
                    return False
            
            # Accept the write
            self.highest_token_seen[resource_id] = token_num
            self.data[resource_id] = {
                "content": data,
                "written_by": client_id,
                "token": token,
                "timestamp": time.time()
            }
            
            logger.info(f"Resource write accepted: {client_id} with token {token}")
            return True
    
    async def read(self, resource_id: str) -> Optional[dict]:
        return self.data.get(resource_id)

@asynccontextmanager
async def distributed_lock(lock_service: DistributedLock, 
                          resource_id: str, 
                          client_id: str,
                          config: LockConfig = LockConfig()):
    token = None
    start_time = time.time()
    
    try:
        token = await lock_service.acquire(resource_id, client_id, config)
        if not token:
            raise Exception(f"Failed to acquire lock for {resource_id}")
        
        yield token
        
    finally:
        if token:
            released = await lock_service.release(resource_id, client_id, token)
            if released:
                logger.info(f"Lock released successfully for {resource_id}")
            else:
                logger.warning(f"Failed to release lock for {resource_id}")

# Demo scenarios
class LockingScenarios:
    def __init__(self):
        self.redis_lock = RedisDistributedLock()
        self.db_lock = DatabaseDistributedLock()
        self.resource = ProtectedResource()
    
    async def scenario_normal_operation(self):
        """Demonstrate normal lock acquisition and release"""
        logger.info("=== Normal Operation Scenario ===")
        
        try:
            async with distributed_lock(self.redis_lock, "account_123", "client_A") as token:
                logger.info(f"Client A acquired lock with token: {token}")
                
                # Simulate work with the protected resource
                success = await self.resource.write("account_123", {"balance": 1000}, token, "client_A")
                logger.info(f"Resource write success: {success}")
                
                await asyncio.sleep(2)  # Simulate processing time
                
        except Exception as e:
            logger.error(f"Error in normal operation: {e}")
    
    async def scenario_lock_contention(self):
        """Demonstrate multiple clients competing for the same lock"""
        logger.info("=== Lock Contention Scenario ===")
        
        async def client_task(client_id: str, delay: float):
            await asyncio.sleep(delay)
            try:
                async with distributed_lock(self.redis_lock, "shared_resource", client_id, 
                                          LockConfig(ttl_seconds=5)) as token:
                    logger.info(f"{client_id} acquired lock with token: {token}")
                    
                    # Write to resource
                    success = await self.resource.write("shared_resource", 
                                                       {"data": f"written_by_{client_id}"}, 
                                                       token, client_id)
                    logger.info(f"{client_id} resource write success: {success}")
                    
                    await asyncio.sleep(2)  # Hold lock for 2 seconds
                    
            except Exception as e:
                logger.error(f"{client_id} failed to acquire lock: {e}")
        
        # Start multiple clients
        await asyncio.gather(
            client_task("client_A", 0),
            client_task("client_B", 0.5),
            client_task("client_C", 1.0)
        )
    
    async def scenario_process_pause_simulation(self):
        """Simulate the dangerous process pause scenario"""
        logger.info("=== Process Pause Simulation ===")
        
        # Client A acquires lock
        client_a_token = await self.redis_lock.acquire("critical_resource", "client_A", 
                                                      LockConfig(ttl_seconds=3))
        logger.info(f"Client A acquired lock: {client_a_token}")
        
        # Simulate Client A writing successfully
        success = await self.resource.write("critical_resource", {"initial": "data"}, 
                                           client_a_token, "client_A")
        logger.info(f"Client A initial write success: {success}")
        
        # Simulate Client A pausing (e.g., GC pause) - we'll simulate with sleep
        logger.info("Client A pausing (simulating GC/network issue)...")
        await asyncio.sleep(4)  # Sleep longer than TTL
        
        # Meanwhile, Client B tries to acquire the lock (should succeed after TTL)
        await asyncio.sleep(0.1)  # Small delay to ensure TTL expired
        client_b_token = await self.redis_lock.acquire("critical_resource", "client_B", 
                                                      LockConfig(ttl_seconds=10))
        logger.info(f"Client B acquired lock: {client_b_token}")
        
        # Client B writes successfully
        success = await self.resource.write("critical_resource", {"updated": "by_client_B"}, 
                                           client_b_token, "client_B")
        logger.info(f"Client B write success: {success}")
        
        # Client A "resumes" and tries to write with stale token
        logger.info("Client A resuming and attempting write with stale token...")
        success = await self.resource.write("critical_resource", {"stale": "write_attempt"}, 
                                           client_a_token, "client_A")
        logger.info(f"Client A stale write success: {success}")  # Should be False
        
        # Clean up
        await self.redis_lock.release("critical_resource", "client_B", client_b_token)
    
    async def scenario_mechanism_comparison(self):
        """Compare different locking mechanisms"""
        logger.info("=== Mechanism Comparison ===")
        
        # Test Redis vs Database locking
        redis_start = time.time()
        async with distributed_lock(self.redis_lock, "redis_test", "client_1"):
            await asyncio.sleep(0.1)
        redis_time = time.time() - redis_start
        
        db_start = time.time()
        async with distributed_lock(self.db_lock, "db_test", "client_1"):
            await asyncio.sleep(0.1)
        db_time = time.time() - db_start
        
        logger.info(f"Redis lock duration: {redis_time:.3f}s")
        logger.info(f"Database lock duration: {db_time:.3f}s")

async def run_all_scenarios():
    """Run all demonstration scenarios"""
    scenarios = LockingScenarios()
    
    await scenarios.scenario_normal_operation()
    await asyncio.sleep(1)
    
    await scenarios.scenario_lock_contention()
    await asyncio.sleep(1)
    
    await scenarios.scenario_process_pause_simulation()
    await asyncio.sleep(1)
    
    await scenarios.scenario_mechanism_comparison()
    
    # Print final metrics
    logger.info("=== Final Metrics ===")
    logger.info(f"Total events recorded: {len(metrics.events)}")
    logger.info(f"Active locks: {len(metrics.active_locks)}")

if __name__ == "__main__":
    asyncio.run(run_all_scenarios())
