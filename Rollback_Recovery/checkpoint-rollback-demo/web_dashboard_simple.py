#!/usr/bin/env python3
"""
Simple Web Dashboard for Checkpoint and Rollback Recovery Demo
Uses SQLite for easier setup
"""
import asyncio
import json
import time
import uuid
import os
from datetime import datetime
from typing import List, Dict, Any
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import uvicorn
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

app = FastAPI(title="Checkpoint Recovery Dashboard")

# Global connections
db_session = None

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_text(json.dumps(message))
            except:
                pass

manager = ConnectionManager()

@app.on_event("startup")
async def startup():
    global db_session
    
    # Database setup with SQLite
    db_engine = create_async_engine("sqlite+aiosqlite:///dashboard.db", echo=False)
    async_session = sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)
    
    # Create tables
    async with db_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    db_session = async_session()
    
    # Start background task for real-time updates
    asyncio.create_task(broadcast_updates())

async def broadcast_updates():
    """Broadcast system state updates to connected clients"""
    while True:
        try:
            if db_session:
                # Get current system stats
                stats = await get_system_stats()
                await manager.broadcast({
                    'type': 'stats_update',
                    'data': stats
                })
            await asyncio.sleep(2)
        except Exception as e:
            logger.error("Broadcast error", error=str(e))
            await asyncio.sleep(5)

async def get_system_stats() -> Dict[str, Any]:
    """Get current system statistics"""
    try:
        # Task counts by status
        result = await db_session.execute(
            sa.select(Task.status, sa.func.count(Task.id))
            .group_by(Task.status)
        )
        task_counts = dict(result.fetchall())
        
        # Recent checkpoints
        result = await db_session.execute(
            sa.select(Checkpoint)
            .order_by(Checkpoint.created_at.desc())
            .limit(5)
        )
        checkpoints = result.scalars().all()
        
        # Active tasks with progress
        result = await db_session.execute(
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
    except Exception as e:
        logger.error("Stats error", error=str(e))
        return {'error': str(e)}

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    stats = await get_system_stats()
    return HTMLResponse(content=get_dashboard_html(stats))

@app.post("/tasks/create")
async def create_task(
    task_type: str = Form(...),
    steps: int = Form(10),
    should_fail: bool = Form(False)
):
    """Create a new task"""
    try:
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        task = Task(
            id=task_id,
            status='pending',
            data={
                'type': task_type,
                'steps': steps,
                'should_fail': should_fail,
                'created_by': 'dashboard'
            }
        )
        
        db_session.add(task)
        await db_session.commit()
        
        await manager.broadcast({
            'type': 'task_created',
            'data': {'task_id': task_id, 'type': task_type}
        })
        
    except Exception as e:
        logger.error("Task creation failed", error=str(e))
    
    return RedirectResponse(url="/", status_code=303)

@app.post("/checkpoints/create")
async def create_checkpoint():
    """Manually trigger checkpoint creation"""
    try:
        checkpoint_id = f"checkpoint_{int(time.time())}_{uuid.uuid4().hex[:8]}"
        
        # Get current tasks
        result = await db_session.execute(sa.select(Task))
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
        
        db_session.add(checkpoint)
        await db_session.commit()
        
        await manager.broadcast({
            'type': 'checkpoint_triggered',
            'data': {'checkpoint_id': checkpoint_id, 'timestamp': datetime.utcnow().isoformat()}
        })
        
    except Exception as e:
        logger.error("Checkpoint trigger failed", error=str(e))
    
    return RedirectResponse(url="/", status_code=303)

@app.post("/rollback/{checkpoint_id}")
async def rollback_to_checkpoint(checkpoint_id: str):
    """Trigger rollback to specific checkpoint"""
    try:
        # Get checkpoint
        result = await db_session.execute(
            sa.select(Checkpoint).where(Checkpoint.id == checkpoint_id)
        )
        checkpoint = result.scalar_one()
        
        # Get task states from checkpoint
        task_states = checkpoint.task_states
        
        # Reset tasks to checkpoint state
        for task_id, task_state in task_states.items():
            await db_session.execute(
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
        await db_session.execute(
            sa.delete(Task).where(Task.created_at > checkpoint_time)
        )
        
        await db_session.commit()
        
        await manager.broadcast({
            'type': 'rollback_triggered',
            'data': {
                'checkpoint_id': checkpoint_id,
                'timestamp': datetime.utcnow().isoformat()
            }
        })
        
    except Exception as e:
        logger.error("Rollback trigger failed", error=str(e))
    
    return RedirectResponse(url="/", status_code=303)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket for real-time updates"""
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # Echo back any received messages
            await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)

def get_dashboard_html(stats):
    """Generate dashboard HTML"""
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Checkpoint Recovery Dashboard</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }}
        .container {{ 
            max-width: 1200px; 
            margin: 0 auto; 
            padding: 20px;
        }}
        .header {{
            background: white;
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 24px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
        }}
        .header h1 {{
            color: #4f46e5;
            font-size: 2rem;
            margin-bottom: 8px;
        }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 24px;
        }}
        .card {{
            background: white;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            transition: transform 0.2s;
        }}
        .card:hover {{ transform: translateY(-2px); }}
        .card h2 {{
            color: #1f2937;
            font-size: 1.25rem;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        .status-grid {{
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            margin-bottom: 16px;
        }}
        .status-item {{
            background: #f8fafc;
            padding: 12px;
            border-radius: 8px;
            text-align: center;
        }}
        .status-pending {{ border-left: 4px solid #eab308; }}
        .status-processing {{ border-left: 4px solid #3b82f6; }}
        .status-completed {{ border-left: 4px solid #10b981; }}
        .status-failed {{ border-left: 4px solid #ef4444; }}
        .checkpoint-list {{
            max-height: 200px;
            overflow-y: auto;
        }}
        .checkpoint-item {{
            background: #f8fafc;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .task-item {{
            background: #f8fafc;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 8px;
        }}
        .progress-bar {{
            width: 100%;
            height: 8px;
            background: #e5e7eb;
            border-radius: 4px;
            overflow: hidden;
            margin-top: 8px;
        }}
        .progress-fill {{
            height: 100%;
            background: #3b82f6;
            transition: width 0.3s;
        }}
        .btn {{
            background: #4f46e5;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: background 0.2s;
        }}
        .btn:hover {{ background: #4338ca; }}
        .btn-sm {{ padding: 4px 8px; font-size: 12px; }}
        .btn-danger {{ background: #ef4444; }}
        .btn-danger:hover {{ background: #dc2626; }}
        .form-group {{
            margin-bottom: 16px;
        }}
        .form-group label {{
            display: block;
            margin-bottom: 4px;
            font-weight: 500;
        }}
        .form-group input, .form-group select {{
            width: 100%;
            padding: 8px 12px;
            border: 1px solid #d1d5db;
            border-radius: 6px;
            font-size: 14px;
        }}
        .status-indicator {{
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
        }}
        .status-online {{ background: #10b981; }}
        .status-offline {{ background: #ef4444; }}
        .timestamp {{
            font-size: 12px;
            color: #6b7280;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Checkpoint & Rollback Recovery Dashboard</h1>
            <p>Real-time monitoring of task processing with checkpoint recovery capabilities</p>
            <div style="margin-top: 12px;">
                <span class="status-indicator status-online"></span>
                <span id="connection-status">Connected</span>
                <span class="timestamp" style="margin-left: 16px;" id="last-update">Last update: {datetime.utcnow().strftime('%H:%M:%S')}</span>
            </div>
        </div>

        <div class="grid">
            <!-- Task Statistics -->
            <div class="card">
                <h2>📊 Task Statistics</h2>
                <div class="status-grid" id="task-stats">
                    <div class="status-item status-pending">
                        <div style="font-size: 24px; font-weight: bold;" id="pending-count">{stats.get('task_counts', {}).get('pending', 0)}</div>
                        <div>Pending</div>
                    </div>
                    <div class="status-item status-processing">
                        <div style="font-size: 24px; font-weight: bold;" id="processing-count">{stats.get('task_counts', {}).get('processing', 0)}</div>
                        <div>Processing</div>
                    </div>
                    <div class="status-item status-completed">
                        <div style="font-size: 24px; font-weight: bold;" id="completed-count">{stats.get('task_counts', {}).get('completed', 0)}</div>
                        <div>Completed</div>
                    </div>
                    <div class="status-item status-failed">
                        <div style="font-size: 24px; font-weight: bold;" id="failed-count">{stats.get('task_counts', {}).get('failed', 0)}</div>
                        <div>Failed</div>
                    </div>
                </div>
            </div>

            <!-- Create Task -->
            <div class="card">
                <h2>➕ Create New Task</h2>
                <form method="post" action="/tasks/create">
                    <div class="form-group">
                        <label for="task_type">Task Type:</label>
                        <select name="task_type" id="task_type">
                            <option value="data_processing">Data Processing</option>
                            <option value="file_conversion">File Conversion</option>
                            <option value="batch_calculation">Batch Calculation</option>
                            <option value="report_generation">Report Generation</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="steps">Processing Steps:</label>
                        <input type="number" name="steps" id="steps" value="10" min="5" max="50">
                    </div>
                    <div class="form-group">
                        <label>
                            <input type="checkbox" name="should_fail" value="true">
                            Simulate failure after 50% progress
                        </label>
                    </div>
                    <button type="submit" class="btn">Create Task</button>
                </form>
            </div>

            <!-- Checkpoint Management -->
            <div class="card">
                <h2>💾 Checkpoint Management</h2>
                <div style="margin-bottom: 16px;">
                    <form method="post" action="/checkpoints/create" style="display: inline;">
                        <button type="submit" class="btn">Create Checkpoint</button>
                    </form>
                </div>
                <div class="checkpoint-list" id="checkpoint-list">
                    {' '.join([f'''
                    <div class="checkpoint-item">
                        <div>
                            <div style="font-weight: bold;">{cp["id"]}</div>
                            <div class="timestamp">{datetime.fromisoformat(cp["created_at"]).strftime('%Y-%m-%d %H:%M:%S')}</div>
                            <div style="font-size: 12px; color: #6b7280;">{cp["task_count"]} tasks</div>
                        </div>
                        <form method="post" action="/rollback/{cp["id"]}" style="display: inline;">
                            <button type="submit" class="btn btn-sm btn-danger">Rollback</button>
                        </form>
                    </div>
                    ''' for cp in stats.get('checkpoints', [])])}
                </div>
            </div>

            <!-- Active Tasks -->
            <div class="card">
                <h2>🔄 Active Tasks</h2>
                <div id="active-tasks">
                    {' '.join([f'''
                    <div class="task-item">
                        <div style="display: flex; justify-content: space-between; align-items: center;">
                            <div>
                                <div style="font-weight: bold;">{task["id"]}</div>
                                <div style="font-size: 12px; color: #6b7280;">{task["data"]["type"]}</div>
                            </div>
                            <div style="text-align: right;">
                                <div style="font-size: 12px; color: #6b7280;">{task["status"]}</div>
                                <div style="font-size: 12px;">{int(task["progress"] * 100)}%</div>
                            </div>
                        </div>
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: {task["progress"] * 100}%"></div>
                        </div>
                    </div>
                    ''' for task in stats.get('active_tasks', [])])}
                </div>
            </div>
        </div>
    </div>

    <script>
        let ws;
        let reconnectInterval;

        function connectWebSocket() {{
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${{protocol}}//${{window.location.host}}/ws`;
            
            ws = new WebSocket(wsUrl);
            
            ws.onopen = function() {{
                document.getElementById('connection-status').textContent = 'Connected';
                document.querySelector('.status-indicator').className = 'status-indicator status-online';
                if (reconnectInterval) {{
                    clearInterval(reconnectInterval);
                    reconnectInterval = null;
                }}
            }};
            
            ws.onmessage = function(event) {{
                const message = JSON.parse(event.data);
                handleWebSocketMessage(message);
            }};
            
            ws.onclose = function() {{
                document.getElementById('connection-status').textContent = 'Disconnected';
                document.querySelector('.status-indicator').className = 'status-indicator status-offline';
                
                if (!reconnectInterval) {{
                    reconnectInterval = setInterval(connectWebSocket, 5000);
                }}
            }};
        }}

        function handleWebSocketMessage(message) {{
            if (message.type === 'stats_update') {{
                updateStats(message.data);
            }} else if (message.type === 'task_created') {{
                showNotification('Task created: ' + message.data.task_id);
            }} else if (message.type === 'checkpoint_triggered') {{
                showNotification('Checkpoint created: ' + message.data.checkpoint_id);
            }} else if (message.type === 'rollback_triggered') {{
                showNotification('Rollback triggered to: ' + message.data.checkpoint_id);
            }}
        }}

        function updateStats(stats) {{
            // Update task counts
            const counts = stats.task_counts || {{}};
            document.getElementById('pending-count').textContent = counts.pending || 0;
            document.getElementById('processing-count').textContent = counts.processing || 0;
            document.getElementById('completed-count').textContent = counts.completed || 0;
            document.getElementById('failed-count').textContent = counts.failed || 0;

            // Update checkpoints
            updateCheckpoints(stats.checkpoints || []);

            // Update active tasks
            updateActiveTasks(stats.active_tasks || []);

            // Update timestamp
            document.getElementById('last-update').textContent = 
                'Last update: ' + new Date(stats.timestamp).toLocaleTimeString();
        }}

        function updateCheckpoints(checkpoints) {{
            const container = document.getElementById('checkpoint-list');
            container.innerHTML = checkpoints.map(cp => `
                <div class="checkpoint-item">
                    <div>
                        <div style="font-weight: bold;">${{cp.id}}</div>
                        <div class="timestamp">${{new Date(cp.created_at).toLocaleString()}}</div>
                        <div style="font-size: 12px; color: #6b7280;">${{cp.task_count}} tasks</div>
                    </div>
                    <form method="post" action="/rollback/${{cp.id}}" style="display: inline;">
                        <button type="submit" class="btn btn-sm btn-danger">Rollback</button>
                    </form>
                </div>
            `).join('');
        }}

        function updateActiveTasks(tasks) {{
            const container = document.getElementById('active-tasks');
            container.innerHTML = tasks.map(task => `
                <div class="task-item">
                    <div style="display: flex; justify-content: space-between; align-items: center;">
                        <div>
                            <div style="font-weight: bold;">${{task.id}}</div>
                            <div style="font-size: 12px; color: #6b7280;">${{task.data.type}}</div>
                        </div>
                        <div style="text-align: right;">
                            <div style="font-size: 12px; color: #6b7280;">${{task.status}}</div>
                            <div style="font-size: 12px;">${{Math.round(task.progress * 100)}}%</div>
                        </div>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${{task.progress * 100}}%"></div>
                    </div>
                </div>
            `).join('');
        }}

        function showNotification(message) {{
            // Simple notification - in production would use toast library
            console.log('Notification:', message);
        }}

        // Initialize
        connectWebSocket();
    </script>
</body>
</html>'''

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
