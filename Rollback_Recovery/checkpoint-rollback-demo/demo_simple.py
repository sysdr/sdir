#!/usr/bin/env python3
"""
Simple demo script for checkpoint and rollback recovery
Uses SQLite for easier setup
"""
import asyncio
import json
import time
import uuid
import os
import tempfile
from datetime import datetime
from typing import List, Dict, Any
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Database models
Base = declarative_base()

class Task(Base):
    __tablename__ = 'tasks'
    
    id = sa.Column(sa.String, primary_key=True)
    status = sa.Column(sa.String, default='pending')
    data = sa.Column(sa.JSON)
    created_at = sa.Column(sa.DateTime, default=datetime.utcnow)
    updated_at = sa.Column(sa.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    checkpoint_id = sa.Column(sa.String, nullable=True)
    progress = sa.Column(sa.Float, default=0.0)

class Checkpoint(Base):
    __tablename__ = 'checkpoints'
    
    id = sa.Column(sa.String, primary_key=True)
    created_at = sa.Column(sa.DateTime, default=datetime.utcnow)
    system_state = sa.Column(sa.JSON)
    task_states = sa.Column(sa.JSON)
    is_consistent = sa.Column(sa.Boolean, default=True)

class SimpleDemo:
    def __init__(self):
        self.db_engine = None
        self.db_session = None
        
    async def initialize(self):
        """Initialize SQLite database"""
        # Use in-memory SQLite for demo
        self.db_engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
        async_session = sessionmaker(self.db_engine, class_=AsyncSession, expire_on_commit=False)
        
        # Create tables
        async with self.db_engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        
        self.db_session = async_session()
        logger.info("Demo initialized with SQLite database")
    
    async def create_task(self, task_type: str, steps: int = 10, should_fail: bool = False) -> str:
        """Create a new task"""
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        task = Task(
            id=task_id,
            status='pending',
            data={
                'type': task_type,
                'steps': steps,
                'should_fail': should_fail,
                'created_by': 'demo'
            }
        )
        
        self.db_session.add(task)
        await self.db_session.commit()
        
        logger.info("Task created", task_id=task_id, task_type=task_type)
        return task_id
    
    async def create_checkpoint(self) -> str:
        """Create a checkpoint"""
        checkpoint_id = f"checkpoint_{int(time.time())}_{uuid.uuid4().hex[:8]}"
        
        # Get current tasks
        result = await self.db_session.execute(sa.select(Task))
        all_tasks = result.scalars().all()
        
        # Create system state
        system_state = {
            'active_tasks': [t.id for t in all_tasks if t.status in ['pending', 'processing']],
            'completed_tasks': [t.id for t in all_tasks if t.status == 'completed'],
            'failed_tasks': [t.id for t in all_tasks if t.status == 'failed'],
            'last_checkpoint': checkpoint_id,
            'uptime_seconds': time.time(),
            'processed_count': len([t for t in all_tasks if t.status == 'completed'])
        }
        
        # Create task states
        task_states = {}
        for task in all_tasks:
            if task.status in ['pending', 'processing']:
                task_states[task.id] = {
                    'task_id': task.id,
                    'status': task.status,
                    'progress': task.progress,
                    'data': task.data,
                    'checkpoint_id': checkpoint_id
                }
        
        # Store checkpoint
        checkpoint = Checkpoint(
            id=checkpoint_id,
            system_state=system_state,
            task_states=task_states,
            is_consistent=True
        )
        
        self.db_session.add(checkpoint)
        await self.db_session.commit()
        
        logger.info("Checkpoint created", checkpoint_id=checkpoint_id, task_count=len(task_states))
        return checkpoint_id
    
    async def process_task(self, task_id: str) -> bool:
        """Process a task"""
        try:
            # Get task
            result = await self.db_session.execute(sa.select(Task).where(Task.id == task_id))
            task = result.scalar_one()
            
            # Update status
            task.status = 'processing'
            await self.db_session.commit()
            
            logger.info("Processing task", task_id=task_id)
            
            # Simulate work
            steps = task.data.get('steps', 10)
            should_fail = task.data.get('should_fail', False)
            
            for step in range(steps):
                await asyncio.sleep(0.1)  # Simulate work
                
                # Update progress
                task.progress = (step + 1) / steps
                await self.db_session.commit()
                
                # Simulate failure if requested
                if should_fail and step > steps // 2:
                    raise Exception("Simulated task failure")
            
            # Mark completed
            task.status = 'completed'
            task.progress = 1.0
            await self.db_session.commit()
            
            logger.info("Task completed", task_id=task_id)
            return True
            
        except Exception as e:
            # Mark as failed
            task.status = 'failed'
            await self.db_session.commit()
            logger.error("Task failed", task_id=task_id, error=str(e))
            return False
    
    async def rollback_to_checkpoint(self, checkpoint_id: str) -> bool:
        """Rollback to checkpoint"""
        try:
            # Get checkpoint
            result = await self.db_session.execute(
                sa.select(Checkpoint).where(Checkpoint.id == checkpoint_id)
            )
            checkpoint = result.scalar_one()
            
            # Get task states from checkpoint
            task_states = checkpoint.task_states
            
            # Reset tasks to checkpoint state
            for task_id, task_state in task_states.items():
                await self.db_session.execute(
                    sa.update(Task)
                    .where(Task.id == task_id)
                    .values(
                        status=task_state['status'],
                        progress=task_state['progress'],
                        checkpoint_id=checkpoint_id,
                        updated_at=datetime.utcnow()
                    )
                )
            
            # Remove tasks created after checkpoint
            checkpoint_time = checkpoint.created_at
            await self.db_session.execute(
                sa.delete(Task).where(Task.created_at > checkpoint_time)
            )
            
            await self.db_session.commit()
            
            logger.info("Rollback completed", checkpoint_id=checkpoint_id, restored_tasks=len(task_states))
            return True
            
        except Exception as e:
            logger.error("Rollback failed", error=str(e), checkpoint_id=checkpoint_id)
            await self.db_session.rollback()
            return False
    
    async def get_stats(self) -> Dict[str, Any]:
        """Get current system statistics"""
        # Task counts by status
        result = await self.db_session.execute(
            sa.select(Task.status, sa.func.count(Task.id))
            .group_by(Task.status)
        )
        task_counts = dict(result.fetchall())
        
        # Recent checkpoints
        result = await self.db_session.execute(
            sa.select(Checkpoint)
            .order_by(Checkpoint.created_at.desc())
            .limit(5)
        )
        checkpoints = result.scalars().all()
        
        # Active tasks
        result = await self.db_session.execute(
            sa.select(Task)
            .where(Task.status.in_(['pending', 'processing']))
            .order_by(Task.updated_at.desc())
        )
        active_tasks = result.scalars().all()
        
        return {
            'task_counts': task_counts,
            'checkpoints': [
                {
                    'id': cp.id,
                    'created_at': cp.created_at.isoformat(),
                    'is_consistent': cp.is_consistent,
                    'task_count': len(cp.task_states) if cp.task_states else 0
                }
                for cp in checkpoints
            ],
            'active_tasks': [
                {
                    'id': task.id,
                    'status': task.status,
                    'progress': task.progress,
                    'created_at': task.created_at.isoformat(),
                    'data': task.data
                }
                for task in active_tasks
            ],
            'timestamp': datetime.utcnow().isoformat()
        }
    
    async def demo_scenario(self):
        """Run a complete demo scenario"""
        print("🚀 Starting Checkpoint and Rollback Recovery Demo")
        print("=" * 60)
        
        # Create initial tasks
        print("\n📝 Creating demo tasks...")
        task1 = await self.create_task("data_processing", 5, False)
        task2 = await self.create_task("file_conversion", 8, False)
        task3 = await self.create_task("batch_calculation", 10, True)  # This will fail
        
        # Show initial stats
        stats = await self.get_stats()
        print(f"\n📊 Initial Stats:")
        print(f"   Pending: {stats['task_counts'].get('pending', 0)}")
        print(f"   Processing: {stats['task_counts'].get('processing', 0)}")
        print(f"   Completed: {stats['task_counts'].get('completed', 0)}")
        print(f"   Failed: {stats['task_counts'].get('failed', 0)}")
        
        # Create checkpoint
        print("\n💾 Creating checkpoint...")
        checkpoint_id = await self.create_checkpoint()
        print(f"   Checkpoint ID: {checkpoint_id}")
        
        # Process tasks
        print("\n⚙️  Processing tasks...")
        await self.process_task(task1)
        await self.process_task(task2)
        await self.process_task(task3)  # This will fail
        
        # Show stats after processing
        stats = await self.get_stats()
        print(f"\n📊 Stats after processing:")
        print(f"   Pending: {stats['task_counts'].get('pending', 0)}")
        print(f"   Processing: {stats['task_counts'].get('processing', 0)}")
        print(f"   Completed: {stats['task_counts'].get('completed', 0)}")
        print(f"   Failed: {stats['task_counts'].get('failed', 0)}")
        
        # Create more tasks after checkpoint
        print("\n📝 Creating additional tasks...")
        task4 = await self.create_task("report_generation", 6, False)
        task5 = await self.create_task("data_analysis", 7, False)
        
        # Show stats before rollback
        stats = await self.get_stats()
        print(f"\n📊 Stats before rollback:")
        print(f"   Pending: {stats['task_counts'].get('pending', 0)}")
        print(f"   Processing: {stats['task_counts'].get('processing', 0)}")
        print(f"   Completed: {stats['task_counts'].get('completed', 0)}")
        print(f"   Failed: {stats['task_counts'].get('failed', 0)}")
        
        # Rollback to checkpoint
        print(f"\n🔄 Rolling back to checkpoint: {checkpoint_id}")
        success = await self.rollback_to_checkpoint(checkpoint_id)
        
        if success:
            print("   ✅ Rollback successful!")
        else:
            print("   ❌ Rollback failed!")
        
        # Show final stats
        stats = await self.get_stats()
        print(f"\n📊 Final Stats:")
        print(f"   Pending: {stats['task_counts'].get('pending', 0)}")
        print(f"   Processing: {stats['task_counts'].get('processing', 0)}")
        print(f"   Completed: {stats['task_counts'].get('completed', 0)}")
        print(f"   Failed: {stats['task_counts'].get('failed', 0)}")
        
        print(f"\n📋 Checkpoints created: {len(stats['checkpoints'])}")
        for cp in stats['checkpoints']:
            print(f"   - {cp['id']} ({cp['task_count']} tasks)")
        
        print("\n✅ Demo completed successfully!")
        print("=" * 60)

async def main():
    demo = SimpleDemo()
    await demo.initialize()
    await demo.demo_scenario()

if __name__ == "__main__":
    asyncio.run(main())
