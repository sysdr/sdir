#!/bin/bash

# Distributed Tracing Demo Setup Script
# This script creates a complete distributed tracing demonstration with multiple microservices
# using OpenTelemetry, Jaeger, and modern Python libraries

set -e

echo "🚀 Setting up Distributed Tracing Demo Environment..."

# Create project structure
mkdir -p distributed-tracing-demo/{services/{api-gateway,order-service,payment-service,inventory-service,notification-service},docker,web,tests}
cd distributed-tracing-demo

# Create requirements.txt
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
redis==5.0.1
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-auto-instrumentation==0.42b0
opentelemetry-instrumentation-fastapi==0.42b0
opentelemetry-instrumentation-httpx==0.42b0
opentelemetry-instrumentation-redis==0.42b0
opentelemetry-exporter-jaeger-thrift==1.21.0
opentelemetry-exporter-otlp==1.21.0
pydantic==2.4.2
python-multipart==0.0.6
jinja2==3.1.2
aiofiles==23.2.1
structlog==23.2.0
EOF

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Jaeger - Distributed Tracing Backend
  jaeger:
    image: jaegertracing/all-in-one:1.50
    ports:
      - "16686:16686"  # Jaeger UI
      - "14268:14268"  # Jaeger collector HTTP
      - "6831:6831/udp"  # Jaeger agent UDP
      - "6832:6832/udp"  # Jaeger agent UDP
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    networks:
      - tracing-network

  # Redis for inter-service communication and caching
  redis:
    image: redis:7.2-alpine
    ports:
      - "6379:6379"
    networks:
      - tracing-network

  # API Gateway Service
  api-gateway:
    build:
      context: .
      dockerfile: docker/Dockerfile.api-gateway
    ports:
      - "8000:8000"
    environment:
      - SERVICE_NAME=api-gateway
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - REDIS_URL=redis://redis:6379
      - ORDER_SERVICE_URL=http://order-service:8001
    depends_on:
      - jaeger
      - redis
      - order-service
    networks:
      - tracing-network

  # Order Service
  order-service:
    build:
      context: .
      dockerfile: docker/Dockerfile.order-service
    ports:
      - "8001:8001"
    environment:
      - SERVICE_NAME=order-service
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - REDIS_URL=redis://redis:6379
      - PAYMENT_SERVICE_URL=http://payment-service:8002
      - INVENTORY_SERVICE_URL=http://inventory-service:8003
      - NOTIFICATION_SERVICE_URL=http://notification-service:8004
    depends_on:
      - jaeger
      - redis
      - payment-service
      - inventory-service
      - notification-service
    networks:
      - tracing-network

  # Payment Service
  payment-service:
    build:
      context: .
      dockerfile: docker/Dockerfile.payment-service
    ports:
      - "8002:8002"
    environment:
      - SERVICE_NAME=payment-service
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - REDIS_URL=redis://redis:6379
    depends_on:
      - jaeger
      - redis
    networks:
      - tracing-network

  # Inventory Service
  inventory-service:
    build:
      context: .
      dockerfile: docker/Dockerfile.inventory-service
    ports:
      - "8003:8003"
    environment:
      - SERVICE_NAME=inventory-service
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - REDIS_URL=redis://redis:6379
    depends_on:
      - jaeger
      - redis
    networks:
      - tracing-network

  # Notification Service
  notification-service:
    build:
      context: .
      dockerfile: docker/Dockerfile.notification-service
    ports:
      - "8004:8004"
    environment:
      - SERVICE_NAME=notification-service
      - JAEGER_ENDPOINT=http://jaeger:14268/api/traces
      - REDIS_URL=redis://redis:6379
    depends_on:
      - jaeger
      - redis
    networks:
      - tracing-network

  # Web Interface
  web-interface:
    build:
      context: .
      dockerfile: docker/Dockerfile.web
    ports:
      - "3000:3000"
    environment:
      - API_GATEWAY_URL=http://api-gateway:8000
    depends_on:
      - api-gateway
    networks:
      - tracing-network

networks:
  tracing-network:
    driver: bridge
EOF

# Create base Dockerfile template
cat > docker/Dockerfile.base << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy common utilities
COPY services/common/ ./common/

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
EOF

# Create common tracing utilities
mkdir -p services/common
cat > services/common/tracing.py << 'EOF'
"""Common tracing utilities for all services."""

import os
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
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

def setup_tracing(service_name: str):
    """Initialize OpenTelemetry tracing for a service."""
    
    # Create resource with service information
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: "1.0.0",
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: "demo"
    })
    
    # Set up tracer provider
    trace.set_tracer_provider(TracerProvider(resource=resource))
    tracer = trace.get_tracer(__name__)
    
    # Configure Jaeger exporter
    jaeger_exporter = JaegerExporter(
        agent_host_name="jaeger",
        agent_port=6831,
    )
    
    # Add batch span processor
    span_processor = BatchSpanProcessor(jaeger_exporter)
    trace.get_tracer_provider().add_span_processor(span_processor)
    
    # Auto-instrument common libraries
    FastAPIInstrumentor.instrument()
    HTTPXClientInstrumentor.instrument()
    RedisInstrumentor.instrument()
    
    logger.info("Tracing initialized", service=service_name)
    return tracer

def get_trace_context():
    """Get current trace context for logging."""
    span = trace.get_current_span()
    if span.get_span_context().is_valid:
        return {
            "trace_id": format(span.get_span_context().trace_id, "032x"),
            "span_id": format(span.get_span_context().span_id, "016x")
        }
    return {}

def trace_request(func_name: str):
    """Decorator to add tracing to functions."""
    def decorator(func):
        async def wrapper(*args, **kwargs):
            tracer = trace.get_tracer(__name__)
            with tracer.start_as_current_span(func_name) as span:
                try:
                    result = await func(*args, **kwargs)
                    span.set_attribute("success", True)
                    return result
                except Exception as e:
                    span.set_attribute("success", False)
                    span.set_attribute("error.message", str(e))
                    span.record_exception(e)
                    logger.error("Function failed", 
                               function=func_name, 
                               error=str(e),
                               **get_trace_context())
                    raise
        return wrapper
    return decorator
EOF

# Create API Gateway service
cat > services/api-gateway/main.py << 'EOF'
"""API Gateway - Entry point for all requests."""

import os
import asyncio
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import httpx
import structlog
from typing import Dict, Any
import uuid

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("api-gateway")

app = FastAPI(title="API Gateway", version="1.0.0")

# Service URLs from environment
ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://localhost:8001")

class OrderRequest(BaseModel):
    user_id: str
    items: list[Dict[str, Any]]
    payment_method: str = "credit_card"

class OrderResponse(BaseModel):
    order_id: str
    status: str
    message: str
    trace_id: str

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "api-gateway"}

@app.get("/", response_class=HTMLResponse)
async def root():
    """Serve the demo web interface."""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Distributed Tracing Demo</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .container { max-width: 800px; margin: 0 auto; }
            .form-group { margin-bottom: 20px; }
            label { display: block; margin-bottom: 5px; font-weight: bold; }
            input, select, textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
            button { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
            button:hover { background: #0056b3; }
            .result { margin-top: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 4px; background: #f9f9f9; }
            .links { margin-top: 30px; }
            .links a { display: inline-block; margin-right: 20px; color: #007bff; text-decoration: none; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔍 Distributed Tracing Demo</h1>
            <p>This demo showcases distributed tracing across multiple microservices.</p>
            
            <div class="form-group">
                <label for="userId">User ID:</label>
                <input type="text" id="userId" value="user-123" placeholder="Enter user ID">
            </div>
            
            <div class="form-group">
                <label for="items">Items (JSON):</label>
                <textarea id="items" rows="4" placeholder='[{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}]'>[{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}, {"id": "item-2", "name": "Gadget", "price": 19.99, "quantity": 1}]</textarea>
            </div>
            
            <div class="form-group">
                <label for="paymentMethod">Payment Method:</label>
                <select id="paymentMethod">
                    <option value="credit_card">Credit Card</option>
                    <option value="paypal">PayPal</option>
                    <option value="bank_transfer">Bank Transfer</option>
                </select>
            </div>
            
            <button onclick="placeOrder()">Place Order</button>
            <button onclick="simulateError()">Simulate Error Scenario</button>
            
            <div id="result" class="result" style="display: none;"></div>
            
            <div class="links">
                <h3>🔗 Quick Links:</h3>
                <a href="http://localhost:16686" target="_blank">📊 Jaeger UI (View Traces)</a>
                <a href="http://localhost:8000/docs" target="_blank">📚 API Documentation</a>
                <a href="http://localhost:8001/docs" target="_blank">🛒 Order Service API</a>
                <a href="http://localhost:8002/docs" target="_blank">💳 Payment Service API</a>
            </div>
        </div>
        
        <script>
            async function placeOrder() {
                const userId = document.getElementById('userId').value;
                const itemsText = document.getElementById('items').value;
                const paymentMethod = document.getElementById('paymentMethod').value;
                
                try {
                    const items = JSON.parse(itemsText);
                    const response = await fetch('/orders', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            user_id: userId,
                            items: items,
                            payment_method: paymentMethod
                        })
                    });
                    
                    const result = await response.json();
                    displayResult(result, response.ok);
                } catch (error) {
                    displayResult({ error: error.message }, false);
                }
            }
            
            async function simulateError() {
                try {
                    const response = await fetch('/orders/simulate-error', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            user_id: "error-user",
                            items: [{"id": "error-item", "name": "Error Item", "price": 0, "quantity": 1}],
                            payment_method: "invalid_method"
                        })
                    });
                    
                    const result = await response.json();
                    displayResult(result, response.ok);
                } catch (error) {
                    displayResult({ error: error.message }, false);
                }
            }
            
            function displayResult(result, success) {
                const resultDiv = document.getElementById('result');
                resultDiv.style.display = 'block';
                resultDiv.style.backgroundColor = success ? '#d4edda' : '#f8d7da';
                resultDiv.style.borderColor = success ? '#c3e6cb' : '#f5c6cb';
                
                let html = '<h4>' + (success ? '✅ Success' : '❌ Error') + '</h4>';
                html += '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
                
                if (result.trace_id) {
                    html += '<p><a href="http://localhost:16686/trace/' + result.trace_id + '" target="_blank">🔍 View Trace in Jaeger</a></p>';
                }
                
                resultDiv.innerHTML = html;
            }
        </script>
    </body>
    </html>
    """

@app.post("/orders", response_model=OrderResponse)
@trace_request("create_order")
async def create_order(order_request: OrderRequest):
    """Create a new order through the order service."""
    
    # Generate a correlation ID for this request
    correlation_id = str(uuid.uuid4())
    
    logger.info("Order creation started", 
                user_id=order_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            # Add tracing headers
            headers = {
                "X-Correlation-ID": correlation_id,
                "X-User-ID": order_request.user_id
            }
            
            response = await client.post(
                f"{ORDER_SERVICE_URL}/orders",
                json=order_request.dict(),
                headers=headers,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                logger.info("Order created successfully",
                           order_id=result.get("order_id"),
                           correlation_id=correlation_id,
                           **get_trace_context())
                
                return OrderResponse(
                    order_id=result["order_id"],
                    status=result["status"],
                    message=result["message"],
                    trace_id=get_trace_context().get("trace_id", "unknown")
                )
            else:
                logger.error("Order creation failed",
                            status_code=response.status_code,
                            response=response.text,
                            correlation_id=correlation_id,
                            **get_trace_context())
                
                raise HTTPException(
                    status_code=response.status_code,
                    detail=f"Order creation failed: {response.text}"
                )
                
    except httpx.TimeoutException:
        logger.error("Order service timeout", 
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=504, detail="Order service timeout")
    except Exception as e:
        logger.error("Unexpected error during order creation",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@app.post("/orders/simulate-error")
@trace_request("simulate_error_scenario")
async def simulate_error_scenario(order_request: OrderRequest):
    """Simulate various error scenarios for demonstration."""
    
    correlation_id = str(uuid.uuid4())
    trace_context = get_trace_context()
    
    logger.info("Error simulation started",
                scenario="payment_failure",
                correlation_id=correlation_id,
                **trace_context)
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {
                "X-Correlation-ID": correlation_id,
                "X-User-ID": order_request.user_id,
                "X-Simulate-Error": "payment_failure"  # Signal to simulate payment failure
            }
            
            response = await client.post(
                f"{ORDER_SERVICE_URL}/orders",
                json=order_request.dict(),
                headers=headers,
                timeout=30.0
            )
            
            result = response.json()
            return {
                **result,
                "trace_id": trace_context.get("trace_id", "unknown"),
                "simulation": "payment_failure_scenario"
            }
            
    except Exception as e:
        logger.error("Error simulation failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **trace_context)
        return {
            "error": str(e),
            "trace_id": trace_context.get("trace_id", "unknown"),
            "simulation": "error_simulation_failed"
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create Order Service
cat > services/order-service/main.py << 'EOF'
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

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("order-service")

app = FastAPI(title="Order Service", version="1.0.0")

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
EOF

# Create Payment Service
cat > services/payment-service/main.py << 'EOF'
"""Payment Service - Handles payment processing."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import structlog
from typing import Optional
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("payment-service")

app = FastAPI(title="Payment Service", version="1.0.0")

class PaymentRequest(BaseModel):
    user_id: str
    amount: float
    payment_method: str = "credit_card"

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "payment-service"}

@app.post("/payments/process")
@trace_request("process_payment")
async def process_payment(
    payment_request: PaymentRequest,
    x_correlation_id: Optional[str] = Header(None),
    x_user_id: Optional[str] = Header(None),
    x_simulate_error: Optional[str] = Header(None)
):
    """Process a payment with simulated payment gateway interaction."""
    
    payment_id = f"pay-{uuid.uuid4()}"
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Payment processing started",
                payment_id=payment_id,
                user_id=payment_request.user_id,
                amount=payment_request.amount,
                payment_method=payment_request.payment_method,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate payment gateway delay
        await asyncio.sleep(random.uniform(0.1, 0.5))
        
        # Simulate error scenarios
        if x_simulate_error == "payment_declined":
            logger.warning("Payment declined (simulated)",
                          payment_id=payment_id,
                          correlation_id=correlation_id,
                          **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": "Payment declined by bank",
                "error_code": "CARD_DECLINED"
            }
        
        # Simulate random payment failures (5% chance)
        if random.random() < 0.05:
            logger.warning("Payment failed due to random error",
                          payment_id=payment_id,
                          correlation_id=correlation_id,
                          **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": "Payment processing failed",
                "error_code": "PROCESSING_ERROR"
            }
        
        # Validate payment method
        valid_methods = ["credit_card", "paypal", "bank_transfer"]
        if payment_request.payment_method not in valid_methods:
            logger.error("Invalid payment method",
                        payment_method=payment_request.payment_method,
                        payment_id=payment_id,
                        correlation_id=correlation_id,
                        **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": f"Invalid payment method: {payment_request.payment_method}",
                "error_code": "INVALID_METHOD"
            }
        
        # Simulate payment gateway interaction
        await simulate_payment_gateway_call(payment_request, payment_id, correlation_id)
        
        # Process successful payment
        logger.info("Payment processed successfully",
                   payment_id=payment_id,
                   user_id=payment_request.user_id,
                   amount=payment_request.amount,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": True,
            "payment_id": payment_id,
            "message": "Payment processed successfully",
            "amount": payment_request.amount,
            "transaction_id": f"txn-{uuid.uuid4()}"
        }
        
    except Exception as e:
        logger.error("Payment processing failed",
                    payment_id=payment_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return {
            "success": False,
            "payment_id": payment_id,
            "message": f"Payment processing error: {str(e)}",
            "error_code": "INTERNAL_ERROR"
        }

@trace_request("payment_gateway_call")
async def simulate_payment_gateway_call(payment_request: PaymentRequest, 
                                       payment_id: str, correlation_id: str):
    """Simulate external payment gateway interaction."""
    
    logger.info("Calling payment gateway",
                payment_id=payment_id,
                gateway="stripe-simulation",
                correlation_id=correlation_id,
                **get_trace_context())
    
    # Simulate gateway response time
    await asyncio.sleep(random.uniform(0.2, 0.8))
    
    # Simulate gateway validation steps
    await validate_card_details(payment_request, correlation_id)
    await check_fraud_rules(payment_request, correlation_id)
    await authorize_payment(payment_request, correlation_id)
    
    logger.info("Payment gateway call completed",
                payment_id=payment_id,
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("validate_card_details")
async def validate_card_details(payment_request: PaymentRequest, correlation_id: str):
    """Simulate card validation."""
    await asyncio.sleep(random.uniform(0.05, 0.15))
    logger.debug("Card details validated",
                user_id=payment_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("check_fraud_rules")
async def check_fraud_rules(payment_request: PaymentRequest, correlation_id: str):
    """Simulate fraud detection."""
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Simulate fraud check result
    fraud_score = random.uniform(0, 100)
    
    logger.debug("Fraud check completed",
                user_id=payment_request.user_id,
                fraud_score=fraud_score,
                correlation_id=correlation_id,
                **get_trace_context())
    
    if fraud_score > 85:
        raise Exception("Transaction flagged for fraud review")

@trace_request("authorize_payment")
async def authorize_payment(payment_request: PaymentRequest, correlation_id: str):
    """Simulate payment authorization."""
    await asyncio.sleep(random.uniform(0.1, 0.2))
    logger.debug("Payment authorized",
                user_id=payment_request.user_id,
                amount=payment_request.amount,
                correlation_id=correlation_id,
                **get_trace_context())

@app.get("/payments/{payment_id}")
@trace_request("get_payment_status")
async def get_payment_status(payment_id: str):
    """Get payment status by ID."""
    
    logger.info("Payment status requested",
                payment_id=payment_id,
                **get_trace_context())
    
    # In a real system, this would query a database
    return {
        "payment_id": payment_id,
        "status": "completed",
        "message": "Payment processed successfully"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
EOF

# Create Inventory Service
cat > services/inventory-service/main.py << 'EOF'
"""Inventory Service - Manages product inventory and reservations."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import redis.asyncio as redis
import structlog
from typing import Optional, List, Dict, Any
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("inventory-service")

app = FastAPI(title="Inventory Service", version="1.0.0")

# Redis connection
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
redis_client = None

# Mock inventory data
INVENTORY_DATA = {
    "item-1": {"name": "Widget", "price": 29.99, "stock": 100},
    "item-2": {"name": "Gadget", "price": 19.99, "stock": 50},
    "error-item": {"name": "Error Item", "price": 0, "stock": 0}  # For error simulation
}

@app.on_event("startup")
async def startup_event():
    global redis_client
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    
    # Initialize inventory in Redis
    for item_id, item_data in INVENTORY_DATA.items():
        await redis_client.hset(f"inventory:{item_id}", mapping=item_data)
    
    logger.info("Inventory service started", redis_url=REDIS_URL)

@app.on_event("shutdown")
async def shutdown_event():
    if redis_client:
        await redis_client.close()

class InventoryItem(BaseModel):
    id: str
    name: str
    price: float
    quantity: int

class InventoryCheckRequest(BaseModel):
    items: List[InventoryItem]

class InventoryReserveRequest(BaseModel):
    order_id: str
    items: List[InventoryItem]

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "inventory-service"}

@app.post("/inventory/check")
@trace_request("check_inventory_availability")
async def check_inventory_availability(
    request: InventoryCheckRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Check if requested items are available in inventory."""
    
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Inventory availability check started",
                items_count=len(request.items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate database query delay
        await asyncio.sleep(random.uniform(0.05, 0.2))
        
        total_amount = 0.0
        availability_results = []
        all_available = True
        
        for item in request.items:
            # Get current inventory from Redis
            inventory_data = await redis_client.hgetall(f"inventory:{item.id}")
            
            if not inventory_data:
                logger.warning("Item not found in inventory",
                              item_id=item.id,
                              correlation_id=correlation_id,
                              **get_trace_context())
                availability_results.append({
                    "item_id": item.id,
                    "available": False,
                    "reason": "Item not found"
                })
                all_available = False
                continue
            
            current_stock = int(inventory_data.get("stock", 0))
            item_price = float(inventory_data.get("price", 0))
            
            if current_stock >= item.quantity:
                availability_results.append({
                    "item_id": item.id,
                    "available": True,
                    "current_stock": current_stock,
                    "requested_quantity": item.quantity,
                    "unit_price": item_price
                })
                total_amount += item_price * item.quantity
            else:
                logger.warning("Insufficient inventory",
                              item_id=item.id,
                              current_stock=current_stock,
                              requested_quantity=item.quantity,
                              correlation_id=correlation_id,
                              **get_trace_context())
                availability_results.append({
                    "item_id": item.id,
                    "available": False,
                    "current_stock": current_stock,
                    "requested_quantity": item.quantity,
                    "reason": "Insufficient stock"
                })
                all_available = False
        
        logger.info("Inventory availability check completed",
                   all_available=all_available,
                   total_amount=total_amount,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "available": all_available,
            "total_amount": total_amount,
            "items": availability_results,
            "checked_at": "2025-06-13T10:00:00Z"
        }
        
    except Exception as e:
        logger.error("Inventory availability check failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Inventory check failed: {str(e)}")

@app.post("/inventory/reserve")
@trace_request("reserve_inventory_items")
async def reserve_inventory_items(
    request: InventoryReserveRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Reserve inventory items for an order."""
    
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Inventory reservation started",
                order_id=request.order_id,
                items_count=len(request.items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate database transaction delay
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        reservation_results = []
        all_reserved = True
        
        # Start transaction simulation
        async with redis_client.pipeline(transaction=True) as pipe:
            for item in request.items:
                try:
                    # Watch the inventory key for changes
                    await pipe.watch(f"inventory:{item.id}")
                    
                    # Get current inventory
                    inventory_data = await redis_client.hgetall(f"inventory:{item.id}")
                    
                    if not inventory_data:
                        logger.error("Item not found during reservation",
                                   item_id=item.id,
                                   order_id=request.order_id,
                                   correlation_id=correlation_id,
                                   **get_trace_context())
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": False,
                            "reason": "Item not found"
                        })
                        all_reserved = False
                        continue
                    
                    current_stock = int(inventory_data.get("stock", 0))
                    
                    if current_stock >= item.quantity:
                        # Reserve the items by reducing stock
                        new_stock = current_stock - item.quantity
                        
                        # Update inventory with reservation
                        pipe.multi()
                        await pipe.hset(f"inventory:{item.id}", "stock", new_stock)
                        
                        # Store reservation record
                        reservation_data = {
                            "order_id": request.order_id,
                            "item_id": item.id,
                            "quantity": item.quantity,
                            "reserved_at": "2025-06-13T10:00:00Z"
                        }
                        await pipe.setex(
                            f"reservation:{request.order_id}:{item.id}",
                            3600,
                            json.dumps(reservation_data)
                        )
                        
                        await pipe.execute()
                        
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": True,
                            "quantity": item.quantity,
                            "remaining_stock": new_stock
                        })
                        
                        logger.debug("Item reserved successfully",
                                   item_id=item.id,
                                   quantity=item.quantity,
                                   remaining_stock=new_stock,
                                   order_id=request.order_id,
                                   correlation_id=correlation_id,
                                   **get_trace_context())
                    else:
                        logger.warning("Cannot reserve item - insufficient stock",
                                     item_id=item.id,
                                     current_stock=current_stock,
                                     requested_quantity=item.quantity,
                                     order_id=request.order_id,
                                     correlation_id=correlation_id,
                                     **get_trace_context())
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": False,
                            "current_stock": current_stock,
                            "requested_quantity": item.quantity,
                            "reason": "Insufficient stock"
                        })
                        all_reserved = False
                        
                except redis.WatchError:
                    logger.warning("Inventory changed during reservation",
                                 item_id=item.id,
                                 order_id=request.order_id,
                                 correlation_id=correlation_id,
                                 **get_trace_context())
                    reservation_results.append({
                        "item_id": item.id,
                        "reserved": False,
                        "reason": "Inventory changed during transaction"
                    })
                    all_reserved = False
        
        logger.info("Inventory reservation completed",
                   order_id=request.order_id,
                   all_reserved=all_reserved,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": all_reserved,
            "order_id": request.order_id,
            "items": reservation_results,
            "reserved_at": "2025-06-13T10:00:00Z"
        }
        
    except Exception as e:
        logger.error("Inventory reservation failed",
                    order_id=request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Inventory reservation failed: {str(e)}")

@app.get("/inventory/{item_id}")
@trace_request("get_item_inventory")
async def get_item_inventory(item_id: str):
    """Get current inventory for a specific item."""
    
    logger.info("Getting item inventory",
                item_id=item_id,
                **get_trace_context())
    
    try:
        inventory_data = await redis_client.hgetall(f"inventory:{item_id}")
        
        if not inventory_data:
            raise HTTPException(status_code=404, detail="Item not found")
        
        return {
            "item_id": item_id,
            "name": inventory_data.get("name"),
            "price": float(inventory_data.get("price", 0)),
            "stock": int(inventory_data.get("stock", 0))
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get item inventory",
                    item_id=item_id,
                    error=str(e),
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Failed to get inventory: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
EOF

# Create Notification Service
cat > services/notification-service/main.py << 'EOF'
"""Notification Service - Handles order and system notifications."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import structlog
from typing import Optional
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("notification-service")

app = FastAPI(title="Notification Service", version="1.0.0")

class NotificationRequest(BaseModel):
    order_id: str
    user_id: str
    type: str = "order_confirmation"
    message: Optional[str] = None

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "notification-service"}

@app.post("/notifications/order-confirmation")
@trace_request("send_order_confirmation")
async def send_order_confirmation(
    notification_request: NotificationRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Send order confirmation notification."""
    
    notification_id = f"notif-{uuid.uuid4()}"
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Order confirmation notification started",
                notification_id=notification_id,
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate multiple notification channels
        channels_sent = []
        
        # Send email notification
        if await send_email_notification(notification_request, correlation_id):
            channels_sent.append("email")
        
        # Send SMS notification
        if await send_sms_notification(notification_request, correlation_id):
            channels_sent.append("sms")
        
        # Send push notification
        if await send_push_notification(notification_request, correlation_id):
            channels_sent.append("push")
        
        logger.info("Order confirmation notification completed",
                   notification_id=notification_id,
                   order_id=notification_request.order_id,
                   channels_sent=channels_sent,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": True,
            "notification_id": notification_id,
            "order_id": notification_request.order_id,
            "channels_sent": channels_sent,
            "message": "Order confirmation notifications sent successfully"
        }
        
    except Exception as e:
        logger.error("Order confirmation notification failed",
                    notification_id=notification_id,
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Notification failed: {str(e)}")

@trace_request("send_email_notification")
async def send_email_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send email notification."""
    
    logger.info("Sending email notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate email service delay
        await asyncio.sleep(random.uniform(0.2, 0.5))
        
        # Simulate email template rendering
        await render_email_template(notification_request, correlation_id)
        
        # Simulate email delivery
        await deliver_email(notification_request, correlation_id)
        
        logger.info("Email notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("Email notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("render_email_template")
async def render_email_template(notification_request: NotificationRequest, correlation_id: str):
    """Render email template for the notification."""
    await asyncio.sleep(random.uniform(0.05, 0.1))
    
    logger.debug("Email template rendered",
                order_id=notification_request.order_id,
                template="order_confirmation_template",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("deliver_email")
async def deliver_email(notification_request: NotificationRequest, correlation_id: str):
    """Deliver email via email service provider."""
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Simulate occasional email delivery failures
    if random.random() < 0.05:
        raise Exception("Email delivery service temporarily unavailable")
    
    logger.debug("Email delivered successfully",
                order_id=notification_request.order_id,
                provider="sendgrid-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("send_sms_notification")
async def send_sms_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send SMS notification."""
    
    logger.info("Sending SMS notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate SMS service delay
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        # Simulate SMS delivery
        await deliver_sms(notification_request, correlation_id)
        
        logger.info("SMS notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("SMS notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("deliver_sms")
async def deliver_sms(notification_request: NotificationRequest, correlation_id: str):
    """Deliver SMS via SMS service provider."""
    await asyncio.sleep(random.uniform(0.05, 0.2))
    
    # Simulate occasional SMS delivery failures
    if random.random() < 0.03:
        raise Exception("SMS delivery service rate limited")
    
    logger.debug("SMS delivered successfully",
                order_id=notification_request.order_id,
                provider="twilio-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("send_push_notification")
async def send_push_notification(notification_request: NotificationRequest, correlation_id: str):
    """Send push notification."""
    
    logger.info("Sending push notification",
                order_id=notification_request.order_id,
                user_id=notification_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate push notification service delay
        await asyncio.sleep(random.uniform(0.05, 0.15))
        
        # Simulate push notification delivery
        await deliver_push_notification(notification_request, correlation_id)
        
        logger.info("Push notification sent successfully",
                   order_id=notification_request.order_id,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return True
        
    except Exception as e:
        logger.error("Push notification failed",
                    order_id=notification_request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return False

@trace_request("deliver_push_notification")
async def deliver_push_notification(notification_request: NotificationRequest, correlation_id: str):
    """Deliver push notification via push service provider."""
    await asyncio.sleep(random.uniform(0.02, 0.08))
    
    logger.debug("Push notification delivered successfully",
                order_id=notification_request.order_id,
                provider="fcm-simulation",
                correlation_id=correlation_id,
                **get_trace_context())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)
EOF

# Create individual Dockerfiles for each service
for service in api-gateway order-service payment-service inventory-service notification-service; do
    cat > docker/Dockerfile.$service << EOF
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy common utilities
COPY services/common/ ./common/

# Copy service-specific code
COPY services/$service/ ./

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
  CMD curl -f http://localhost:800${service: -1}/health || exit 1

# Run the service
CMD ["python", "main.py"]
EOF
done

# Create web interface Dockerfile
cat > docker/Dockerfile.web << 'EOF'
FROM nginx:alpine

COPY web/ /usr/share/nginx/html/

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;", "-p", "/tmp", "-c", "/etc/nginx/nginx.conf"]
EOF

# Create test script
cat > tests/test_distributed_tracing.py << 'EOF'
#!/usr/bin/env python3
"""Test script for distributed tracing demo."""

import asyncio
import httpx
import json
import time
from typing import Dict, Any

API_GATEWAY_URL = "http://localhost:8000"
JAEGER_UI_URL = "http://localhost:16686"

async def test_successful_order():
    """Test a successful order flow."""
    print("🧪 Testing successful order flow...")
    
    async with httpx.AsyncClient() as client:
        order_data = {
            "user_id": "test-user-123",
            "items": [
                {"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2},
                {"id": "item-2", "name": "Gadget", "price": 19.99, "quantity": 1}
            ],
            "payment_method": "credit_card"
        }
        
        start_time = time.time()
        response = await client.post(f"{API_GATEWAY_URL}/orders", json=order_data, timeout=30.0)
        end_time = time.time()
        
        print(f"⏱️  Request completed in {end_time - start_time:.2f} seconds")
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Order created successfully: {result['order_id']}")
            print(f"🔍 Trace ID: {result['trace_id']}")
            print(f"📊 View trace: {JAEGER_UI_URL}/trace/{result['trace_id']}")
            return True
        else:
            print(f"❌ Order failed: {response.status_code} - {response.text}")
            return False

async def test_payment_failure():
    """Test payment failure scenario."""
    print("🧪 Testing payment failure scenario...")
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_GATEWAY_URL}/orders/simulate-error",
            json={
                "user_id": "error-user",
                "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
                "payment_method": "credit_card"
            },
            timeout=30.0
        )
        
        result = response.json()
        print(f"⚠️  Payment failure simulated: {result.get('message', 'Unknown error')}")
        print(f"🔍 Trace ID: {result.get('trace_id', 'N/A')}")
        
        if result.get('trace_id'):
            print(f"📊 View trace: {JAEGER_UI_URL}/trace/{result['trace_id']}")
        
        return True

async def test_service_health():
    """Test health endpoints of all services."""
    print("🧪 Testing service health...")
    
    services = [
        ("API Gateway", "http://localhost:8000/health"),
        ("Order Service", "http://localhost:8001/health"),
        ("Payment Service", "http://localhost:8002/health"),
        ("Inventory Service", "http://localhost:8003/health"),
        ("Notification Service", "http://localhost:8004/health")
    ]
    
    async with httpx.AsyncClient() as client:
        for service_name, health_url in services:
            try:
                response = await client.get(health_url, timeout=5.0)
                if response.status_code == 200:
                    print(f"✅ {service_name} is healthy")
                else:
                    print(f"⚠️  {service_name} health check failed: {response.status_code}")
            except Exception as e:
                print(f"❌ {service_name} is unreachable: {str(e)}")

async def run_load_test():
    """Run a simple load test to generate multiple traces."""
    print("🧪 Running load test (10 concurrent orders)...")
    
    async def create_order(order_id: int):
        async with httpx.AsyncClient() as client:
            order_data = {
                "user_id": f"load-test-user-{order_id}",
                "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
                "payment_method": "credit_card"
            }
            
            try:
                response = await client.post(f"{API_GATEWAY_URL}/orders", json=order_data, timeout=30.0)
                if response.status_code == 200:
                    result = response.json()
                    return f"✅ Order {order_id}: {result['order_id']}"
                else:
                    return f"❌ Order {order_id} failed: {response.status_code}"
            except Exception as e:
                return f"❌ Order {order_id} error: {str(e)}"
    
    # Create 10 concurrent orders
    tasks = [create_order(i) for i in range(1, 11)]
    results = await asyncio.gather(*tasks)
    
    for result in results:
        print(result)
    
    print(f"📊 View all traces: {JAEGER_UI_URL}")

async def main():
    """Run all tests."""
    print("🚀 Starting Distributed Tracing Demo Tests")
    print("=" * 50)
    
    # Wait for services to be ready
    print("⏳ Waiting for services to be ready...")
    await asyncio.sleep(10)
    
    # Test service health
    await test_service_health()
    print()
    
    # Test successful order
    await test_successful_order()
    print()
    
    # Test payment failure
    await test_payment_failure()
    print()
    
    # Run load test
    await run_load_test()
    print()
    
    print("🎉 All tests completed!")
    print(f"🔍 Open Jaeger UI: {JAEGER_UI_URL}")
    print(f"🌐 Open Demo Web Interface: http://localhost:3000")

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Make test script executable
chmod +x tests/test_distributed_tracing.py

# Create README with instructions
cat > README.md << 'EOF'
# Distributed Tracing Demo

This demo showcases distributed tracing across multiple microservices using OpenTelemetry and Jaeger.

## Architecture

- **API Gateway**: Entry point for all requests
- **Order Service**: Orchestrates order processing
- **Payment Service**: Handles payment processing
- **Inventory Service**: Manages product inventory
- **Notification Service**: Sends order confirmations
- **Redis**: Inter-service communication and caching
- **Jaeger**: Distributed tracing backend

## Quick Start

1. **Build and start all services:**
   ```bash
   docker-compose up --build
   ```

2. **Wait for services to be ready (about 2-3 minutes):**
   ```bash
   # Check if all services are healthy
   docker-compose ps
   ```

3. **Run the test suite:**
   ```bash
   python3 tests/test_distributed_tracing.py
   ```

4. **Open the web interfaces:**
   - Demo Web Interface: http://localhost:3000
   - Jaeger UI: http://localhost:16686
   - API Documentation: http://localhost:8000/docs

## Usage

### Web Interface
1. Open http://localhost:3000
2. Fill in the order form
3. Click "Place Order" to see successful flow
4. Click "Simulate Error Scenario" to see failure tracing
5. View traces in Jaeger UI using the provided links

### Direct API Testing
```bash
# Successful order
curl -X POST http://localhost:8000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "demo-user",
    "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}],
    "payment_method": "credit_card"
  }'

# Error simulation
curl -X POST http://localhost:8000/orders/simulate-error \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "error-user",
    "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
    "payment_method": "invalid_method"
  }'
```

## Key Features Demonstrated

1. **Request Flow Tracing**: Follow requests across all services
2. **Error Propagation**: See how errors are traced through the system
3. **Asynchronous Operations**: Observe async notification handling
4. **Cross-Service Correlation**: Track requests with correlation IDs
5. **Performance Analysis**: Analyze latency across service boundaries
6. **Sampling Strategies**: See traces being collected and stored

## Observing Traces

1. **Open Jaeger UI**: http://localhost:16686
2. **Select Service**: Choose "api-gateway" from the service dropdown
3. **Find Traces**: Click "Find Traces" to see recent traces
4. **Trace Details**: Click on any trace to see the detailed flow
5. **Span Analysis**: Examine individual spans for timing and errors

## Troubleshooting

- **Services not starting**: Check `docker-compose logs <service-name>`
- **Traces not appearing**: Wait 30 seconds for trace propagation
- **Port conflicts**: Modify ports in docker-compose.yml if needed
- **Memory issues**: Ensure Docker has at least 4GB RAM allocated

## Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes and images
docker-compose down -v --rmi all
```
EOF

echo "✅ Distributed Tracing Demo setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Run: docker-compose up --build"
echo "2. Wait 2-3 minutes for services to start"
echo "3. Run: python3 tests/test_distributed_tracing.py"
echo "4. Open: http://localhost:3000 (Demo Interface)"
echo "5. Open: http://localhost:16686 (Jaeger UI)"
echo ""
echo "🎯 The demo showcases:"
echo "   • Request tracing across 5 microservices"
echo "   • Error scenario simulation and tracing"
echo "   • Asynchronous operation tracing"
echo "   • Cross-service correlation patterns"
echo "   • Performance analysis capabilities"