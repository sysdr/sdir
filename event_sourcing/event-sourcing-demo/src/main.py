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
