"""
Test suite for checkpoint and rollback recovery
"""
import pytest
import asyncio
import json
import tempfile
import os
from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
import redis.asyncio as redis

# Import from src
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))
from task_processor import TaskProcessor, Task, Checkpoint, Base, CheckpointManager

@pytest.fixture
async def test_db():
    """Create test database"""
    # Use in-memory SQLite for tests
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    session = async_session()
    
    yield session
    
    await session.close()

@pytest.fixture
async def redis_client():
    """Redis client for testing"""
    # Use Redis from environment or default
    redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
    client = redis.from_url(redis_url)
    
    # Clear test data
    await client.flushdb()
    
    yield client
    
    await client.close()

@pytest.mark.asyncio
async def test_checkpoint_creation(test_db, redis_client):
    """Test checkpoint creation functionality"""
    checkpoint_manager = CheckpointManager(test_db, redis_client)
    
    # Create some test tasks
    tasks = [
        Task(id="task1", status="pending", data={"type": "test"}),
        Task(id="task2", status="processing", data={"type": "test"}, progress=0.5),
        Task(id="task3", status="completed", data={"type": "test"}, progress=1.0)
    ]
    
    for task in tasks:
        test_db.add(task)
    await test_db.commit()
    
    # Create checkpoint
    checkpoint_id = await checkpoint_manager.create_checkpoint()
    
    assert checkpoint_id is not None
    assert checkpoint_id.startswith("checkpoint_")
    
    # Verify checkpoint in database
    result = await test_db.execute(
        sa.select(Checkpoint).where(Checkpoint.id == checkpoint_id)
    )
    checkpoint = result.scalar_one()
    
    assert checkpoint.is_consistent
    assert len(checkpoint.task_states) == 2  # pending + processing tasks
    assert "task1" in checkpoint.task_states
    assert "task2" in checkpoint.task_states
    assert "task3" not in checkpoint.task_states  # completed task not in active state

@pytest.mark.asyncio
async def test_rollback_functionality(test_db, redis_client):
    """Test rollback to checkpoint"""
    checkpoint_manager = CheckpointManager(test_db, redis_client)
    
    # Create initial state
    initial_tasks = [
        Task(id="task1", status="pending", data={"type": "test"}),
        Task(id="task2", status="processing", data={"type": "test"}, progress=0.3)
    ]
    
    for task in initial_tasks:
        test_db.add(task)
    await test_db.commit()
    
    # Create checkpoint
    checkpoint_id = await checkpoint_manager.create_checkpoint()
    
    # Modify state after checkpoint
    await test_db.execute(
        sa.update(Task)
        .where(Task.id == "task1")
        .values(status="failed")
    )
    
    # Add new task after checkpoint
    new_task = Task(id="task3", status="pending", data={"type": "test"})
    test_db.add(new_task)
    await test_db.commit()
    
    # Verify modified state
    result = await test_db.execute(sa.select(Task))
    tasks_before_rollback = result.scalars().all()
    assert len(tasks_before_rollback) == 3
    
    # Perform rollback
    success = await checkpoint_manager.rollback_to_checkpoint(checkpoint_id)
    assert success
    
    # Verify rollback
    result = await test_db.execute(sa.select(Task))
    tasks_after_rollback = result.scalars().all()
    
    # Should have original 2 tasks
    assert len(tasks_after_rollback) == 2
    
    # Task1 should be back to pending status
    task1 = next(t for t in tasks_after_rollback if t.id == "task1")
    assert task1.status == "pending"
    
    # Task3 should be removed (created after checkpoint)
    task3_exists = any(t.id == "task3" for t in tasks_after_rollback)
    assert not task3_exists

@pytest.mark.asyncio
async def test_task_processing_with_failure(test_db, redis_client):
    """Test task processing with simulated failures"""
    # Create task that will fail
    failing_task = Task(
        id="failing_task",
        status="pending",
        data={"type": "test", "should_fail": True, "steps": 8}
    )
    test_db.add(failing_task)
    await test_db.commit()
    
    # Create checkpoint manager
    checkpoint_manager = CheckpointManager(test_db, redis_client)
    
    # Create initial checkpoint
    checkpoint_id = await checkpoint_manager.create_checkpoint()
    
    # Process the failing task (would be done by TaskProcessor)
    failing_task.status = "processing"
    failing_task.progress = 0.6
    await test_db.commit()
    
    # Simulate failure
    failing_task.status = "failed"
    await test_db.commit()
    
    # Rollback should restore original state
    success = await checkpoint_manager.rollback_to_checkpoint(checkpoint_id)
    assert success
    
    # Verify task is back to pending
    result = await test_db.execute(
        sa.select(Task).where(Task.id == "failing_task")
    )
    restored_task = result.scalar_one()
    assert restored_task.status == "pending"
    assert restored_task.progress == 0.0

@pytest.mark.asyncio
async def test_concurrent_checkpoint_operations(test_db, redis_client):
    """Test concurrent checkpoint and rollback operations"""
    checkpoint_manager = CheckpointManager(test_db, redis_client)
    
    # Create multiple tasks
    tasks = [
        Task(id=f"task{i}", status="pending", data={"type": "test"})
        for i in range(5)
    ]
    
    for task in tasks:
        test_db.add(task)
    await test_db.commit()
    
    # Create multiple checkpoints concurrently
    checkpoint_tasks = [
        checkpoint_manager.create_checkpoint()
        for _ in range(3)
    ]
    
    checkpoint_ids = await asyncio.gather(*checkpoint_tasks)
    
    # All checkpoints should be created successfully
    assert len(checkpoint_ids) == 3
    assert all(cp_id is not None for cp_id in checkpoint_ids)
    assert len(set(checkpoint_ids)) == 3  # All unique
    
    # Test rollback to latest checkpoint
    latest_checkpoint = max(checkpoint_ids)
    success = await checkpoint_manager.rollback_to_checkpoint(latest_checkpoint)
    assert success

if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])
