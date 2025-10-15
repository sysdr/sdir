import asyncio
import time
import json
import random
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
import uvicorn
import redis
from prometheus_client import Counter, Histogram, generate_latest
import logging
from typing import Dict, List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Metrics
request_counter = Counter('http_requests_total', 'Total HTTP requests', ['service', 'endpoint', 'status'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration', ['service', 'endpoint'])

class ErrorBudgetCalculator:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.services = ['user-service', 'payment-service', 'order-service']
        self.sla_targets = {
            'user-service': 0.999,    # 99.9%
            'payment-service': 0.995, # 99.5%
            'order-service': 0.99     # 99.0%
        }
    
    def calculate_error_budget(self, service: str, window_hours: int = 24) -> Dict:
        """Calculate error budget for a service"""
        if not self.redis:
            # Return mock data when Redis is not available
            return {
                'service': service,
                'success_rate': 0.995,
                'error_budget_remaining': 0.8,
                'total_requests': 1000,
                'successful_requests': 995,
                'failed_requests': 5,
                'sla_target': self.sla_targets.get(service, 0.99),
                'budget_status': 'healthy'
            }
        
        success_key = f"{service}:success:{window_hours}h"
        total_key = f"{service}:total:{window_hours}h"
        
        success_count = int(self.redis.get(success_key) or 0)
        total_count = int(self.redis.get(total_key) or 0)
        
        if total_count == 0:
            return {
                'service': service,
                'success_rate': 1.0,
                'error_budget_remaining': 1.0,
                'total_requests': 0,
                'sla_target': self.sla_targets.get(service, 0.99)
            }
        
        success_rate = success_count / total_count
        sla_target = self.sla_targets.get(service, 0.99)
        
        # Error budget remaining as percentage
        if success_rate >= sla_target:
            budget_remaining = 1.0
        else:
            budget_consumed = (sla_target - success_rate) / (1 - sla_target)
            budget_remaining = max(0, 1 - budget_consumed)
        
        return {
            'service': service,
            'success_rate': success_rate,
            'error_budget_remaining': budget_remaining,
            'total_requests': total_count,
            'successful_requests': success_count,
            'failed_requests': total_count - success_count,
            'sla_target': sla_target,
            'budget_status': 'healthy' if budget_remaining > 0.1 else 'critical' if budget_remaining > 0 else 'exhausted'
        }

class ServiceSimulator:
    def __init__(self, service_name: str, redis_client):
        self.service_name = service_name
        self.redis = redis_client
        self.error_rate = 0.01  # Start with 1% error rate
        self.app = FastAPI(title=f"{service_name}")
        self.setup_routes()
        
    def setup_routes(self):
        @self.app.get("/health")
        async def health():
            return {"status": "healthy", "service": self.service_name}
        
        @self.app.get("/api/data")
        async def get_data():
            return await self.simulate_request()
            
        @self.app.post("/api/process")
        async def process_data():
            return await self.simulate_request()
            
        @self.app.post("/config/error-rate/{rate}")
        async def set_error_rate(rate: float):
            if 0 <= rate <= 1:
                self.error_rate = rate
                return {"message": f"Error rate set to {rate*100}%"}
            raise HTTPException(400, "Error rate must be between 0 and 1")
    
    async def simulate_request(self):
        """Simulate a service request with configurable error rate"""
        start_time = time.time()
        
        # Increment total requests
        total_key = f"{self.service_name}:total:24h"
        success_key = f"{self.service_name}:success:24h"
        
        # Simulate processing time
        await asyncio.sleep(random.uniform(0.01, 0.1))
        
        # Determine if request should fail
        is_success = random.random() > self.error_rate
        
        # Update metrics
        if self.redis:
            with self.redis.pipeline() as pipe:
                pipe.incr(total_key)
                pipe.expire(total_key, 86400)  # 24 hour expiry
                
                if is_success:
                    pipe.incr(success_key)
                    pipe.expire(success_key, 86400)
                    status_code = "200"
                else:
                    status_code = "500"
                
                pipe.execute()
        else:
            # Mock Redis - just set status code
            status_code = "200" if is_success else "500"
        
        # Record metrics
        request_counter.labels(
            service=self.service_name, 
            endpoint="api", 
            status=status_code
        ).inc()
        
        request_duration.labels(
            service=self.service_name, 
            endpoint="api"
        ).observe(time.time() - start_time)
        
        if is_success:
            return {
                "status": "success",
                "service": self.service_name,
                "data": f"processed-{random.randint(1000, 9999)}",
                "timestamp": datetime.now().isoformat()
            }
        else:
            raise HTTPException(500, "Service temporarily unavailable")

# Main dashboard application
dashboard_app = FastAPI(title="Error Budget Dashboard")
dashboard_app.mount("/static", StaticFiles(directory="web"), name="static")
templates = Jinja2Templates(directory="web")

@dashboard_app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@dashboard_app.get("/api/error-budgets")
async def get_error_budgets():
    """Get current error budget status for all services"""
    try:
        redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
        redis_client.ping()  # Test connection
    except:
        try:
            # Fallback to localhost for development
            redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
            redis_client.ping()
        except:
            # Use None if Redis is not available
            redis_client = None
    calculator = ErrorBudgetCalculator(redis_client)
    
    budgets = {}
    for service in calculator.services:
        budgets[service] = calculator.calculate_error_budget(service)
    
    return budgets

@dashboard_app.get("/api/metrics")
async def get_metrics():
    """Get Prometheus metrics"""
    return generate_latest()

async def run_services():
    """Run all services concurrently"""
    try:
        redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
        redis_client.ping()  # Test connection
        logger.info("Connected to Redis at redis:6379")
    except Exception as e:
        logger.warning(f"Failed to connect to Redis at redis:6379: {e}")
        try:
            # Fallback to localhost for development
            redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
            redis_client.ping()
            logger.info("Connected to Redis at localhost:6379")
        except Exception as e2:
            logger.error(f"Failed to connect to Redis at localhost:6379: {e2}")
            logger.info("Starting without Redis - using mock data")
            redis_client = None
    
    # Create service simulators
    user_service = ServiceSimulator('user-service', redis_client)
    payment_service = ServiceSimulator('payment-service', redis_client)
    order_service = ServiceSimulator('order-service', redis_client)
    
    # Start background traffic generation
    async def generate_traffic():
        """Generate realistic traffic patterns"""
        while True:
            try:
                # Simulate different load patterns
                for service in [user_service, payment_service, order_service]:
                    for _ in range(random.randint(5, 20)):
                        asyncio.create_task(service.simulate_request())
                
                await asyncio.sleep(1)  # Generate traffic every second
                
            except Exception as e:
                logger.error(f"Traffic generation error: {e}")
                await asyncio.sleep(5)
    
    # Start traffic generation
    asyncio.create_task(generate_traffic())
    
    # Start individual service servers
    user_config = uvicorn.Config(user_service.app, host="0.0.0.0", port=8001, log_level="info")
    payment_config = uvicorn.Config(payment_service.app, host="0.0.0.0", port=8002, log_level="info")
    order_config = uvicorn.Config(order_service.app, host="0.0.0.0", port=8003, log_level="info")
    dashboard_config = uvicorn.Config(dashboard_app, host="0.0.0.0", port=3000, log_level="info")
    
    # Start all servers concurrently
    await asyncio.gather(
        uvicorn.Server(user_config).serve(),
        uvicorn.Server(payment_config).serve(),
        uvicorn.Server(order_config).serve(),
        uvicorn.Server(dashboard_config).serve()
    )

if __name__ == "__main__":
    asyncio.run(run_services())
