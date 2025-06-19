#!/bin/bash

# Event Sourcing Demo - One-Click Setup Script
# Creates a complete event sourcing banking system demonstration

set -e

echo "🚀 Event Sourcing Demo Setup Starting..."

# Create project structure
PROJECT_DIR="event-sourcing-demo"
mkdir -p "$PROJECT_DIR"/{src,templates,static,tests}
cd "$PROJECT_DIR"

# Create requirements.txt with latest compatible versions
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.2
jinja2==3.1.2
python-multipart==0.0.6
aiofiles==23.2.0

python-dateutil==2.8.2
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs data templates static

# Expose port
EXPOSE 8000

# Start the application
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  event-sourcing-demo:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - PYTHONPATH=/app
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Create the main application
cat > src/main.py << 'EOF'
"""
Event Sourcing Banking System Demo
Demonstrates core event sourcing patterns with temporal queries
"""

from fastapi import FastAPI, Request, Form, HTTPException
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
import uuid
import json
import sqlite3
import os
from dataclasses import dataclass, asdict
from enum import Enum

# Initialize FastAPI app
app = FastAPI(title="Event Sourcing Demo", version="1.0.0")

# Setup templates and static files
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")

# Ensure data directory exists
os.makedirs("data", exist_ok=True)

class EventType(str, Enum):
    ACCOUNT_CREATED = "account_created"
    DEPOSIT = "deposit"
    WITHDRAWAL = "withdrawal"
    TRANSFER_OUT = "transfer_out"
    TRANSFER_IN = "transfer_in"

@dataclass
class Event:
    event_id: str
    aggregate_id: str
    event_type: EventType
    event_data: Dict[str, Any]
    timestamp: datetime
    version: int
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'event_id': self.event_id,
            'aggregate_id': self.aggregate_id,
            'event_type': self.event_type.value,
            'event_data': json.dumps(self.event_data),
            'timestamp': self.timestamp.isoformat(),
            'version': self.version
        }

class EventStore:
    """Simple SQLite-based event store for demonstration"""
    
    def __init__(self, db_path: str = "data/events.db"):
        self.db_path = db_path
        self.init_db()
    
    def init_db(self):
        """Initialize the event store database"""
        conn = sqlite3.connect(self.db_path)
        try:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    event_id TEXT PRIMARY KEY,
                    aggregate_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    event_data TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    version INTEGER NOT NULL,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_aggregate_id 
                ON events(aggregate_id, version)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_timestamp 
                ON events(timestamp)
            """)
            conn.commit()
        finally:
            conn.close()
    
    def append_event(self, event: Event) -> None:
        """Append an event to the store with optimistic concurrency control"""
        conn = sqlite3.connect(self.db_path)
        try:
            # Check current version for optimistic concurrency
            cursor = conn.execute(
                "SELECT MAX(version) FROM events WHERE aggregate_id = ?",
                (event.aggregate_id,)
            )
            current_version = cursor.fetchone()[0] or 0
            
            if event.version != current_version + 1:
                raise ValueError(f"Concurrency conflict: expected version {current_version + 1}, got {event.version}")
            
            # Insert the event
            event_dict = event.to_dict()
            conn.execute("""
                INSERT INTO events (event_id, aggregate_id, event_type, event_data, timestamp, version)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                event_dict['event_id'],
                event_dict['aggregate_id'],
                event_dict['event_type'],
                event_dict['event_data'],
                event_dict['timestamp'],
                event_dict['version']
            ))
            conn.commit()
        finally:
            conn.close()
    
    def get_events(self, aggregate_id: str, from_version: int = 0, to_timestamp: Optional[datetime] = None) -> List[Event]:
        """Retrieve events for an aggregate, optionally up to a specific timestamp"""
        conn = sqlite3.connect(self.db_path)
        try:
            query = """
                SELECT event_id, aggregate_id, event_type, event_data, timestamp, version
                FROM events 
                WHERE aggregate_id = ? AND version > ?
            """
            params = [aggregate_id, from_version]
            
            if to_timestamp:
                query += " AND timestamp <= ?"
                params.append(to_timestamp.isoformat())
            
            query += " ORDER BY version"
            
            cursor = conn.execute(query, params)
            events = []
            
            for row in cursor.fetchall():
                events.append(Event(
                    event_id=row[0],
                    aggregate_id=row[1],
                    event_type=EventType(row[2]),
                    event_data=json.loads(row[3]),
                    timestamp=datetime.fromisoformat(row[4]),
                    version=row[5]
                ))
            
            return events
        finally:
            conn.close()
    
    def get_all_events(self, limit: int = 100) -> List[Event]:
        """Get all events across all aggregates for dashboard view"""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.execute("""
                SELECT event_id, aggregate_id, event_type, event_data, timestamp, version
                FROM events 
                ORDER BY timestamp DESC 
                LIMIT ?
            """, (limit,))
            
            events = []
            for row in cursor.fetchall():
                events.append(Event(
                    event_id=row[0],
                    aggregate_id=row[1],
                    event_type=EventType(row[2]),
                    event_data=json.loads(row[3]),
                    timestamp=datetime.fromisoformat(row[4]),
                    version=row[5]
                ))
            
            return events
        finally:
            conn.close()

@dataclass
class Account:
    """Account aggregate representing current state"""
    account_id: str
    account_number: str
    balance: float
    version: int
    created_at: datetime
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'account_id': self.account_id,
            'account_number': self.account_number,
            'balance': self.balance,
            'version': self.version,
            'created_at': self.created_at.isoformat()
        }

class AccountAggregate:
    """Account aggregate that rebuilds state from events"""
    
    def __init__(self, event_store: EventStore):
        self.event_store = event_store
    
    def create_account(self, account_number: str) -> str:
        """Create a new account and return account ID"""
        account_id = str(uuid.uuid4())
        
        event = Event(
            event_id=str(uuid.uuid4()),
            aggregate_id=account_id,
            event_type=EventType.ACCOUNT_CREATED,
            event_data={
                'account_number': account_number,
                'initial_balance': 0.0
            },
            timestamp=datetime.now(),
            version=1
        )
        
        self.event_store.append_event(event)
        return account_id
    
    def deposit(self, account_id: str, amount: float, description: str = "") -> None:
        """Deposit money to account"""
        current_account = self.get_account(account_id)
        if not current_account:
            raise ValueError(f"Account {account_id} not found")
        
        event = Event(
            event_id=str(uuid.uuid4()),
            aggregate_id=account_id,
            event_type=EventType.DEPOSIT,
            event_data={
                'amount': amount,
                'description': description
            },
            timestamp=datetime.now(),
            version=current_account.version + 1
        )
        
        self.event_store.append_event(event)
    
    def withdraw(self, account_id: str, amount: float, description: str = "") -> None:
        """Withdraw money from account"""
        current_account = self.get_account(account_id)
        if not current_account:
            raise ValueError(f"Account {account_id} not found")
        
        if current_account.balance < amount:
            raise ValueError(f"Insufficient funds. Current balance: {current_account.balance}")
        
        event = Event(
            event_id=str(uuid.uuid4()),
            aggregate_id=account_id,
            event_type=EventType.WITHDRAWAL,
            event_data={
                'amount': amount,
                'description': description
            },
            timestamp=datetime.now(),
            version=current_account.version + 1
        )
        
        self.event_store.append_event(event)
    
    def get_account(self, account_id: str, at_timestamp: Optional[datetime] = None) -> Optional[Account]:
        """Rebuild account state from events, optionally at a specific timestamp"""
        events = self.event_store.get_events(account_id, to_timestamp=at_timestamp)
        
        if not events:
            return None
        
        # Start with creation event
        creation_event = events[0]
        if creation_event.event_type != EventType.ACCOUNT_CREATED:
            raise ValueError("First event must be account creation")
        
        account = Account(
            account_id=account_id,
            account_number=creation_event.event_data['account_number'],
            balance=creation_event.event_data['initial_balance'],
            version=creation_event.version,
            created_at=creation_event.timestamp
        )
        
        # Apply subsequent events
        for event in events[1:]:
            if event.event_type == EventType.DEPOSIT:
                account.balance += event.event_data['amount']
            elif event.event_type == EventType.WITHDRAWAL:
                account.balance -= event.event_data['amount']
            elif event.event_type == EventType.TRANSFER_IN:
                account.balance += event.event_data['amount']
            elif event.event_type == EventType.TRANSFER_OUT:
                account.balance -= event.event_data['amount']
            
            account.version = event.version
        
        return account

# Initialize components
event_store = EventStore()
account_aggregate = AccountAggregate(event_store)

# API Routes
@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard showing accounts and recent events"""
    recent_events = event_store.get_all_events(limit=20)
    
    # Get all unique account IDs from events
    account_ids = set()
    for event in recent_events:
        account_ids.add(event.aggregate_id)
    
    # Build current account states
    accounts = []
    for account_id in account_ids:
        account = account_aggregate.get_account(account_id)
        if account:
            accounts.append(account)
    
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "accounts": accounts,
        "recent_events": recent_events
    })

@app.post("/create-account")
async def create_account(account_number: str = Form(...)):
    """Create a new account"""
    try:
        account_id = account_aggregate.create_account(account_number)
        return {"success": True, "account_id": account_id, "message": f"Account {account_number} created successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/deposit")
async def deposit(account_id: str = Form(...), amount: float = Form(...), description: str = Form("")):
    """Deposit money to account"""
    try:
        account_aggregate.deposit(account_id, amount, description)
        return {"success": True, "message": f"Deposited ${amount:.2f} successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/withdraw")
async def withdraw(account_id: str = Form(...), amount: float = Form(...), description: str = Form("")):
    """Withdraw money from account"""
    try:
        account_aggregate.withdraw(account_id, amount, description)
        return {"success": True, "message": f"Withdrawn ${amount:.2f} successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/account/{account_id}/history")
async def account_history(account_id: str, hours_ago: Optional[int] = None):
    """Get account state at different points in time"""
    try:
        current_account = account_aggregate.get_account(account_id)
        if not current_account:
            raise HTTPException(status_code=404, detail="Account not found")
        
        result = {
            "current": current_account.to_dict(),
            "events": []
        }
        
        # Get all events for this account
        events = event_store.get_events(account_id)
        for event in events:
            result["events"].append({
                "timestamp": event.timestamp.isoformat(),
                "event_type": event.event_type.value,
                "event_data": event.event_data,
                "version": event.version
            })
        
        # If hours_ago specified, show historical balance
        if hours_ago is not None:
            historical_timestamp = datetime.now() - timedelta(hours=hours_ago)
            historical_account = account_aggregate.get_account(account_id, historical_timestamp)
            if historical_account:
                result["historical"] = {
                    "timestamp": historical_timestamp.isoformat(),
                    "hours_ago": hours_ago,
                    "balance": historical_account.balance
                }
        
        return result
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint for Docker"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create the HTML template
cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Event Sourcing Banking Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .main-content {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            padding: 30px;
        }
        
        .section {
            background: #f8fafc;
            border-radius: 10px;
            padding: 25px;
            border: 1px solid #e2e8f0;
        }
        
        .section h2 {
            color: #1e293b;
            margin-bottom: 20px;
            font-size: 1.5em;
            border-bottom: 2px solid #e2e8f0;
            padding-bottom: 10px;
        }
        
        .form-group {
            margin-bottom: 15px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: 600;
            color: #374151;
        }
        
        .form-group input, .form-group select {
            width: 100%;
            padding: 12px;
            border: 2px solid #e5e7eb;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.2s;
        }
        
        .form-group input:focus, .form-group select:focus {
            outline: none;
            border-color: #4f46e5;
        }
        
        .btn {
            background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: transform 0.2s;
            width: 100%;
            margin-top: 10px;
        }
        
        .btn:hover {
            transform: translateY(-2px);
        }
        
        .accounts-list {
            margin-bottom: 20px;
        }
        
        .account-card {
            background: white;
            border: 2px solid #e5e7eb;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 10px;
            transition: border-color 0.2s;
        }
        
        .account-card:hover {
            border-color: #4f46e5;
        }
        
        .account-number {
            font-weight: 600;
            color: #1e293b;
            font-size: 1.1em;
        }
        
        .account-balance {
            color: #059669;
            font-size: 1.2em;
            font-weight: 700;
            margin-top: 5px;
        }
        
        .account-id {
            color: #6b7280;
            font-size: 0.9em;
            margin-top: 5px;
            font-family: monospace;
        }
        
        .events-list {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .event-item {
            background: white;
            border-left: 4px solid #4f46e5;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 0 8px 8px 0;
        }
        
        .event-type {
            font-weight: 600;
            color: #1e293b;
            text-transform: uppercase;
            font-size: 0.9em;
        }
        
        .event-data {
            margin-top: 5px;
            color: #374151;
        }
        
        .event-timestamp {
            color: #6b7280;
            font-size: 0.8em;
            margin-top: 5px;
        }
        
        .temporal-query {
            background: #fef3c7;
            border: 2px solid #f59e0b;
            border-radius: 8px;
            padding: 20px;
            margin-top: 20px;
        }
        
        .temporal-query h3 {
            color: #92400e;
            margin-bottom: 15px;
        }
        
        .message {
            padding: 15px;
            border-radius: 8px;
            margin: 10px 0;
            font-weight: 600;
        }
        
        .success {
            background: #d1fae5;
            color: #065f46;
            border: 1px solid #10b981;
        }
        
        .error {
            background: #fee2e2;
            color: #991b1b;
            border: 1px solid #ef4444;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏦 Event Sourcing Banking Demo</h1>
            <p>Experience how event sourcing enables time travel through your data</p>
        </div>
        
        <div class="main-content">
            <!-- Left Column: Actions -->
            <div class="section">
                <h2>💰 Account Operations</h2>
                
                <!-- Create Account Form -->
                <form id="createAccountForm">
                    <div class="form-group">
                        <label>Create New Account</label>
                        <input type="text" id="accountNumber" placeholder="Enter account number" required>
                        <button type="submit" class="btn">Create Account</button>
                    </div>
                </form>
                
                <!-- Transaction Forms -->
                <form id="depositForm">
                    <div class="form-group">
                        <label>Deposit Money</label>
                        <select id="depositAccount" required>
                            <option value="">Select Account</option>
                            {% for account in accounts %}
                            <option value="{{ account.account_id }}">{{ account.account_number }} ({{ account.account_id[:8] }}...)</option>
                            {% endfor %}
                        </select>
                        <input type="number" id="depositAmount" placeholder="Amount" step="0.01" min="0.01" required>
                        <input type="text" id="depositDescription" placeholder="Description (optional)">
                        <button type="submit" class="btn">Deposit</button>
                    </div>
                </form>
                
                <form id="withdrawForm">
                    <div class="form-group">
                        <label>Withdraw Money</label>
                        <select id="withdrawAccount" required>
                            <option value="">Select Account</option>
                            {% for account in accounts %}
                            <option value="{{ account.account_id }}">{{ account.account_number }} ({{ account.account_id[:8] }}...)</option>
                            {% endfor %}
                        </select>
                        <input type="number" id="withdrawAmount" placeholder="Amount" step="0.01" min="0.01" required>
                        <input type="text" id="withdrawDescription" placeholder="Description (optional)">
                        <button type="submit" class="btn">Withdraw</button>
                    </div>
                </form>
                
                <!-- Temporal Query Section -->
                <div class="temporal-query">
                    <h3>⏰ Time Travel Query</h3>
                    <div class="form-group">
                        <select id="historyAccount">
                            <option value="">Select Account</option>
                            {% for account in accounts %}
                            <option value="{{ account.account_id }}">{{ account.account_number }}</option>
                            {% endfor %}
                        </select>
                        <input type="number" id="hoursAgo" placeholder="Hours ago" min="1" max="168">
                        <button type="button" class="btn" onclick="queryHistory()">View Historical Balance</button>
                    </div>
                </div>
                
                <div id="messages"></div>
            </div>
            
            <!-- Right Column: Current State -->
            <div class="section">
                <h2>📊 Current State & Event Stream</h2>
                
                <!-- Accounts List -->
                <div class="accounts-list">
                    <h3>Active Accounts</h3>
                    {% for account in accounts %}
                    <div class="account-card">
                        <div class="account-number">Account: {{ account.account_number }}</div>
                        <div class="account-balance">${{ "%.2f"|format(account.balance) }}</div>
                        <div class="account-id">ID: {{ account.account_id }}</div>
                    </div>
                    {% endfor %}
                    
                    {% if not accounts %}
                    <p style="color: #6b7280; text-align: center; padding: 20px;">
                        No accounts yet. Create your first account to begin!
                    </p>
                    {% endif %}
                </div>
                
                <!-- Recent Events -->
                <div class="events-list">
                    <h3>Recent Events (Latest First)</h3>
                    {% for event in recent_events %}
                    <div class="event-item">
                        <div class="event-type">{{ event.event_type.value.replace('_', ' ') }}</div>
                        <div class="event-data">
                            {% if event.event_data.amount %}
                                Amount: ${{ "%.2f"|format(event.event_data.amount) }}
                            {% endif %}
                            {% if event.event_data.account_number %}
                                Account: {{ event.event_data.account_number }}
                            {% endif %}
                            {% if event.event_data.description %}
                                - {{ event.event_data.description }}
                            {% endif %}
                        </div>
                        <div class="event-timestamp">
                            {{ event.timestamp.strftime('%Y-%m-%d %H:%M:%S') }} | 
                            Account: {{ event.aggregate_id[:8] }}... | 
                            Version: {{ event.version }}
                        </div>
                    </div>
                    {% endfor %}
                    
                    {% if not recent_events %}
                    <p style="color: #6b7280; text-align: center; padding: 20px;">
                        No events yet. Start by creating an account!
                    </p>
                    {% endif %}
                </div>
            </div>
        </div>
    </div>
    
    <script>
        function showMessage(message, type = 'success') {
            const messagesDiv = document.getElementById('messages');
            const messageEl = document.createElement('div');
            messageEl.className = `message ${type}`;
            messageEl.textContent = message;
            messagesDiv.appendChild(messageEl);
            
            setTimeout(() => {
                messageEl.remove();
            }, 5000);
        }
        
        // Create Account Form
        document.getElementById('createAccountForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const accountNumber = document.getElementById('accountNumber').value;
            
            try {
                const response = await fetch('/create-account', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `account_number=${encodeURIComponent(accountNumber)}`
                });
                
                const result = await response.json();
                if (result.success) {
                    showMessage(result.message);
                    setTimeout(() => location.reload(), 1000);
                } else {
                    showMessage(result.detail || 'Error creating account', 'error');
                }
            } catch (error) {
                showMessage('Network error: ' + error.message, 'error');
            }
        });
        
        // Deposit Form
        document.getElementById('depositForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const accountId = document.getElementById('depositAccount').value;
            const amount = document.getElementById('depositAmount').value;
            const description = document.getElementById('depositDescription').value;
            
            try {
                const response = await fetch('/deposit', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `account_id=${accountId}&amount=${amount}&description=${encodeURIComponent(description)}`
                });
                
                const result = await response.json();
                if (result.success) {
                    showMessage(result.message);
                    setTimeout(() => location.reload(), 1000);
                } else {
                    showMessage(result.detail || 'Error processing deposit', 'error');
                }
            } catch (error) {
                showMessage('Network error: ' + error.message, 'error');
            }
        });
        
        // Withdraw Form
        document.getElementById('withdrawForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const accountId = document.getElementById('withdrawAccount').value;
            const amount = document.getElementById('withdrawAmount').value;
            const description = document.getElementById('withdrawDescription').value;
            
            try {
                const response = await fetch('/withdraw', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `account_id=${accountId}&amount=${amount}&description=${encodeURIComponent(description)}`
                });
                
                const result = await response.json();
                if (result.success) {
                    showMessage(result.message);
                    setTimeout(() => location.reload(), 1000);
                } else {
                    showMessage(result.detail || 'Error processing withdrawal', 'error');
                }
            } catch (error) {
                showMessage('Network error: ' + error.message, 'error');
            }
        });
        
        // Temporal Query
        async function queryHistory() {
            const accountId = document.getElementById('historyAccount').value;
            const hoursAgo = document.getElementById('hoursAgo').value;
            
            if (!accountId || !hoursAgo) {
                showMessage('Please select an account and specify hours ago', 'error');
                return;
            }
            
            try {
                const response = await fetch(`/account/${accountId}/history?hours_ago=${hoursAgo}`);
                const result = await response.json();
                
                if (result.current) {
                    let message = `Current balance: $${result.current.balance.toFixed(2)}`;
                    if (result.historical) {
                        message += ` | Balance ${hoursAgo} hours ago: $${result.historical.balance.toFixed(2)}`;
                        const change = result.current.balance - result.historical.balance;
                        message += ` | Change: ${change >= 0 ? '+' : ''}$${change.toFixed(2)}`;
                    }
                    showMessage(message);
                } else {
                    showMessage('Account not found', 'error');
                }
            } catch (error) {
                showMessage('Network error: ' + error.message, 'error');
            }
        }
        
        // Auto-refresh every 10 seconds to show new events
        setTimeout(() => {
            location.reload();
        }, 10000);
    </script>
</body>
</html>
EOF

# Create test script
cat > tests/test_event_sourcing.py << 'EOF'
"""
Test suite for Event Sourcing Demo
Validates core event sourcing patterns and behaviors
"""

import pytest
import sqlite3
import tempfile
import os
from datetime import datetime, timedelta
from src.main import EventStore, AccountAggregate, Event, EventType

class TestEventSourcing:
    """Test event sourcing implementation"""
    
    @pytest.fixture
    def event_store(self):
        """Create a temporary event store for testing"""
        db_path = tempfile.mktemp(suffix='.db')
        store = EventStore(db_path)
        yield store
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)
    
    @pytest.fixture
    def account_aggregate(self, event_store):
        """Create account aggregate with test event store"""
        return AccountAggregate(event_store)
    
    def test_account_creation(self, account_aggregate):
        """Test basic account creation"""
        account_id = account_aggregate.create_account("TEST-001")
        account = account_aggregate.get_account(account_id)
        
        assert account is not None
        assert account.account_number == "TEST-001"
        assert account.balance == 0.0
        assert account.version == 1
    
    def test_deposit_and_withdrawal(self, account_aggregate):
        """Test deposit and withdrawal operations"""
        account_id = account_aggregate.create_account("TEST-002")
        
        # Deposit money
        account_aggregate.deposit(account_id, 100.0, "Initial deposit")
        account = account_aggregate.get_account(account_id)
        assert account.balance == 100.0
        assert account.version == 2
        
        # Withdraw money
        account_aggregate.withdraw(account_id, 30.0, "ATM withdrawal")
        account = account_aggregate.get_account(account_id)
        assert account.balance == 70.0
        assert account.version == 3
    
    def test_insufficient_funds(self, account_aggregate):
        """Test insufficient funds protection"""
        account_id = account_aggregate.create_account("TEST-003")
        account_aggregate.deposit(account_id, 50.0)
        
        with pytest.raises(ValueError, match="Insufficient funds"):
            account_aggregate.withdraw(account_id, 100.0)
    
    def test_temporal_queries(self, account_aggregate, event_store):
        """Test temporal queries - state at specific points in time"""
        account_id = account_aggregate.create_account("TEST-004")
        
        # Record timestamp after account creation
        t1 = datetime.now()
        
        # First deposit
        account_aggregate.deposit(account_id, 100.0)
        t2 = datetime.now()  # After first deposit
        
        # Second deposit  
        account_aggregate.deposit(account_id, 50.0)
        t3 = datetime.now()  # After second deposit
        
        # Withdrawal
        account_aggregate.withdraw(account_id, 25.0)
        
        # Query state at different times
        state_at_t1 = account_aggregate.get_account(account_id, t1)
        state_at_t2 = account_aggregate.get_account(account_id, t2)
        state_at_t3 = account_aggregate.get_account(account_id, t3)
        current_state = account_aggregate.get_account(account_id)
        
        # Verify temporal accuracy
        assert state_at_t1.balance == 0.0  # Just after creation
        assert state_at_t2.balance == 100.0  # After first deposit
        assert state_at_t3.balance == 150.0  # After second deposit
        assert current_state.balance == 125.0  # After withdrawal
    
    def test_event_ordering(self, event_store):
        """Test that events maintain proper ordering"""
        account_id = "test-account"
        
        # Create events in sequence
        events = [
            Event("e1", account_id, EventType.ACCOUNT_CREATED, {"account_number": "TEST"}, datetime.now(), 1),
            Event("e2", account_id, EventType.DEPOSIT, {"amount": 100}, datetime.now(), 2),
            Event("e3", account_id, EventType.WITHDRAWAL, {"amount": 50}, datetime.now(), 3)
        ]
        
        for event in events:
            event_store.append_event(event)
        
        # Retrieve and verify ordering
        retrieved_events = event_store.get_events(account_id)
        assert len(retrieved_events) == 3
        assert [e.version for e in retrieved_events] == [1, 2, 3]
    
    def test_optimistic_concurrency(self, event_store):
        """Test optimistic concurrency control"""
        account_id = "test-account"
        
        # Create initial event
        event1 = Event("e1", account_id, EventType.ACCOUNT_CREATED, {"account_number": "TEST"}, datetime.now(), 1)
        event_store.append_event(event1)
        
        # Try to append event with wrong version (should fail)
        event2 = Event("e2", account_id, EventType.DEPOSIT, {"amount": 100}, datetime.now(), 3)  # Wrong version
        
        with pytest.raises(ValueError, match="Concurrency conflict"):
            event_store.append_event(event2)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
EOF

# Create README with setup instructions
cat > README.md << 'EOF'
# Event Sourcing Banking Demo

A comprehensive demonstration of event sourcing patterns using a banking system example.

## Features

- ✅ Complete event sourcing implementation with SQLite event store
- ✅ Temporal queries - view account state at any point in time
- ✅ Optimistic concurrency control for thread safety
- ✅ Event replay and state reconstruction
- ✅ Interactive web interface for demonstration
- ✅ Comprehensive test suite

## Quick Start

### Option 1: Docker (Recommended)
```bash
docker-compose up --build
```
Access the demo at: http://localhost:8000

### Option 2: Local Development
```bash
pip install -r requirements.txt
python src/main.py
```

## Demo Steps

1. **Create Accounts**: Start by creating one or more bank accounts
2. **Perform Transactions**: Deposit and withdraw money to see events being created
3. **Observe Event Stream**: Watch how each operation creates immutable events
4. **Time Travel Queries**: Use the temporal query feature to see account balances at historical points
5. **View Event History**: Examine the complete event log for any account

## Key Learning Points

- **Immutability**: Events are never modified, only appended
- **State Reconstruction**: Current state is calculated from event history
- **Temporal Queries**: System can answer "what was the state at time X?"
- **Auditability**: Complete history of all changes with full context
- **Replay Capability**: State can be rebuilt from events at any time

## Testing

Run the comprehensive test suite:
```bash
python -m pytest tests/ -v
```

## Architecture

- **Event Store**: SQLite-based append-only event storage
- **Account Aggregate**: Business logic for account operations
- **Event Types**: Strongly typed events for different operations
- **Projection**: Current state views built from events
- **Web Interface**: Interactive demonstration of concepts

This demo illustrates production-ready event sourcing patterns suitable for enterprise applications.
EOF

echo "✅ Event Sourcing Demo created successfully!"

# Make the project directory and give final instructions
echo ""
echo "🎉 Event Sourcing Demo Setup Complete!"
echo ""
echo "📁 Project created in: $PROJECT_DIR"
echo ""
echo "🚀 Quick Start Options:"
echo "  1. Docker (Recommended):"
echo "     cd $PROJECT_DIR && docker-compose up --build"
echo ""
echo "  2. Local Development:"
echo "     cd $PROJECT_DIR && pip install -r requirements.txt && python src/main.py"
echo ""
echo "🌐 Access the demo at: http://localhost:8000"
echo ""
echo "🧪 Run tests with: cd $PROJECT_DIR && python -m pytest tests/ -v"
echo ""
echo "📖 Key Demo Features:"
echo "  • Create bank accounts and perform transactions"
echo "  • Watch events being stored immutably"
echo "  • Use temporal queries to view historical account states"
echo "  • Observe how current state is reconstructed from events"
echo "  • Experience auditability and replay capabilities"
echo ""
echo "Happy learning! 🎓"