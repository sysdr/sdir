import asyncio
import random
import time
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import structlog
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import os

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
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Initialize tracing
jaeger_exporter = JaegerExporter(
    agent_host_name=os.getenv("JAEGER_AGENT_HOST", "localhost"),
    agent_port=int(os.getenv("JAEGER_AGENT_PORT", "6831")),
)

trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

span_processor = BatchSpanProcessor(jaeger_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Create FastAPI app
app = FastAPI(title="User Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instrument FastAPI
FastAPIInstrumentor.instrument_app(app)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')

# Mock user database
USERS = {
    1: {"id": 1, "name": "John Doe", "email": "john@example.com", "balance": 1500.00},
    2: {"id": 2, "name": "Jane Smith", "email": "jane@example.com", "balance": 2000.00},
    3: {"id": 3, "name": "Bob Johnson", "email": "bob@example.com", "balance": 750.00},
}

@app.middleware("http")
async def add_process_time_header(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    
    # Update metrics
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    REQUEST_DURATION.observe(process_time)
    
    response.headers["X-Process-Time"] = str(process_time)
    return response

@app.get("/")
async def health_check():
    return {"service": "user-service", "status": "healthy", "timestamp": time.time()}

@app.get("/users/{user_id}")
async def get_user(user_id: int):
    with tracer.start_as_current_span("get_user") as span:
        span.set_attribute("user.id", user_id)
        
        # Simulate database lookup time
        await asyncio.sleep(random.uniform(0.01, 0.1))
        
        if user_id not in USERS:
            logger.warning("User not found", user_id=user_id)
            span.set_attribute("error", True)
            raise HTTPException(status_code=404, detail="User not found")
        
        user = USERS[user_id]
        logger.info("User retrieved", user_id=user_id, user_name=user["name"])
        
        # Simulate occasional errors
        if random.random() < 0.05:  # 5% error rate
            logger.error("Database connection error", user_id=user_id)
            span.set_attribute("error", True)
            raise HTTPException(status_code=500, detail="Database connection error")
        
        return user

@app.get("/users")
async def list_users():
    with tracer.start_as_current_span("list_users") as span:
        span.set_attribute("users.count", len(USERS))
        
        # Simulate database query time
        await asyncio.sleep(random.uniform(0.05, 0.2))
        
        logger.info("Users listed", count=len(USERS))
        return {"users": list(USERS.values())}

@app.get("/metrics")
async def get_metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
