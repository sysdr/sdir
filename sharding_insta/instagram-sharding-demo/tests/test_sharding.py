"""
Test suite for Instagram sharding demo
"""

import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from app import ShardManager, User, Photo, InMemoryStorage
from datetime import datetime

def test_shard_manager_basic():
    """Test basic shard manager functionality"""
    sm = ShardManager(num_shards=4)
    
    # Test user ID sharding
    assert sm.get_shard_for_user(100) == 0  # 100 % 4 = 0
    assert sm.get_shard_for_user(101) == 1  # 101 % 4 = 1
    assert sm.get_shard_for_user(102) == 2  # 102 % 4 = 2
    assert sm.get_shard_for_user(103) == 3  # 103 % 4 = 3

def test_user_id_generation():
    """Test Instagram-style user ID generation"""
    sm = ShardManager()
    
    user_id = sm.generate_user_id()
    assert isinstance(user_id, int)
    assert user_id > 0
    
    # Generate multiple IDs and ensure they're unique
    ids = set()
    for _ in range(1000):
        uid = sm.generate_user_id()
        assert uid not in ids
        ids.add(uid)

def test_storage_operations():
    """Test in-memory storage operations"""
    storage = InMemoryStorage()
    sm = ShardManager(num_shards=4)
    
    # Create test user
    user = User(
        user_id=100,
        username="testuser",
        email="test@example.com",
        shard_id=sm.get_shard_for_user(100),
        created_at=datetime.now()
    )
    
    storage.add_user(user)
    retrieved_user = storage.get_user(100)
    
    assert retrieved_user is not None
    assert retrieved_user.username == "testuser"
    assert retrieved_user.shard_id == 0  # 100 % 4 = 0

def test_hot_shard_detection():
    """Test hot shard detection logic"""
    sm = ShardManager(num_shards=4)
    sm.hot_threshold = 10  # Low threshold for testing
    
    # Generate load on shard 0
    for _ in range(15):
        sm.update_shard_stats(0, 'query')
    
    hot_shards = sm.get_hot_shards()
    assert 0 in hot_shards

def test_shard_distribution():
    """Test that users are distributed across shards"""
    sm = ShardManager(num_shards=8)
    storage = InMemoryStorage()
    
    # Add users and check distribution
    shard_counts = {i: 0 for i in range(8)}
    
    for i in range(800):  # 100 users per shard on average
        user_id = sm.generate_user_id()
        shard_id = sm.get_shard_for_user(user_id)
        shard_counts[shard_id] += 1
    
    # Each shard should have some users (rough distribution)
    for count in shard_counts.values():
        assert count > 0, "All shards should have some users"

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
