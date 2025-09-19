"""
Simple test suite for checkpoint and rollback recovery
"""
import pytest
import asyncio
import tempfile
import os
from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Import from src
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))
from task_processor import TaskProcessor, Task, Checkpoint, Base, CheckpointManager

@pytest.mark.asyncio
async def test_basic_functionality():
    """Test basic checkpoint functionality"""
    # Use in-memory SQLite for tests
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        # Create checkpoint manager (without Redis for simple test)
        checkpoint_manager = CheckpointManager(session, None)
        
        # Create some test tasks
        tasks = [
            Task(id="task1", status="pending", data={"type": "test"}),
            Task(id="task2", status="processing", data={"type": "test"}, progress=0.5),
            Task(id="task3", status="completed", data={"type": "test"}, progress=1.0)
        ]
        
        for task in tasks:
            session.add(task)
        await session.commit()
        
        # Create checkpoint
        checkpoint_id = await checkpoint_manager.create_checkpoint()
        
        assert checkpoint_id is not None
        assert checkpoint_id.startswith("checkpoint_")
        
        # Verify checkpoint in database
        result = await session.execute(
            sa.select(Checkpoint).where(Checkpoint.id == checkpoint_id)
        )
        checkpoint = result.scalar_one()
        
        assert checkpoint.is_consistent
        assert len(checkpoint.task_states) == 2  # pending + processing tasks
        assert "task1" in checkpoint.task_states
        assert "task2" in checkpoint.task_states
        assert "task3" not in checkpoint.task_states  # completed task not in active state

@pytest.mark.asyncio
async def test_rollback_functionality():
    """Test rollback to checkpoint"""
    # Use in-memory SQLite for tests
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as session:
        checkpoint_manager = CheckpointManager(session, None)
        
        # Create initial state
        initial_tasks = [
            Task(id="task1", status="pending", data={"type": "test"}),
            Task(id="task2", status="processing", data={"type": "test"}, progress=0.3)
        ]
        
        for task in initial_tasks:
            session.add(task)
        await session.commit()
        
        # Create checkpoint
        checkpoint_id = await checkpoint_manager.create_checkpoint()
        
        # Modify state after checkpoint
        await session.execute(
            sa.update(Task)
            .where(Task.id == "task1")
            .values(status="failed")
        )
        
        # Add new task after checkpoint
        new_task = Task(id="task3", status="pending", data={"type": "test"})
        session.add(new_task)
        await session.commit()
        
        # Verify modified state
        result = await session.execute(sa.select(Task))
        tasks_before_rollback = result.scalars().all()
        assert len(tasks_before_rollback) == 3
        
        # Perform rollback
        success = await checkpoint_manager.rollback_to_checkpoint(checkpoint_id)
        assert success
        
        # Verify rollback
        result = await session.execute(sa.select(Task))
        tasks_after_rollback = result.scalars().all()
        
        # Should have original 2 tasks
        assert len(tasks_after_rollback) == 2
        
        # Task1 should be back to pending status
        task1 = next(t for t in tasks_after_rollback if t.id == "task1")
        assert task1.status == "pending"
        
        # Task3 should be removed (created after checkpoint)
        task3_exists = any(t.id == "task3" for t in tasks_after_rollback)
        assert not task3_exists

if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])
