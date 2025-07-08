from celery import Celery
import time
import random
import json
import logging
from datetime import datetime
from typing import Dict, Any
import os
from PIL import Image
import io
import base64

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create Celery app
app = Celery('async_processing_worker')
app.conf.update(
    broker_url=os.getenv("REDIS_URL", "redis://redis:6379/0"),
    result_backend=os.getenv("REDIS_URL", "redis://redis:6379/0"),
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
    task_routes={
        'worker.tasks.process_image_task': {'queue': 'images'},
        'worker.tasks.send_email_task': {'queue': 'emails'},
        'worker.tasks.generate_report_task': {'queue': 'reports'},
        'worker.tasks.heavy_computation_task': {'queue': 'computation'},
    },
    task_default_retry_delay=60,  # 1 minute
    task_max_retries=3,
    worker_prefetch_multiplier=1,
)

def update_task_status(task_id: str, status: str, result: Dict[Any, Any] = None, error: str = None):
    """Update task status in database"""
    try:
        import asyncio
        import asyncpg
        import os
        
        # Database connection
        DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://demo:demo123@postgres:5432/demo")
        
        # Map status to enum values (database uses uppercase)
        status_mapping = {
            "pending": "PENDING",
            "processing": "PROCESSING", 
            "completed": "COMPLETED",
            "failed": "FAILED",
            "retrying": "RETRYING"
        }
        
        db_status = status_mapping.get(status, status)
        
        async def update_db():
            conn = await asyncpg.connect(DATABASE_URL)
            try:
                if result:
                    await conn.execute(
                        "UPDATE tasks SET status = $1::taskstatus, result = $2, updated_at = NOW() WHERE id = $3",
                        db_status, json.dumps(result), task_id
                    )
                elif error:
                    await conn.execute(
                        "UPDATE tasks SET status = $1::taskstatus, error = $2, updated_at = NOW() WHERE id = $3",
                        db_status, error, task_id
                    )
                else:
                    await conn.execute(
                        "UPDATE tasks SET status = $1::taskstatus, updated_at = NOW() WHERE id = $3",
                        db_status, task_id
                    )
            finally:
                await conn.close()
        
        # Run the async function
        asyncio.run(update_db())
        logger.info(f"Task {task_id}: Status updated to {status}")
        if result:
            logger.info(f"Task {task_id}: Result - {result}")
        if error:
            logger.error(f"Task {task_id}: Error - {error}")
    except Exception as e:
        logger.error(f"Error updating task status: {e}")

@app.task(bind=True, name='worker.tasks.process_image_task')
def process_image_task(self, task_id: str, image_data: bytes, operation: str):
    """Process image with various operations"""
    try:
        update_task_status(task_id, "processing")
        
        # Simulate image processing
        logger.info(f"Processing image task {task_id} with operation: {operation}")
        
        # Convert bytes to PIL Image for demonstration
        try:
            image = Image.open(io.BytesIO(image_data))
            width, height = image.size
        except Exception:
            # If image processing fails, use dummy dimensions
            width, height = 800, 600
        
        # Simulate different processing times based on operation
        processing_times = {
            "thumbnail": random.uniform(2, 5),
            "resize": random.uniform(3, 7),
            "filter": random.uniform(5, 10),
            "enhancement": random.uniform(8, 15)
        }
        
        processing_time = processing_times.get(operation, 5)
        
        # Simulate processing with progress updates
        for i in range(5):
            time.sleep(processing_time / 5)
            progress = (i + 1) * 20
            logger.info(f"Task {task_id}: {progress}% complete")
        
        # Simulate occasional failures
        if random.random() < 0.1:  # 10% failure rate
            raise Exception(f"Random processing failure for operation: {operation}")
        
        result = {
            "operation": operation,
            "original_size": f"{width}x{height}",
            "processed_at": datetime.now().isoformat(),
            "processing_time": processing_time,
            "file_size": len(image_data),
            "success": True
        }
        
        update_task_status(task_id, "completed", result)
        return result
        
    except Exception as exc:
        logger.error(f"Image processing failed for task {task_id}: {exc}")
        update_task_status(task_id, "failed", error=str(exc))
        # Retry with exponential backoff
        raise self.retry(exc=exc, countdown=60 * (2 ** self.request.retries))

@app.task(bind=True, name='worker.tasks.send_email_task')
def send_email_task(self, task_id: str, recipient: str, subject: str, template: str):
    """Send email task"""
    try:
        update_task_status(task_id, "processing")
        
        logger.info(f"Sending email task {task_id} to {recipient}")
        
        # Simulate email sending process
        templates = {
            "welcome": "Welcome to our service!",
            "confirmation": "Your order has been confirmed",
            "newsletter": "Weekly newsletter content",
            "notification": "Important notification"
        }
        
        email_content = templates.get(template, "Default email content")
        
        # Simulate email service API call
        time.sleep(random.uniform(1, 3))
        
        # Simulate occasional failures
        if random.random() < 0.05:  # 5% failure rate
            raise Exception(f"Email service temporarily unavailable")
        
        result = {
            "recipient": recipient,
            "subject": subject,
            "template": template,
            "content_preview": email_content[:50] + "...",
            "sent_at": datetime.now().isoformat(),
            "success": True
        }
        
        update_task_status(task_id, "completed", result)
        return result
        
    except Exception as exc:
        logger.error(f"Email sending failed for task {task_id}: {exc}")
        update_task_status(task_id, "failed", error=str(exc))
        raise self.retry(exc=exc, countdown=30 * (2 ** self.request.retries))

@app.task(bind=True, name='worker.tasks.generate_report_task')
def generate_report_task(self, task_id: str, report_type: str, date_range: str, format: str):
    """Generate report task"""
    try:
        update_task_status(task_id, "processing")
        
        logger.info(f"Generating report task {task_id}: {report_type}")
        
        # Simulate report generation
        report_sizes = {
            "sales": random.randint(100, 1000),
            "analytics": random.randint(500, 2000),
            "user_activity": random.randint(200, 800),
            "financial": random.randint(50, 500)
        }
        
        # Simulate processing time based on complexity
        processing_time = random.uniform(10, 30)
        
        for i in range(10):
            time.sleep(processing_time / 10)
            progress = (i + 1) * 10
            logger.info(f"Task {task_id}: Generating report... {progress}% complete")
        
        # Simulate occasional failures
        if random.random() < 0.08:  # 8% failure rate
            raise Exception(f"Report generation failed due to data inconsistency")
        
        record_count = report_sizes.get(report_type, 500)
        
        result = {
            "report_type": report_type,
            "date_range": f"Last {date_range} days",
            "format": format,
            "record_count": record_count,
            "file_size": f"{record_count * 2.5:.1f} KB",
            "generated_at": datetime.now().isoformat(),
            "processing_time": processing_time,
            "success": True
        }
        
        update_task_status(task_id, "completed", result)
        return result
        
    except Exception as exc:
        logger.error(f"Report generation failed for task {task_id}: {exc}")
        update_task_status(task_id, "failed", error=str(exc))
        raise self.retry(exc=exc, countdown=120 * (2 ** self.request.retries))

@app.task(bind=True, name='worker.tasks.heavy_computation_task')
def heavy_computation_task(self, task_id: str, complexity: str, data_size: int):
    """Heavy computation task"""
    try:
        update_task_status(task_id, "processing")
        
        logger.info(f"Starting computation task {task_id}: {complexity} complexity")
        
        # Simulate computation based on complexity
        complexity_multipliers = {
            "low": 1,
            "medium": 3,
            "high": 8,
            "extreme": 20
        }
        
        multiplier = complexity_multipliers.get(complexity, 3)
        iterations = data_size * multiplier
        
        # Simulate heavy computation with progress updates
        total_time = random.uniform(5, 20)
        checkpoint_interval = max(iterations // 20, 1)
        
        start_time = time.time()
        for i in range(iterations):
            # Simulate computation work
            if i % 1000 == 0:
                time.sleep(0.001)  # Small delay to simulate work
            
            if i % checkpoint_interval == 0:
                progress = (i / iterations) * 100
                elapsed = time.time() - start_time
                logger.info(f"Task {task_id}: {progress:.1f}% complete ({elapsed:.1f}s elapsed)")
        
        elapsed_time = time.time() - start_time
        
        # Simulate occasional failures
        if random.random() < 0.12:  # 12% failure rate
            raise Exception(f"Computation failed due to memory constraints")
        
        result = {
            "complexity": complexity,
            "data_size": data_size,
            "iterations": iterations,
            "elapsed_time": elapsed_time,
            "operations_per_second": iterations / elapsed_time,
            "completed_at": datetime.now().isoformat(),
            "success": True
        }
        
        update_task_status(task_id, "completed", result)
        return result
        
    except Exception as exc:
        logger.error(f"Computation failed for task {task_id}: {exc}")
        update_task_status(task_id, "failed", error=str(exc))
        raise self.retry(exc=exc, countdown=180 * (2 ** self.request.retries))

def get_task_status(task_id: str) -> Dict[str, Any]:
    """Get task status from Celery"""
    try:
        # Try to find task in different queues
        queues = ['images', 'emails', 'reports', 'computation']
        
        for queue in queues:
            # In a real implementation, you'd query the database here
            # For demo purposes, we'll return a mock status
            pass
        
        return {
            "task_id": task_id,
            "status": "unknown",
            "progress": 0,
            "message": "Task status not found"
        }
    except Exception as e:
        return {
            "task_id": task_id,
            "status": "error",
            "error": str(e)
        }

def get_queue_stats() -> Dict[str, Any]:
    """Get queue statistics"""
    try:
        from celery import current_app
        inspect = current_app.control.inspect()
        
        # Get active tasks
        active_tasks = inspect.active()
        reserved_tasks = inspect.reserved()
        
        stats = {
            "active_tasks": len(active_tasks) if active_tasks else 0,
            "reserved_tasks": len(reserved_tasks) if reserved_tasks else 0,
            "workers_online": len(active_tasks.keys()) if active_tasks else 0,
            "timestamp": datetime.now().isoformat()
        }
        
        return stats
    except Exception as e:
        logger.error(f"Error getting queue stats: {e}")
        return {
            "active_tasks": 0,
            "reserved_tasks": 0,
            "workers_online": 0,
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }
