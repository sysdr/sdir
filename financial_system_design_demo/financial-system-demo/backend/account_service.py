from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import asyncpg
import asyncio
import redis.asyncio as redis
import json
import os
import uuid
from decimal import Decimal
import hashlib
from datetime import datetime

app = FastAPI(title="Account Service", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AccountCreate(BaseModel):
    customer_name: str
    initial_balance: float = 0.0

class AccountUpdate(BaseModel):
    balance: float

class BalanceAdjustment(BaseModel):
    account_number: str
    amount: float
    operation: str  # 'debit' or 'credit'
    idempotency_key: str
    saga_id: str = None

# Database connection
DATABASE_URL = os.getenv("DATABASE_URL")
REDIS_URL = os.getenv("REDIS_URL")

class DatabaseManager:
    def __init__(self):
        self.pool = None
        self.redis_client = None
    
    async def connect(self):
        self.pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20)
        self.redis_client = redis.from_url(REDIS_URL)
    
    async def disconnect(self):
        if self.pool:
            await self.pool.close()
        if self.redis_client:
            await self.redis_client.close()

db_manager = DatabaseManager()

@app.on_event("startup")
async def startup_event():
    await db_manager.connect()

@app.on_event("shutdown")
async def shutdown_event():
    await db_manager.disconnect()

def create_audit_checksum(data: dict) -> str:
    """Create integrity checksum for audit trail"""
    content = json.dumps(data, sort_keys=True, default=str)
    return hashlib.sha256(content.encode()).hexdigest()

async def log_audit_event(conn, event_type: str, entity_type: str, entity_id: str, 
                         old_data: dict = None, new_data: dict = None, user_id: str = "system"):
    """Log audit event with integrity checksum"""
    # Get timestamp once and use it consistently for checksum and database storage
    timestamp = datetime.utcnow()
    timestamp_iso = timestamp.isoformat()
    
    audit_data = {
        "event_type": event_type,
        "entity_type": entity_type, 
        "entity_id": entity_id,
        "old_data": old_data,
        "new_data": new_data,
        "user_id": user_id,
        "timestamp": timestamp_iso
    }
    checksum = create_audit_checksum(audit_data)
    
    # Insert with the timestamp used in checksum calculation
    await conn.execute("""
        INSERT INTO audit_log (event_type, entity_type, entity_id, old_data, new_data, user_id, timestamp, checksum)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    """, event_type, entity_type, entity_id, json.dumps(old_data), json.dumps(new_data), user_id, timestamp, checksum)

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "account-service"}

@app.post("/accounts")
async def create_account(account: AccountCreate):
    async with db_manager.pool.acquire() as conn:
        async with conn.transaction():
            # Generate unique account number
            account_number = f"ACC{str(uuid.uuid4())[:8].upper()}"
            
            account_id = await conn.fetchval("""
                INSERT INTO accounts (account_number, customer_name, balance)
                VALUES ($1, $2, $3) RETURNING id
            """, account_number, account.customer_name, account.initial_balance)
            
            # Log audit event
            await log_audit_event(conn, "ACCOUNT_CREATED", "account", str(account_id),
                                 None, {"account_number": account_number, "customer_name": account.customer_name, "balance": account.initial_balance})
            
            return {"account_id": account_id, "account_number": account_number, "message": "Account created successfully"}

@app.get("/accounts/{account_number}")
async def get_account(account_number: str):
    async with db_manager.pool.acquire() as conn:
        account = await conn.fetchrow("""
            SELECT id, account_number, customer_name, balance, status, created_at
            FROM accounts WHERE account_number = $1
        """, account_number)
        
        if not account:
            raise HTTPException(status_code=404, detail="Account not found")
        
        return dict(account)

@app.get("/accounts")
async def list_accounts():
    async with db_manager.pool.acquire() as conn:
        accounts = await conn.fetch("""
            SELECT id, account_number, customer_name, balance, status, created_at
            FROM accounts ORDER BY created_at DESC
        """)
        
        return [dict(account) for account in accounts]

@app.post("/accounts/adjust-balance")
async def adjust_balance(adjustment: BalanceAdjustment):
    """ACID-compliant balance adjustment with idempotency"""
    # Check idempotency key in Redis
    idempotency_result = await db_manager.redis_client.get(f"idempotent:{adjustment.idempotency_key}")
    if idempotency_result:
        return json.loads(idempotency_result)
    
    async with db_manager.pool.acquire() as conn:
        async with conn.transaction():
            # Get current account with row-level lock (SELECT FOR UPDATE)
            account = await conn.fetchrow("""
                SELECT id, account_number, customer_name, balance, version
                FROM accounts WHERE account_number = $1 FOR UPDATE
            """, adjustment.account_number)
            
            if not account:
                raise HTTPException(status_code=404, detail="Account not found")
            
            old_balance = float(account['balance'])
            
            # Calculate new balance
            if adjustment.operation == 'debit':
                new_balance = old_balance - adjustment.amount
                if new_balance < 0:
                    raise HTTPException(status_code=400, detail="Insufficient funds")
            elif adjustment.operation == 'credit':
                new_balance = old_balance + adjustment.amount
            else:
                raise HTTPException(status_code=400, detail="Invalid operation")
            
            # Update balance with optimistic locking (version check)
            updated_rows = await conn.execute("""
                UPDATE accounts 
                SET balance = $1, version = version + 1, updated_at = CURRENT_TIMESTAMP
                WHERE account_number = $2 AND version = $3
            """, new_balance, adjustment.account_number, account['version'])
            
            if updated_rows == "UPDATE 0":
                raise HTTPException(status_code=409, detail="Account was modified by another transaction")
            
            # Log audit event
            await log_audit_event(conn, f"BALANCE_{adjustment.operation.upper()}", "account", str(account['id']),
                                 {"balance": old_balance, "version": account['version']},
                                 {"balance": new_balance, "version": account['version'] + 1,
                                  "operation": adjustment.operation, "amount": adjustment.amount,
                                  "saga_id": adjustment.saga_id})
            
            result = {
                "success": True,
                "account_number": adjustment.account_number,
                "old_balance": old_balance,
                "new_balance": new_balance,
                "operation": adjustment.operation,
                "amount": adjustment.amount
            }
            
            # Store idempotency result
            await db_manager.redis_client.setex(f"idempotent:{adjustment.idempotency_key}", 3600, json.dumps(result))
            
            return result

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8001)))
