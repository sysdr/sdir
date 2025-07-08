from fastapi import FastAPI, HTTPException, BackgroundTasks, File, UploadFile, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
import asyncio
import redis
import json
import uuid
from datetime import datetime
from typing import List, Dict, Any
import logging
from app.database import init_db, get_db_session
from app.models import Task, TaskStatus
from worker.tasks import (
    process_image_task, send_email_task, generate_report_task,
    heavy_computation_task, get_task_status, get_queue_stats
)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Async Processing Demo", version="1.0.0")

# Static files and templates
app.mount("/static", StaticFiles(directory="web/static"), name="static")
templates = Jinja2Templates(directory="web/templates")

# Redis connection
redis_client = redis.from_url("redis://redis:6379/0", decode_responses=True)

@app.on_event("startup")
async def startup_event():
    """Initialize database and connections"""
    await init_db()
    logger.info("Application startup complete")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/queue-stats")
async def queue_statistics():
    """Get current queue statistics"""
    try:
        stats = get_queue_stats()
        return JSONResponse(content=stats)
    except Exception as e:
        logger.error(f"Error getting queue stats: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

@app.post("/api/tasks/image-processing")
async def create_image_task(file: UploadFile = File(...), operation: str = Form("thumbnail")):
    """Create an image processing task"""
    try:
        # Save uploaded file
        file_content = await file.read()
        file_id = str(uuid.uuid4())
        
        # Create task record
        async with get_db_session() as session:
            task = Task(
                id=file_id,
                task_type="image_processing",
                status=TaskStatus.PENDING,
                task_metadata={"filename": file.filename, "operation": operation}
            )
            session.add(task)
            await session.commit()
        
        # Queue background task
        job = process_image_task.delay(file_id, file_content, operation)
        
        return JSONResponse(content={
            "task_id": file_id,
            "job_id": job.id,
            "status": "queued",
            "message": f"Image processing task created for {operation}"
        })
    except Exception as e:
        logger.error(f"Error creating image task: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/tasks/email")
async def create_email_task(
    recipient: str = Form(...),
    subject: str = Form(...),
    template: str = Form("welcome")
):
    """Create an email sending task"""
    try:
        task_id = str(uuid.uuid4())
        
        # Create task record
        async with get_db_session() as session:
            task = Task(
                id=task_id,
                task_type="email",
                status=TaskStatus.PENDING,
                task_metadata={"recipient": recipient, "subject": subject, "template": template}
            )
            session.add(task)
            await session.commit()
        
        # Queue background task
        job = send_email_task.delay(task_id, recipient, subject, template)
        
        return JSONResponse(content={
            "task_id": task_id,
            "job_id": job.id,
            "status": "queued",
            "message": f"Email task created for {recipient}"
        })
    except Exception as e:
        logger.error(f"Error creating email task: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/tasks/report")
async def create_report_task(
    report_type: str = Form(...),
    date_range: str = Form("30"),
    format: str = Form("pdf")
):
    """Create a report generation task"""
    try:
        task_id = str(uuid.uuid4())
        
        # Create task record
        async with get_db_session() as session:
            task = Task(
                id=task_id,
                task_type="report",
                status=TaskStatus.PENDING,
                task_metadata={"report_type": report_type, "date_range": date_range, "format": format}
            )
            session.add(task)
            await session.commit()
        
        # Queue background task
        job = generate_report_task.delay(task_id, report_type, date_range, format)
        
        return JSONResponse(content={
            "task_id": task_id,
            "job_id": job.id,
            "status": "queued",
            "message": f"Report generation task created for {report_type}"
        })
    except Exception as e:
        logger.error(f"Error creating report task: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/tasks/computation")
async def create_computation_task(
    complexity: str = Form("medium"),
    data_size: str = Form("1000")
):
    """Create a heavy computation task"""
    try:
        task_id = str(uuid.uuid4())
        
        # Create task record
        async with get_db_session() as session:
            task = Task(
                id=task_id,
                task_type="computation",
                status=TaskStatus.PENDING,
                task_metadata={"complexity": complexity, "data_size": data_size}
            )
            session.add(task)
            await session.commit()
        
        # Queue background task
        job = heavy_computation_task.delay(task_id, complexity, int(data_size))
        
        return JSONResponse(content={
            "task_id": task_id,
            "job_id": job.id,
            "status": "queued",
            "message": f"Computation task created with {complexity} complexity"
        })
    except Exception as e:
        logger.error(f"Error creating computation task: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/tasks/{task_id}/status")
async def get_task_status_endpoint(task_id: str):
    """Get task status and progress"""
    try:
        status = get_task_status(task_id)
        return JSONResponse(content=status)
    except Exception as e:
        logger.error(f"Error getting task status: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

@app.get("/api/tasks")
async def list_tasks():
    """List all recent tasks"""
    try:
        async with get_db_session() as session:
            from sqlalchemy import select
            result = await session.execute(
                select(Task).order_by(Task.created_at.desc()).limit(50)
            )
            tasks = result.scalars().all()
            
            return JSONResponse(content=[{
                "id": task.id,
                "task_type": task.task_type,
                "status": task.status.value,
                "created_at": task.created_at.isoformat(),
                "updated_at": task.updated_at.isoformat() if task.updated_at else None,
                "metadata": task.task_metadata,
                "result": task.result,
                "error": task.error
            } for task in tasks])
    except Exception as e:
        logger.error(f"Error listing tasks: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

@app.get("/api/metrics")
async def get_metrics():
    """Get system metrics"""
    try:
        # Get queue stats
        queue_stats = get_queue_stats()
        
        # Get task statistics from database
        async with get_db_session() as session:
            from sqlalchemy import select, func
            
            # Total tasks by status
            result = await session.execute(
                select(Task.status, func.count(Task.id))
                .group_by(Task.status)
            )
            status_counts = dict(result.all())
            
            # Tasks by type
            result = await session.execute(
                select(Task.task_type, func.count(Task.id))
                .group_by(Task.task_type)
            )
            type_counts = dict(result.all())
        
        return JSONResponse(content={
            "queue_stats": queue_stats,
            "task_status_counts": {status.value if hasattr(status, 'value') else str(status): count 
                                 for status, count in status_counts.items()},
            "task_type_counts": type_counts,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
