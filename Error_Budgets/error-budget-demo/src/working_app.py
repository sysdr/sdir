#!/usr/bin/env python3

import asyncio
import logging
import random
import time
from fastapi import FastAPI, Request, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import redis

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global error rates for services
service_error_rates = {
    'user-service': 0.01,
    'payment-service': 0.01,
    'order-service': 0.01
}

# Create dashboard app
dashboard_app = FastAPI(title="Error Budget Dashboard")
dashboard_app.mount("/static", StaticFiles(directory="web"), name="static")
templates = Jinja2Templates(directory="web")

# Add CORS middleware to dashboard
dashboard_app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create service apps
user_service_app = FastAPI(title="User Service")
payment_service_app = FastAPI(title="Payment Service")
order_service_app = FastAPI(title="Order Service")

# Add CORS middleware to all service apps
for app in [user_service_app, payment_service_app, order_service_app]:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

@dashboard_app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@dashboard_app.get("/api/error-budgets")
async def get_error_budgets():
    """Get current error budget status for all services"""
    try:
        redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
        redis_client.ping()  # Test connection
        logger.info("Connected to Redis at redis:6379")
    except:
        try:
            # Fallback to localhost for development
            redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
            redis_client.ping()
            logger.info("Connected to Redis at localhost:6379")
        except:
            # Use None if Redis is not available
            redis_client = None
            logger.info("Redis not available - using mock data")
    
    # Calculate error budgets based on current error rates
    budgets = {}
    for service_name in ['user-service', 'payment-service', 'order-service']:
        error_rate = service_error_rates.get(service_name, 0.01)
        success_rate = 1.0 - error_rate
        
        # Calculate budget remaining (simplified)
        sla_targets = {
            'user-service': 0.999,
            'payment-service': 0.995,
            'order-service': 0.99
        }
        sla_target = sla_targets.get(service_name, 0.99)
        
        if success_rate >= sla_target:
            budget_remaining = 1.0
            budget_status = 'healthy'
        elif success_rate >= sla_target * 0.9:
            budget_remaining = 0.5
            budget_status = 'critical'
        else:
            budget_remaining = 0.1
            budget_status = 'exhausted'
        
        budgets[service_name] = {
            "service": service_name,
            "success_rate": success_rate,
            "error_budget_remaining": budget_remaining,
            "total_requests": 1000,
            "successful_requests": int(1000 * success_rate),
            "failed_requests": int(1000 * error_rate),
            "sla_target": sla_target,
            "budget_status": budget_status
        }
    
    return budgets

@dashboard_app.get("/api/metrics")
async def get_metrics():
    """Get mock Prometheus metrics"""
    return "# Mock metrics\nhttp_requests_total{service=\"user-service\"} 1000\n"

# Service endpoints for error rate configuration
def create_service_endpoints(app, service_name):
    @app.get("/health")
    async def health():
        return {"status": "healthy", "service": service_name}
    
    @app.get("/api/data")
    async def get_data():
        return {"status": "success", "service": service_name, "data": f"processed-{random.randint(1000, 9999)}"}
    
    @app.post("/api/process")
    async def process_data():
        return {"status": "success", "service": service_name, "data": f"processed-{random.randint(1000, 9999)}"}
    
    @app.post("/config/error-rate/{rate}")
    async def set_error_rate(rate: float):
        if 0 <= rate <= 1:
            service_error_rates[service_name] = rate
            logger.info(f"Error rate set to {rate*100}% for {service_name}")
            return {"message": f"Error rate set to {rate*100}%"}
        raise HTTPException(400, "Error rate must be between 0 and 1")

# Create endpoints for each service
create_service_endpoints(user_service_app, 'user-service')
create_service_endpoints(payment_service_app, 'payment-service')
create_service_endpoints(order_service_app, 'order-service')

async def run_services():
    """Run all services concurrently"""
    logger.info("Starting Error Budget Demo Services...")
    
    # Start all servers concurrently
    await asyncio.gather(
        uvicorn.Server(uvicorn.Config(dashboard_app, host="0.0.0.0", port=3000, log_level="info")).serve(),
        uvicorn.Server(uvicorn.Config(user_service_app, host="0.0.0.0", port=8001, log_level="info")).serve(),
        uvicorn.Server(uvicorn.Config(payment_service_app, host="0.0.0.0", port=8002, log_level="info")).serve(),
        uvicorn.Server(uvicorn.Config(order_service_app, host="0.0.0.0", port=8003, log_level="info")).serve()
    )

if __name__ == "__main__":
    asyncio.run(run_services())
