from sqlalchemy import Column, String, DateTime, Text, JSON, Enum
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
import enum
from datetime import datetime

Base = declarative_base()

class TaskStatus(enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    RETRYING = "retrying"

class Task(Base):
    __tablename__ = "tasks"
    
    id = Column(String, primary_key=True)
    task_type = Column(String, nullable=False)
    status = Column(Enum(TaskStatus), default=TaskStatus.PENDING)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, onupdate=func.now())
    task_metadata = Column(JSON)
    result = Column(JSON)
    error = Column(Text)
    
    def __repr__(self):
        return f"<Task(id='{self.id}', type='{self.task_type}', status='{self.status}')>"
