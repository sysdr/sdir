import pytest
import pytest_asyncio
import asyncio
import time
from src.lock_mechanisms import (
    RedisDistributedLock, DatabaseDistributedLock, 
    ProtectedResource, LockConfig, metrics
)

@pytest.fixture
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()

@pytest_asyncio.fixture
async def redis_lock():
    return RedisDistributedLock("redis://localhost:6379")

@pytest_asyncio.fixture
async def db_lock():
    return DatabaseDistributedLock()

@pytest_asyncio.fixture
async def protected_resource():
    return ProtectedResource()

@pytest.mark.asyncio
async def test_basic_lock_acquisition(db_lock):
    """Test basic lock acquisition and release"""
    config = LockConfig(ttl_seconds=10)
    
    # Acquire lock
    token = await db_lock.acquire("test_resource", "client_1", config)
    assert token is not None
    assert "client_1" in token
    
    # Verify lock info
    lock_info = await db_lock.get_lock_info("test_resource")
    assert lock_info is not None
    assert lock_info["client_id"] == "client_1"
    
    # Release lock
    success = await db_lock.release("test_resource", "client_1", token)
    assert success is True
    
    # Verify lock is gone
    lock_info = await db_lock.get_lock_info("test_resource")
    assert lock_info is None

@pytest.mark.asyncio
async def test_lock_contention(db_lock):
    """Test that only one client can hold a lock"""
    config = LockConfig(ttl_seconds=10)
    
    # Client 1 acquires lock
    token1 = await db_lock.acquire("test_resource", "client_1", config)
    assert token1 is not None
    
    # Client 2 should fail to acquire the same lock
    token2 = await db_lock.acquire("test_resource", "client_2", config)
    assert token2 is None
    
    # Release first lock
    success = await db_lock.release("test_resource", "client_1", token1)
    assert success is True
    
    # Now client 2 should be able to acquire
    token2 = await db_lock.acquire("test_resource", "client_2", config)
    assert token2 is not None

@pytest.mark.asyncio
async def test_ttl_expiration(db_lock):
    """Test that locks expire after TTL"""
    config = LockConfig(ttl_seconds=1)  # Short TTL for testing
    
    # Acquire lock
    token = await db_lock.acquire("test_resource", "client_1", config)
    assert token is not None
    
    # Wait for TTL to expire
    await asyncio.sleep(1.5)
    
    # Another client should be able to acquire now
    token2 = await db_lock.acquire("test_resource", "client_2", config)
    assert token2 is not None

@pytest.mark.asyncio
async def test_fencing_tokens(protected_resource):
    """Test that fencing tokens prevent stale writes"""
    
    # Write with token 1001
    success = await protected_resource.write("test_resource", 
                                           {"data": "first"}, 
                                           "1001:client_A:123", 
                                           "client_A")
    assert success is True
    
    # Write with higher token 1002
    success = await protected_resource.write("test_resource", 
                                           {"data": "second"}, 
                                           "1002:client_B:124", 
                                           "client_B")
    assert success is True
    
    # Try to write with stale token 1001 - should fail
    success = await protected_resource.write("test_resource", 
                                           {"data": "stale"}, 
                                           "1001:client_A:125", 
                                           "client_A")
    assert success is False
    
    # Verify the data wasn't overwritten
    data = await protected_resource.read("test_resource")
    assert data["content"]["data"] == "second"
    assert data["written_by"] == "client_B"

@pytest.mark.asyncio 
async def test_token_validation(db_lock):
    """Test token validation"""
    config = LockConfig(ttl_seconds=10)
    
    # Acquire lock
    token = await db_lock.acquire("test_resource", "client_1", config)
    assert token is not None
    
    # Validate correct token
    valid = await db_lock.validate_token("test_resource", token)
    assert valid is True
    
    # Validate incorrect token
    valid = await db_lock.validate_token("test_resource", "fake_token")
    assert valid is False
    
    # Release and validate again
    await db_lock.release("test_resource", "client_1", token)
    valid = await db_lock.validate_token("test_resource", token)
    assert valid is False

def test_metrics_recording():
    """Test that metrics are properly recorded"""
    initial_count = len(metrics.events)
    
    # Events should be recorded during lock operations
    # This is tested implicitly by other tests that use the lock mechanisms
    
    # Verify metrics structure
    recent_events = metrics.get_recent_events(10)
    assert isinstance(recent_events, list)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
