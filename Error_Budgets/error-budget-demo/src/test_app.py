#!/usr/bin/env python3

import asyncio
import logging
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
import uvicorn
import redis

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create simple dashboard app
app = FastAPI(title="Error Budget Dashboard")
app.mount("/static", StaticFiles(directory="web"), name="static")
templates = Jinja2Templates(directory="web")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/error-budgets")
async def get_error_budgets():
    """Get mock error budget status for all services"""
    return {
        "user-service": {
            "service": "user-service",
            "success_rate": 0.995,
            "error_budget_remaining": 0.8,
            "total_requests": 1000,
            "successful_requests": 995,
            "failed_requests": 5,
            "sla_target": 0.999,
            "budget_status": "healthy"
        },
        "payment-service": {
            "service": "payment-service",
            "success_rate": 0.99,
            "error_budget_remaining": 0.6,
            "total_requests": 500,
            "successful_requests": 495,
            "failed_requests": 5,
            "sla_target": 0.995,
            "budget_status": "healthy"
        },
        "order-service": {
            "service": "order-service",
            "success_rate": 0.98,
            "error_budget_remaining": 0.2,
            "total_requests": 200,
            "successful_requests": 196,
            "failed_requests": 4,
            "sla_target": 0.99,
            "budget_status": "critical"
        }
    }

@app.get("/api/metrics")
async def get_metrics():
    """Get mock Prometheus metrics"""
    return "# Mock metrics\nhttp_requests_total{service=\"user-service\"} 1000\n"

if __name__ == "__main__":
    logger.info("Starting Error Budget Dashboard...")
    config = uvicorn.Config(app, host="0.0.0.0", port=3000, log_level="info")
    server = uvicorn.Server(config)
    asyncio.run(server.serve())
