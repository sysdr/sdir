import asyncio
import random
import time
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import structlog
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
import httpx
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

app = FastAPI(title="Order Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

FastAPIInstrumentor.instrument_app(app)
RequestsInstrumentor().instrument()

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
ORDER_COUNT = Counter('orders_total', 'Total orders processed', ['status'])

class OrderRequest(BaseModel):
    user_id: int
    items: list
    total_amount: float

class OrderItem(BaseModel):
    product_id: str
    quantity: int
    price: float

# Mock order storage
ORDERS = {}

@app.middleware("http")
async def add_process_time_header(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    
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
    return {"service": "order-service", "status": "healthy", "timestamp": time.time()}

@app.post("/orders")
async def create_order(order: OrderRequest):
    with tracer.start_as_current_span("create_order") as span:
        span.set_attribute("order.user_id", order.user_id)
        span.set_attribute("order.amount", order.total_amount)
        span.set_attribute("order.items_count", len(order.items))
        
        order_id = f"order_{int(time.time())}_{random.randint(1000, 9999)}"
        
        logger.info("Creating order", user_id=order.user_id, order_id=order_id, amount=order.total_amount)
        
        try:
            # Step 1: Validate user
            with tracer.start_as_current_span("validate_user") as user_span:
                user_span.set_attribute("user.id", order.user_id)
                
                async with httpx.AsyncClient() as client:
                    user_response = await client.get(f"http://user-service:8000/users/{order.user_id}")
                    
                if user_response.status_code != 200:
                    logger.error("User validation failed", user_id=order.user_id, order_id=order_id)
                    ORDER_COUNT.labels(status="user_validation_failed").inc()
                    span.set_attribute("error", True)
                    raise HTTPException(status_code=400, detail="Invalid user")
                
                user_data = user_response.json()
                logger.info("User validated", user_id=order.user_id, user_name=user_data["name"])
            
            # Step 2: Process payment
            with tracer.start_as_current_span("process_payment") as payment_span:
                payment_span.set_attribute("payment.amount", order.total_amount)
                
                payment_data = {
                    "user_id": order.user_id,
                    "amount": order.total_amount,
                    "currency": "USD",
                    "payment_method": "credit_card"
                }
                
                async with httpx.AsyncClient() as client:
                    payment_response = await client.post("http://payment-service:8000/payments", json=payment_data)
                
                if payment_response.status_code != 200:
                    logger.error("Payment failed", user_id=order.user_id, order_id=order_id, amount=order.total_amount)
                    ORDER_COUNT.labels(status="payment_failed").inc()
                    span.set_attribute("error", True)
                    raise HTTPException(status_code=400, detail="Payment failed")
                
                payment_result = payment_response.json()
                logger.info("Payment processed", user_id=order.user_id, payment_id=payment_result["payment_id"])
            
            # Step 3: Create order record
            with tracer.start_as_current_span("save_order") as save_span:
                save_span.set_attribute("order.id", order_id)
                
                # Simulate database save time
                await asyncio.sleep(random.uniform(0.02, 0.08))
                
                order_record = {
                    "order_id": order_id,
                    "user_id": order.user_id,
                    "items": order.items,
                    "total_amount": order.total_amount,
                    "payment_id": payment_result["payment_id"],
                    "status": "confirmed",
                    "created_at": time.time()
                }
                
                ORDERS[order_id] = order_record
                ORDER_COUNT.labels(status="success").inc()
                
                logger.info("Order created successfully", user_id=order.user_id, order_id=order_id)
                
                return order_record
        
        except Exception as e:
            ORDER_COUNT.labels(status="error").inc()
            logger.error("Order creation failed", user_id=order.user_id, order_id=order_id, error=str(e))
            span.set_attribute("error", True)
            raise

@app.get("/orders/{order_id}")
async def get_order(order_id: str):
    with tracer.start_as_current_span("get_order") as span:
        span.set_attribute("order.id", order_id)
        
        if order_id not in ORDERS:
            logger.warning("Order not found", order_id=order_id)
            span.set_attribute("error", True)
            raise HTTPException(status_code=404, detail="Order not found")
        
        return ORDERS[order_id]

@app.get("/orders")
async def list_orders():
    with tracer.start_as_current_span("list_orders") as span:
        span.set_attribute("orders.count", len(ORDERS))
        
        return {"orders": list(ORDERS.values())}

@app.get("/metrics")
async def get_metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
