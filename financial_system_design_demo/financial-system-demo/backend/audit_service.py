from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import asyncpg
import os
import json
import hashlib
from datetime import datetime, timedelta
from typing import Optional, List

app = FastAPI(title="Audit Service", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection
DATABASE_URL = os.getenv("DATABASE_URL")

class DatabaseManager:
    def __init__(self):
        self.pool = None
    
    async def connect(self):
        self.pool = await asyncpg.create_pool(DATABASE_URL, min_size=5, max_size=20)
    
    async def disconnect(self):
        if self.pool:
            await self.pool.close()

db_manager = DatabaseManager()

@app.on_event("startup")
async def startup_event():
    await db_manager.connect()

@app.on_event("shutdown")
async def shutdown_event():
    await db_manager.disconnect()

def verify_audit_checksum(audit_record: dict) -> bool:
    """Verify the integrity of an audit record"""
    if not audit_record.get('checksum'):
        return False
    
    stored_checksum = audit_record['checksum']
    
    # Build the audit_data exactly as it was when checksum was created
    # The checksum is calculated from: event_type, entity_type, entity_id, old_data, new_data, user_id, timestamp
    audit_data = {}
    
    # Handle each field exactly as it was when the checksum was created
    for key in ['event_type', 'entity_type', 'entity_id', 'user_id']:
        if key in audit_record:
            audit_data[key] = audit_record[key]
    
    # Handle timestamp - convert datetime to ISO format string (as it was stored)
    if 'timestamp' in audit_record:
        timestamp = audit_record['timestamp']
        if hasattr(timestamp, 'isoformat'):
            # It's a datetime object, convert to ISO string
            audit_data['timestamp'] = timestamp.isoformat()
        else:
            # Already a string
            audit_data['timestamp'] = str(timestamp)
    
    # Handle old_data and new_data (JSONB fields)
    for key in ['old_data', 'new_data']:
        if key in audit_record:
            value = audit_record[key]
            # asyncpg typically returns JSONB as dict/list, but sometimes as string
            if value is None:
                audit_data[key] = None
            elif isinstance(value, str):
                # If it's a string (JSON representation), use it as-is
                # The original checksum was calculated with the dict version,
                # but when stored via json.dumps() it becomes a string in JSONB
                # asyncpg might return it as string in some cases
                # So we need to parse it to get back to the dict for checksum calculation
                try:
                    if value.strip():
                        audit_data[key] = json.loads(value)
                    else:
                        audit_data[key] = None
                except (json.JSONDecodeError, AttributeError):
                    # If parsing fails, try to use as-is (shouldn't happen)
                    audit_data[key] = value
            else:
                # It's already a dict/list (asyncpg parses JSONB automatically)
                audit_data[key] = value
    
    # Calculate checksum using the same method as creation
    # Use sort_keys=True and default=str to match the creation logic
    calculated_checksum = hashlib.sha256(json.dumps(audit_data, sort_keys=True, default=str).encode()).hexdigest()
    return stored_checksum == calculated_checksum

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "audit-service"}

@app.get("/audit/logs")
async def get_audit_logs(
    entity_type: Optional[str] = Query(None),
    entity_id: Optional[str] = Query(None),
    event_type: Optional[str] = Query(None),
    hours_back: int = Query(24, description="Hours back to search"),
    limit: int = Query(100, description="Maximum records to return")
):
    """Get audit logs with filtering options"""
    
    where_conditions = ["timestamp >= $1"]
    params = [datetime.utcnow() - timedelta(hours=hours_back)]
    param_count = 1
    
    if entity_type:
        param_count += 1
        where_conditions.append(f"entity_type = ${param_count}")
        params.append(entity_type)
    
    if entity_id:
        param_count += 1
        where_conditions.append(f"entity_id = ${param_count}")
        params.append(entity_id)
    
    if event_type:
        param_count += 1
        where_conditions.append(f"event_type = ${param_count}")
        params.append(event_type)
    
    param_count += 1
    params.append(limit)
    
    query = f"""
        SELECT * FROM audit_log 
        WHERE {' AND '.join(where_conditions)}
        ORDER BY timestamp DESC 
        LIMIT ${param_count}
    """
    
    async with db_manager.pool.acquire() as conn:
        logs = await conn.fetch(query, *params)
        
        result = []
        for log in logs:
            log_dict = dict(log)
            # Verify integrity
            log_dict['integrity_verified'] = verify_audit_checksum(dict(log))
            result.append(log_dict)
        
        return {
            "total_records": len(result),
            "filters_applied": {
                "entity_type": entity_type,
                "entity_id": entity_id, 
                "event_type": event_type,
                "hours_back": hours_back
            },
            "logs": result
        }

@app.get("/audit/account/{account_number}")
async def get_account_audit_trail(account_number: str):
    """Get complete audit trail for a specific account"""
    
    async with db_manager.pool.acquire() as conn:
        # Get account ID
        account = await conn.fetchrow("""
            SELECT id FROM accounts WHERE account_number = $1
        """, account_number)
        
        if not account:
            return {"error": "Account not found"}
        
        # Get audit trail
        logs = await conn.fetch("""
            SELECT * FROM audit_log 
            WHERE entity_type = 'account' AND entity_id = $1
            ORDER BY timestamp ASC
        """, str(account['id']))
        
        # Get related transaction logs
        transaction_logs = await conn.fetch("""
            SELECT al.* FROM audit_log al
            JOIN transactions t ON (t.from_account_id = $1 OR t.to_account_id = $1)
            WHERE al.entity_type = 'transaction'
            ORDER BY al.timestamp ASC
        """, account['id'])
        
        result = []
        for log in list(logs) + list(transaction_logs):
            log_dict = dict(log)
            log_dict['integrity_verified'] = verify_audit_checksum(dict(log))
            result.append(log_dict)
        
        # Sort by timestamp
        result.sort(key=lambda x: x['timestamp'])
        
        return {
            "account_number": account_number,
            "total_events": len(result),
            "audit_trail": result
        }

@app.get("/audit/integrity/verify")
async def verify_audit_integrity(hours_back: int = Query(24)):
    """Verify the integrity of audit logs"""
    
    async with db_manager.pool.acquire() as conn:
        logs = await conn.fetch("""
            SELECT * FROM audit_log 
            WHERE timestamp >= $1
            ORDER BY timestamp DESC
        """, datetime.utcnow() - timedelta(hours=hours_back))
        
        total_records = len(logs)
        verified_records = 0
        corrupted_records = []
        
        for log in logs:
            if verify_audit_checksum(dict(log)):
                verified_records += 1
            else:
                corrupted_records.append({
                    "id": log['id'],
                    "timestamp": log['timestamp'],
                    "event_type": log['event_type'],
                    "entity_type": log['entity_type'],
                    "entity_id": log['entity_id']
                })
        
        return {
            "verification_period_hours": hours_back,
            "total_records_checked": total_records,
            "verified_records": verified_records,
            "corrupted_records_count": len(corrupted_records),
            "corrupted_records": corrupted_records,
            "integrity_percentage": (verified_records / total_records * 100) if total_records > 0 else 100
        }

@app.get("/audit/statistics")
async def get_audit_statistics():
    """Get audit system statistics"""
    
    async with db_manager.pool.acquire() as conn:
        stats = await conn.fetchrow("""
            SELECT 
                COUNT(*) as total_logs,
                COUNT(DISTINCT entity_type) as unique_entity_types,
                COUNT(DISTINCT event_type) as unique_event_types,
                MIN(timestamp) as earliest_log,
                MAX(timestamp) as latest_log
            FROM audit_log
        """)
        
        event_type_counts = await conn.fetch("""
            SELECT event_type, COUNT(*) as count
            FROM audit_log
            GROUP BY event_type
            ORDER BY count DESC
        """)
        
        entity_type_counts = await conn.fetch("""
            SELECT entity_type, COUNT(*) as count
            FROM audit_log
            GROUP BY entity_type
            ORDER BY count DESC
        """)
        
        return {
            "overview": dict(stats),
            "event_type_distribution": [dict(row) for row in event_type_counts],
            "entity_type_distribution": [dict(row) for row in entity_type_counts]
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8003)))
