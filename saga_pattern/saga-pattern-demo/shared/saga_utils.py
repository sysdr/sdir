import asyncio
import redis.asyncio as redis
import json
import logging
import uuid
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional
import httpx

class SAGAStatus(Enum):
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    COMPENSATING = "COMPENSATING"
    COMPENSATED = "COMPENSATED"

class SAGAStep:
    def __init__(self, service: str, action: str, compensation_action: str, data: Dict):
        self.service = service
        self.action = action
        self.compensation_action = compensation_action
        self.data = data
        self.status = SAGAStatus.PENDING
        self.result = None
        self.error = None
        self.timestamp = datetime.utcnow().isoformat()

class SAGAOrchestrator:
    def __init__(self, redis_url: str = "redis://redis:6379"):
        self.redis_url = redis_url
        self.redis = None
        
    async def init_redis(self):
        self.redis = redis.from_url(self.redis_url, decode_responses=True)
        await self.redis.ping()
        
    async def create_saga(self, transaction_id: str, steps: List[SAGAStep]) -> str:
        saga_data = {
            "transaction_id": transaction_id,
            "status": SAGAStatus.IN_PROGRESS.value,
            "steps": [self._step_to_dict(step) for step in steps],
            "created_at": datetime.utcnow().isoformat(),
            "current_step": 0
        }
        await self.redis.set(f"saga:{transaction_id}", json.dumps(saga_data))
        return transaction_id
        
    async def execute_saga(self, transaction_id: str) -> Dict:
        saga_data = await self.get_saga(transaction_id)
        if not saga_data:
            raise Exception(f"SAGA {transaction_id} not found")
            
        steps = saga_data["steps"]
        current_step = saga_data["current_step"]
        
        # Execute forward steps
        for i in range(current_step, len(steps)):
            step = steps[i]
            try:
                result = await self._execute_step(step)
                steps[i]["status"] = SAGAStatus.COMPLETED.value
                steps[i]["result"] = result
                saga_data["current_step"] = i + 1
                await self._update_saga(transaction_id, saga_data)
                
            except Exception as e:
                steps[i]["status"] = SAGAStatus.FAILED.value
                steps[i]["error"] = str(e)
                
                # Start compensation
                saga_data["status"] = SAGAStatus.COMPENSATING.value
                await self._update_saga(transaction_id, saga_data)
                
                # Compensate completed steps in reverse order
                for j in range(i - 1, -1, -1):
                    await self._compensate_step(steps[j])
                    
                saga_data["status"] = SAGAStatus.COMPENSATED.value
                await self._update_saga(transaction_id, saga_data)
                return saga_data
                
        saga_data["status"] = SAGAStatus.COMPLETED.value
        await self._update_saga(transaction_id, saga_data)
        return saga_data
        
    async def _execute_step(self, step: Dict) -> Dict:
        service_urls = {
            "payment": "http://payment-service:8001",
            "inventory": "http://inventory-service:8002", 
            "shipping": "http://shipping-service:8003"
        }
        
        url = f"{service_urls[step['service']]}/{step['action']}"
        timeout = httpx.Timeout(10.0, read=30.0)
        
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(url, json=step['data'])
            if response.status_code != 200:
                raise Exception(f"Step failed: {response.text}")
            return response.json()
            
    async def _compensate_step(self, step: Dict):
        if step["status"] != SAGAStatus.COMPLETED.value:
            return
            
        service_urls = {
            "payment": "http://payment-service:8001",
            "inventory": "http://inventory-service:8002",
            "shipping": "http://shipping-service:8003"
        }
        
        url = f"{service_urls[step['service']]}/{step['compensation_action']}"
        timeout = httpx.Timeout(10.0, read=30.0)
        
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                compensation_data = {**step['data'], **step.get('result', {})}
                response = await client.post(url, json=compensation_data)
                step["compensation_status"] = "COMPLETED"
            except Exception as e:
                step["compensation_status"] = f"FAILED: {str(e)}"
                
    async def get_saga(self, transaction_id: str) -> Optional[Dict]:
        data = await self.redis.get(f"saga:{transaction_id}")
        return json.loads(data) if data else None
        
    async def _update_saga(self, transaction_id: str, saga_data: Dict):
        await self.redis.set(f"saga:{transaction_id}", json.dumps(saga_data))
        
    def _step_to_dict(self, step: SAGAStep) -> Dict:
        return {
            "service": step.service,
            "action": step.action,
            "compensation_action": step.compensation_action,
            "data": step.data,
            "status": step.status.value,
            "result": step.result,
            "error": step.error,
            "timestamp": step.timestamp
        }

def setup_logging(service_name: str):
    logging.basicConfig(
        level=logging.INFO,
        format=f'%(asctime)s - {service_name} - %(levelname)s - %(message)s'
    )
    return logging.getLogger(service_name)
