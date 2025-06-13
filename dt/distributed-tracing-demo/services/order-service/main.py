"""Order Service - Handles order processing and orchestration."""

import os
import asyncio
import uuid
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import httpx
import redis.asyncio as redis
import structlog
from typing import Dict, Any, Optional
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

app = FastAPI(title="Order Service", version="1.0.0")

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("order-service", app)

# Service URLs and Redis connection
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://localhost:8002")
INVENTORY_SERVICE_URL = os.getenv("INVENTORY_SERVICE_URL", "http://localhost:8003")
NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://localhost:8004")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

# Redis client
redis_client = None

@app.on_event("startup")
async def startup_event():
    global redis_client
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    logger.info("Order service started", redis_url=REDIS_URL)

@app.on_event("shutdown")
async def shutdown_event():
    if redis_client:
        await redis_client.close()

class OrderItem(BaseModel):
    id: str
    name: str
    price: float
    quantity: int

class OrderRequest(BaseModel):
    user_id: str
    items: list[OrderItem]
    payment_method: str = "credit_card"

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "order-service"}

@app.post("/orders")
@trace_request("process_order")
async def process_order(
    order_request: OrderRequest,
    x_correlation_id: Optional[str] = Header(None),
    x_user_id: Optional[str] = Header(None),
    x_simulate_error: Optional[str] = Header(None)
):
    """Process a new order with distributed tracing."""
    
    order_id = f"order-{uuid.uuid4()}"
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Order processing started",
                order_id=order_id,
                user_id=order_request.user_id,
                correlation_id=correlation_id,
                items_count=len(order_request.items),
                **get_trace_context())
    
    try:
        # Store order in Redis for tracking
        order_data = {
            "order_id": order_id,
            "user_id": order_request.user_id,
            "items": [item.dict() for item in order_request.items],
            "payment_method": order_request.payment_method,
            "status": "processing",
            "correlation_id": correlation_id,
            "trace_id": get_trace_context().get("trace_id", "unknown")
        }
        
        await redis_client.setex(f"order:{order_id}", 3600, json.dumps(order_data))
        
        # Step 1: Check inventory
        inventory_result = await check_inventory(order_request.items, correlation_id)
        if not inventory_result["available"]:
            await update_order_status(order_id, "failed", "Insufficient inventory")
            raise HTTPException(status_code=400, detail="Insufficient inventory")
        
        # Step 2: Process payment (may simulate error)
        payment_result = await process_payment(
            order_request.user_id,
            inventory_result["total_amount"],
            order_request.payment_method,
            correlation_id,
            simulate_error=(x_simulate_error == "payment_failure")
        )
        
        if not payment_result["success"]:
            await update_order_status(order_id, "failed", "Payment failed")
            # Still return order info for tracing demonstration
            return {
                "order_id": order_id,
                "status": "failed",
                "message": f"Payment failed: {payment_result['message']}",
                "trace_id": get_trace_context().get("trace_id", "unknown")
            }
        
        # Step 3: Reserve inventory
        reservation_result = await reserve_inventory(order_request.items, order_id, correlation_id)
        if not reservation_result["success"]:
            # Refund payment (would be implemented in production)
            await update_order_status(order_id, "failed", "Inventory reservation failed")
            raise HTTPException(status_code=500, detail="Inventory reservation failed")
        
        # Step 4: Send notifications (async)
        asyncio.create_task(send_order_notification(order_id, order_request.user_id, correlation_id))
        
        # Step 5: Update order status
        await update_order_status(order_id, "confirmed", "Order processed successfully")
        
        logger.info("Order processed successfully",
                   order_id=order_id,
                   user_id=order_request.user_id,
                   correlation_id=correlation_id,
                   total_amount=inventory_result["total_amount"],
                   **get_trace_context())
        
        return {
            "order_id": order_id,
            "status": "confirmed",
            "message": "Order processed successfully",
            "total_amount": inventory_result["total_amount"],
            "payment_id": payment_result["payment_id"],
            "trace_id": get_trace_context().get("trace_id", "unknown")
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Order processing failed",
                    order_id=order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        await update_order_status(order_id, "failed", f"Processing error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Order processing failed: {str(e)}")

@trace_request("check_inventory")
async def check_inventory(items: list[OrderItem], correlation_id: str):
    """Check if items are available in inventory."""
    
    logger.info("Checking inventory",
                items_count=len(items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {"X-Correlation-ID": correlation_id}
            
            response = await client.post(
                f"{INVENTORY_SERVICE_URL}/inventory/check",
                json={"items": [item.dict() for item in items]},
                headers=headers,
                timeout=10.0
            )
            
            if response.status_code == 200:
                result = response.json()
                logger.info("Inventory check completed",
                           available=result["available"],
                           total_amount=result.get("total_amount", 0),
                           correlation_id=correlation_id,
                           **get_trace_context())
                return result
            else:
                logger.error("Inventory check failed",
                            status_code=response.status_code,
                            response=response.text,
                            correlation_id=correlation_id,
                            **get_trace_context())
                return {"available": False, "message": "Inventory service error"}
                
    except Exception as e:
        logger.error("Inventory service communication failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return {"available": False, "message": f"Service communication error: {str(e)}"}

@trace_request("process_payment")
async def process_payment(user_id: str, amount: float, payment_method: str, 
                         correlation_id: str, simulate_error: bool = False):
    """Process payment for the order."""
    
    logger.info("Processing payment",
                user_id=user_id,
                amount=amount,
                payment_method=payment_method,
                correlation_id=correlation_id,
                simulate_error=simulate_error,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {
                "X-Correlation-ID": correlation_id,
                "X-User-ID": user_id
            }
            
            if simulate_error:
                headers["X-Simulate-Error"] = "payment_declined"
            
            response = await client.post(
                f"{PAYMENT_SERVICE_URL}/payments/process",
                json={
                    "user_id": user_id,
                    "amount": amount,
                    "payment_method": payment_method
                },
                headers=headers,
                timeout=15.0
            )
            
            result = response.json()
            
            if response.status_code == 200 and result.get("success"):
                logger.info("Payment processed successfully",
                           payment_id=result.get("payment_id"),
                           correlation_id=correlation_id,
                           **get_trace_context())
            else:
                logger.warning("Payment processing failed",
                              status_code=response.status_code,
                              result=result,
                              correlation_id=correlation_id,
                              **get_trace_context())
            
            return result
            
    except Exception as e:
        logger.error("Payment service communication failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return {"success": False, "message": f"Payment service error: {str(e)}"}

@trace_request("reserve_inventory")
async def reserve_inventory(items: list[OrderItem], order_id: str, correlation_id: str):
    """Reserve inventory items for the order."""
    
    logger.info("Reserving inventory",
                order_id=order_id,
                items_count=len(items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {"X-Correlation-ID": correlation_id}
            
            response = await client.post(
                f"{INVENTORY_SERVICE_URL}/inventory/reserve",
                json={
                    "order_id": order_id,
                    "items": [item.dict() for item in items]
                },
                headers=headers,
                timeout=10.0
            )
            
            if response.status_code == 200:
                result = response.json()
                logger.info("Inventory reserved successfully",
                           order_id=order_id,
                           correlation_id=correlation_id,
                           **get_trace_context())
                return result
            else:
                logger.error("Inventory reservation failed",
                            status_code=response.status_code,
                            response=response.text,
                            correlation_id=correlation_id,
                            **get_trace_context())
                return {"success": False, "message": "Inventory reservation failed"}
                
    except Exception as e:
        logger.error("Inventory service communication failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return {"success": False, "message": f"Service communication error: {str(e)}"}

@trace_request("send_order_notification")
async def send_order_notification(order_id: str, user_id: str, correlation_id: str):
    """Send order confirmation notification (asynchronous)."""
    
    logger.info("Sending order notification",
                order_id=order_id,
                user_id=user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {"X-Correlation-ID": correlation_id}
            
            response = await client.post(
                f"{NOTIFICATION_SERVICE_URL}/notifications/order-confirmation",
                json={
                    "order_id": order_id,
                    "user_id": user_id,
                    "type": "order_confirmation"
                },
                headers=headers,
                timeout=5.0
            )
            
            if response.status_code == 200:
                logger.info("Order notification sent successfully",
                           order_id=order_id,
                           correlation_id=correlation_id,
                           **get_trace_context())
            else:
                logger.warning("Order notification failed",
                              status_code=response.status_code,
                              response=response.text,
                              correlation_id=correlation_id,
                              **get_trace_context())
                
    except Exception as e:
        logger.warning("Notification service communication failed",
                      error=str(e),
                      correlation_id=correlation_id,
                      **get_trace_context())

async def update_order_status(order_id: str, status: str, message: str):
    """Update order status in Redis."""
    try:
        order_key = f"order:{order_id}"
        order_data = await redis_client.get(order_key)
        
        if order_data:
            order_dict = json.loads(order_data)
            order_dict["status"] = status
            order_dict["message"] = message
            await redis_client.setex(order_key, 3600, json.dumps(order_dict))
            
    except Exception as e:
        logger.error("Failed to update order status",
                    order_id=order_id,
                    error=str(e),
                    **get_trace_context())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
