from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import asyncpg
import asyncio
import redis.asyncio as redis
import json
import os
import uuid
import httpx
from decimal import Decimal
import hashlib
from datetime import datetime
from enum import Enum
from typing import Optional, List, Dict, Any

app = FastAPI(title="Transaction Service", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class TransactionType(str, Enum):
    TRANSFER = "TRANSFER"
    DEPOSIT = "DEPOSIT"
    WITHDRAWAL = "WITHDRAWAL"

class TransactionStatus(str, Enum):
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    COMPENSATED = "COMPENSATED"

class SagaStatus(str, Enum):
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    COMPENSATING = "COMPENSATING"
    COMPENSATED = "COMPENSATED"

class TransferRequest(BaseModel):
    from_account: str
    to_account: str
    amount: float
    description: str = ""
    idempotency_key: str

class SagaStep(BaseModel):
    step_number: int
    service_name: str
    action: str
    payload: Dict[Any, Any]
    compensation_action: str
    compensation_payload: Dict[Any, Any]
    status: str = "PENDING"

# Database and service configuration
DATABASE_URL = os.getenv("DATABASE_URL")
REDIS_URL = os.getenv("REDIS_URL")
ACCOUNT_SERVICE_URL = os.getenv("ACCOUNT_SERVICE_URL", "http://localhost:8001")

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

class SagaOrchestrator:
    """SAGA pattern implementation for distributed transactions"""
    
    def __init__(self, db_pool, redis_client):
        self.db_pool = db_pool
        self.redis_client = redis_client
        self.http_client = httpx.AsyncClient(timeout=30.0)
    
    async def start_saga(self, saga_id: str, transaction_data: dict, steps: List[SagaStep]) -> bool:
        """Start a new SAGA transaction"""
        async with self.db_pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute("""
                    INSERT INTO saga_transactions (saga_id, transaction_data, total_steps, status)
                    VALUES ($1, $2, $3, $4)
                """, saga_id, json.dumps(transaction_data), len(steps), SagaStatus.IN_PROGRESS.value)
                
                # Store steps in Redis for faster access
                await self.redis_client.hset(f"saga:{saga_id}:steps", 
                                           mapping={str(i): json.dumps(step.dict()) for i, step in enumerate(steps)})
                
                return await self.execute_saga(saga_id, steps)
    
    async def execute_saga(self, saga_id: str, steps: List[SagaStep]) -> bool:
        """Execute SAGA steps sequentially"""
        current_step = 0
        
        try:
            for step in steps:
                success = await self.execute_step(saga_id, step)
                if not success:
                    # Start compensation
                    await self.compensate_saga(saga_id, current_step)
                    return False
                current_step += 1
            
            # All steps completed successfully
            await self.complete_saga(saga_id)
            return True
            
        except Exception as e:
            print(f"SAGA {saga_id} failed with error: {e}")
            await self.compensate_saga(saga_id, current_step)
            return False
    
    async def execute_step(self, saga_id: str, step: SagaStep) -> bool:
        """Execute a single SAGA step"""
        try:
            if step.service_name == "account-service":
                url = f"{ACCOUNT_SERVICE_URL}{step.action}"
                async with self.http_client as client:
                    response = await client.post(url, json=step.payload)
                    success = response.status_code == 200
            else:
                # Handle other services
                success = True
            
            # Update step status in Redis
            step.status = "COMPLETED" if success else "FAILED"
            await self.redis_client.hset(f"saga:{saga_id}:steps", str(step.step_number), json.dumps(step.dict()))
            
            return success
            
        except Exception as e:
            print(f"Step {step.step_number} failed: {e}")
            return False
    
    async def compensate_saga(self, saga_id: str, failed_step_index: int):
        """Execute compensation actions for completed steps"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                UPDATE saga_transactions 
                SET status = $1, updated_at = CURRENT_TIMESTAMP
                WHERE saga_id = $2
            """, SagaStatus.COMPENSATING.value, saga_id)
        
        # Execute compensations in reverse order
        for step_index in range(failed_step_index - 1, -1, -1):
            step_data = await self.redis_client.hget(f"saga:{saga_id}:steps", str(step_index))
            if step_data:
                step = SagaStep(**json.loads(step_data))
                await self.execute_compensation(saga_id, step)
        
        # Mark saga as compensated
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                UPDATE saga_transactions 
                SET status = $1, updated_at = CURRENT_TIMESTAMP
                WHERE saga_id = $2
            """, SagaStatus.COMPENSATED.value, saga_id)
    
    async def execute_compensation(self, saga_id: str, step: SagaStep):
        """Execute compensation for a step"""
        try:
            if step.service_name == "account-service":
                url = f"{ACCOUNT_SERVICE_URL}{step.compensation_action}"
                async with self.http_client as client:
                    await client.post(url, json=step.compensation_payload)
            print(f"Compensated step {step.step_number} for SAGA {saga_id}")
        except Exception as e:
            print(f"Compensation failed for step {step.step_number}: {e}")
    
    async def complete_saga(self, saga_id: str):
        """Mark saga as completed"""
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                UPDATE saga_transactions 
                SET status = $1, updated_at = CURRENT_TIMESTAMP
                WHERE saga_id = $2
            """, SagaStatus.COMPLETED.value, saga_id)

# Global saga orchestrator
saga_orchestrator = None

@app.on_event("startup")
async def init_saga_orchestrator():
    global saga_orchestrator
    saga_orchestrator = SagaOrchestrator(db_manager.pool, db_manager.redis_client)

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "transaction-service"}

@app.post("/transactions/transfer")
async def transfer_money(transfer: TransferRequest):
    """Execute money transfer using SAGA pattern"""
    try:
        # Check idempotency
        idempotency_result = await db_manager.redis_client.get(f"transfer:{transfer.idempotency_key}")
        if idempotency_result:
            return json.loads(idempotency_result)
        
        saga_id = f"transfer_{uuid.uuid4()}"
        transaction_id = f"TXN_{uuid.uuid4()}"
        
        # Define SAGA steps
        steps = [
            SagaStep(
                step_number=0,
                service_name="account-service",
                action="/accounts/adjust-balance",
                payload={
                    "account_number": transfer.from_account,
                    "amount": transfer.amount,
                    "operation": "debit",
                    "idempotency_key": f"{saga_id}_debit",
                    "saga_id": saga_id
                },
                compensation_action="/accounts/adjust-balance",
                compensation_payload={
                    "account_number": transfer.from_account,
                    "amount": transfer.amount,
                    "operation": "credit",
                    "idempotency_key": f"{saga_id}_debit_compensation",
                    "saga_id": saga_id
                }
            ),
            SagaStep(
                step_number=1,
                service_name="account-service",
                action="/accounts/adjust-balance",
                payload={
                    "account_number": transfer.to_account,
                    "amount": transfer.amount,
                    "operation": "credit",
                    "idempotency_key": f"{saga_id}_credit",
                    "saga_id": saga_id
                },
                compensation_action="/accounts/adjust-balance",
                compensation_payload={
                    "account_number": transfer.to_account,
                    "amount": transfer.amount,
                    "operation": "debit",
                    "idempotency_key": f"{saga_id}_credit_compensation",
                    "saga_id": saga_id
                }
            )
        ]
        
        # Record transaction intent
        async with db_manager.pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO transactions (transaction_id, from_account_id, to_account_id, amount, 
                                        transaction_type, status, description, idempotency_key, saga_id)
                VALUES ($1, 
                       (SELECT id FROM accounts WHERE account_number = $2),
                       (SELECT id FROM accounts WHERE account_number = $3),
                       $4, $5, $6, $7, $8, $9)
            """, transaction_id, transfer.from_account, transfer.to_account, transfer.amount,
                TransactionType.TRANSFER.value, TransactionStatus.PENDING.value, 
                transfer.description, transfer.idempotency_key, saga_id)
        
        # Execute SAGA
        transaction_data = {
            "transaction_id": transaction_id,
            "from_account": transfer.from_account,
            "to_account": transfer.to_account,
            "amount": transfer.amount,
            "description": transfer.description
        }
        
        success = await saga_orchestrator.start_saga(saga_id, transaction_data, steps)
        
        # Update transaction status
        final_status = TransactionStatus.COMPLETED.value if success else TransactionStatus.FAILED.value
        async with db_manager.pool.acquire() as conn:
            await conn.execute("""
                UPDATE transactions SET status = $1, updated_at = CURRENT_TIMESTAMP
                WHERE transaction_id = $2
            """, final_status, transaction_id)
        
        result = {
            "success": success,
            "transaction_id": transaction_id,
            "saga_id": saga_id,
            "status": final_status,
            "message": "Transfer completed successfully" if success else "Transfer failed"
        }
        
        # Store idempotency result
        await db_manager.redis_client.setex(f"transfer:{transfer.idempotency_key}", 3600, json.dumps(result))
        
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transfer failed: {str(e)}")

@app.get("/transactions")
async def list_transactions():
    """List all transactions with their status"""
    async with db_manager.pool.acquire() as conn:
        transactions = await conn.fetch("""
            SELECT t.transaction_id, t.amount, t.transaction_type, t.status, t.description,
                   t.created_at, t.saga_id,
                   fa.account_number as from_account,
                   ta.account_number as to_account
            FROM transactions t
            LEFT JOIN accounts fa ON t.from_account_id = fa.id
            LEFT JOIN accounts ta ON t.to_account_id = ta.id
            ORDER BY t.created_at DESC
        """)
        
        return [dict(tx) for tx in transactions]

@app.get("/transactions/{transaction_id}")
async def get_transaction(transaction_id: str):
    """Get transaction details including SAGA status"""
    async with db_manager.pool.acquire() as conn:
        transaction = await conn.fetchrow("""
            SELECT t.*, fa.account_number as from_account, ta.account_number as to_account,
                   s.status as saga_status, s.current_step, s.total_steps
            FROM transactions t
            LEFT JOIN accounts fa ON t.from_account_id = fa.id
            LEFT JOIN accounts ta ON t.to_account_id = ta.id
            LEFT JOIN saga_transactions s ON t.saga_id = s.saga_id
            WHERE t.transaction_id = $1
        """, transaction_id)
        
        if not transaction:
            raise HTTPException(status_code=404, detail="Transaction not found")
        
        return dict(transaction)

@app.get("/saga/{saga_id}/status")
async def get_saga_status(saga_id: str):
    """Get detailed SAGA execution status"""
    async with db_manager.pool.acquire() as conn:
        saga = await conn.fetchrow("""
            SELECT * FROM saga_transactions WHERE saga_id = $1
        """, saga_id)
        
        if not saga:
            raise HTTPException(status_code=404, detail="SAGA not found")
        
        # Get step details from Redis
        steps = await db_manager.redis_client.hgetall(f"saga:{saga_id}:steps")
        step_details = {}
        for step_num, step_data in steps.items():
            step_details[int(step_num)] = json.loads(step_data)
        
        return {
            "saga_id": saga_id,
            "status": saga['status'],
            "current_step": saga['current_step'],
            "total_steps": saga['total_steps'],
            "steps": step_details,
            "created_at": saga['created_at'],
            "updated_at": saga['updated_at']
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8002)))
