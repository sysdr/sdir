"""
Task Processor with Checkpoint and Rollback Recovery
Demonstrates production-grade checkpoint mechanisms
"""
import asyncio
import json
import time
import uuid
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
import redis.asyncio as redis
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
    status = sa.Column(sa.String, default='pending')  # pending, processing, completed, failed
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

@dataclass
class SystemState:
    active_tasks: List[str]
    completed_tasks: List[str]
    failed_tasks: List[str]
    last_checkpoint: Optional[str]
    uptime_seconds: float
    processed_count: int

@dataclass
class TaskState:
    task_id: str
    status: str
    progress: float
    data: Dict[str, Any]
    checkpoint_id: Optional[str]

class CheckpointManager:
    """Manages checkpoint creation and rollback operations"""
    
    def __init__(self, db_session: AsyncSession, redis_client: redis.Redis):
        self.db_session = db_session
        self.redis_client = redis_client
        self.checkpoint_interval = 10  # seconds
        self.last_checkpoint_time = time.time()
        
    async def create_checkpoint(self) -> str:
        """Create a consistent system checkpoint"""
        checkpoint_id = f"checkpoint_{int(time.time())}_{uuid.uuid4().hex[:8]}"
        
        try:
            # Gather current system state
            result = await self.db_session.execute(
                sa.select(Task).where(Task.status.in_(['pending', 'processing']))
            )
            active_tasks = result.scalars().all()
            
            result = await self.db_session.execute(
                sa.select(Task).where(Task.status == 'completed')
            )
            completed_tasks = result.scalars().all()
            
            # Create system state snapshot
            system_state = SystemState(
                active_tasks=[t.id for t in active_tasks],
                completed_tasks=[t.id for t in completed_tasks],
                failed_tasks=[],
                last_checkpoint=checkpoint_id,
                uptime_seconds=time.time(),
                processed_count=len(completed_tasks)
            )
            
            # Create task state snapshots
            task_states = {}
            for task in active_tasks:
                task_states[task.id] = TaskState(
                    task_id=task.id,
                    status=task.status,
                    progress=task.progress,
                    data=task.data,
                    checkpoint_id=checkpoint_id
                )
            
            # Store checkpoint in database
            checkpoint = Checkpoint(
                id=checkpoint_id,
                system_state=asdict(system_state),
                task_states={k: asdict(v) for k, v in task_states.items()},
                is_consistent=True
            )
            
            self.db_session.add(checkpoint)
            await self.db_session.commit()
            
            # Cache in Redis for fast access (if Redis is available)
            if self.redis_client:
                await self.redis_client.set(
                    f"checkpoint:{checkpoint_id}",
                    json.dumps({
                        'system_state': asdict(system_state),
                        'task_states': {k: asdict(v) for k, v in task_states.items()},
                        'created_at': datetime.utcnow().isoformat()
                    }),
                    ex=3600  # 1 hour TTL
                )
            
            self.last_checkpoint_time = time.time()
            
            logger.info("Checkpoint created", 
                       checkpoint_id=checkpoint_id,
                       active_tasks=len(active_tasks),
                       completed_tasks=len(completed_tasks))
            
            return checkpoint_id
            
        except Exception as e:
            logger.error("Checkpoint creation failed", error=str(e))
            await self.db_session.rollback()
            raise
    
    async def rollback_to_checkpoint(self, checkpoint_id: str) -> bool:
        """Rollback system to a specific checkpoint"""
        try:
            # Load checkpoint data
            result = await self.db_session.execute(
                sa.select(Checkpoint).where(Checkpoint.id == checkpoint_id)
            )
            checkpoint = result.scalar_one_or_none()
            
            if not checkpoint:
                logger.error("Checkpoint not found", checkpoint_id=checkpoint_id)
                return False
            
            # Restore system state
            system_state = checkpoint.system_state
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
            
            logger.info("Rollback completed", 
                       checkpoint_id=checkpoint_id,
                       restored_tasks=len(task_states))
            
            return True
            
        except Exception as e:
            logger.error("Rollback failed", error=str(e), checkpoint_id=checkpoint_id)
            await self.db_session.rollback()
            return False
    
    async def get_latest_checkpoint(self) -> Optional[str]:
        """Get the most recent checkpoint ID"""
        result = await self.db_session.execute(
            sa.select(Checkpoint.id)
            .order_by(Checkpoint.created_at.desc())
            .limit(1)
        )
        checkpoint = result.scalar_one_or_none()
        return checkpoint

class TaskProcessor:
    """Main task processing engine with checkpoint recovery"""
    
    def __init__(self):
        self.db_engine = None
        self.db_session = None
        self.redis_client = None
        self.checkpoint_manager = None
        self.running = False
        self.start_time = time.time()
        
    async def initialize(self):
        """Initialize database and Redis connections"""
        # Database setup
        database_url = os.getenv('DATABASE_URL', 'postgresql://demo:demo123@localhost:5432/checkpoint_demo')
        # Convert to async URL
        async_url = database_url.replace('postgresql://', 'postgresql+asyncpg://')
        
        self.db_engine = create_async_engine(async_url, echo=False)
        async_session = sessionmaker(self.db_engine, class_=AsyncSession, expire_on_commit=False)
        
        # Create tables
        async with self.db_engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        
        self.db_session = async_session()
        
        # Redis setup
        redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
        self.redis_client = redis.from_url(redis_url)
        
        # Initialize checkpoint manager
        self.checkpoint_manager = CheckpointManager(self.db_session, self.redis_client)
        
        logger.info("Task processor initialized")
    
    async def process_task(self, task: Task) -> bool:
        """Process a single task with progress tracking"""
        try:
            # Update task status
            task.status = 'processing'
            task.updated_at = datetime.utcnow()
            await self.db_session.commit()
            
            logger.info("Processing task", task_id=task.id, data=task.data)
            
            # Simulate work with progress updates
            total_steps = task.data.get('steps', 10)
            for step in range(total_steps):
                # Simulate processing time
                await asyncio.sleep(0.5)
                
                # Update progress
                task.progress = (step + 1) / total_steps
                await self.db_session.commit()
                
                # Simulate potential failure
                if task.data.get('should_fail') and step > 5:
                    raise Exception("Simulated task failure")
            
            # Mark completed
            task.status = 'completed'
            task.progress = 1.0
            task.updated_at = datetime.utcnow()
            await self.db_session.commit()
            
            logger.info("Task completed", task_id=task.id)
            return True
            
        except Exception as e:
            task.status = 'failed'
            task.updated_at = datetime.utcnow()
            await self.db_session.commit()
            
            logger.error("Task failed", task_id=task.id, error=str(e))
            return False
    
    async def recovery_check(self):
        """Check if recovery is needed and trigger rollback if necessary"""
        try:
            # Check for too many failed tasks
            result = await self.db_session.execute(
                sa.select(sa.func.count(Task.id)).where(Task.status == 'failed')
            )
            failed_count = result.scalar()
            
            # Check for stalled tasks
            stall_threshold = datetime.utcnow() - timedelta(minutes=5)
            result = await self.db_session.execute(
                sa.select(sa.func.count(Task.id))
                .where(Task.status == 'processing')
                .where(Task.updated_at < stall_threshold)
            )
            stalled_count = result.scalar()
            
            # Trigger rollback if too many failures or stalled tasks
            if failed_count > 3 or stalled_count > 2:
                logger.warning("System instability detected, triggering rollback",
                             failed_count=failed_count, stalled_count=stalled_count)
                
                latest_checkpoint = await self.checkpoint_manager.get_latest_checkpoint()
                if latest_checkpoint:
                    success = await self.checkpoint_manager.rollback_to_checkpoint(latest_checkpoint)
                    if success:
                        logger.info("Recovery rollback completed")
                        return True
                        
        except Exception as e:
            logger.error("Recovery check failed", error=str(e))
            
        return False
    
    async def run(self):
        """Main processing loop"""
        self.running = True
        
        while self.running:
            try:
                # Create checkpoint periodically
                if time.time() - self.checkpoint_manager.last_checkpoint_time > self.checkpoint_manager.checkpoint_interval:
                    await self.checkpoint_manager.create_checkpoint()
                
                # Check for recovery needs
                await self.recovery_check()
                
                # Process pending tasks
                result = await self.db_session.execute(
                    sa.select(Task)
                    .where(Task.status == 'pending')
                    .limit(5)
                )
                pending_tasks = result.scalars().all()
                
                if pending_tasks:
                    # Process tasks concurrently
                    tasks = [self.process_task(task) for task in pending_tasks]
                    await asyncio.gather(*tasks, return_exceptions=True)
                else:
                    # No tasks, wait a bit
                    await asyncio.sleep(2)
                    
            except Exception as e:
                logger.error("Processing loop error", error=str(e))
                await asyncio.sleep(5)
    
    async def shutdown(self):
        """Graceful shutdown"""
        self.running = False
        if self.db_session:
            await self.db_session.close()
        if self.redis_client:
            await self.redis_client.close()
        logger.info("Task processor shutdown complete")

async def main():
    """Main entry point"""
    processor = TaskProcessor()
    
    try:
        await processor.initialize()
        
        # Create initial checkpoint
        await processor.checkpoint_manager.create_checkpoint()
        
        # Start processing
        await processor.run()
        
    except KeyboardInterrupt:
        logger.info("Shutdown signal received")
    finally:
        await processor.shutdown()

if __name__ == "__main__":
    asyncio.run(main())
