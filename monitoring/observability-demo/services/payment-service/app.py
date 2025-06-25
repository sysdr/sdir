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

app = FastAPI(title="Payment Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

FastAPIInstrumentor.instrument_app(app)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
PAYMENT_COUNT = Counter('payments_total', 'Total payments processed', ['status'])
PAYMENT_AMOUNT = Histogram('payment_amount_dollars', 'Payment amounts in dollars')

class PaymentRequest(BaseModel):
    user_id: int
    amount: float
    currency: str = "USD"
    payment_method: str = "credit_card"

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
    return {"service": "payment-service", "status": "healthy", "timestamp": time.time()}

@app.post("/payments")
async def process_payment(payment: PaymentRequest):
    with tracer.start_as_current_span("process_payment") as span:
        span.set_attribute("payment.user_id", payment.user_id)
        span.set_attribute("payment.amount", payment.amount)
        span.set_attribute("payment.method", payment.payment_method)
        
        logger.info("Processing payment", user_id=payment.user_id, amount=payment.amount)
        
        # Simulate payment processing time
        await asyncio.sleep(random.uniform(0.1, 0.5))
        
        # Simulate payment failures
        if random.random() < 0.15:  # 15% failure rate
            PAYMENT_COUNT.labels(status="failed").inc()
            logger.error("Payment failed", user_id=payment.user_id, amount=payment.amount, reason="insufficient_funds")
            span.set_attribute("error", True)
            raise HTTPException(status_code=400, detail="Payment failed: insufficient funds")
        
        # Simulate network errors
        if random.random() < 0.05:  # 5% network error rate
            PAYMENT_COUNT.labels(status="error").inc()
            logger.error("Payment gateway error", user_id=payment.user_id, amount=payment.amount)
            span.set_attribute("error", True)
            raise HTTPException(status_code=500, detail="Payment gateway error")
        
        # Successful payment
        payment_id = f"pay_{int(time.time())}_{random.randint(1000, 9999)}"
        PAYMENT_COUNT.labels(status="success").inc()
        PAYMENT_AMOUNT.observe(payment.amount)
        
        logger.info("Payment successful", user_id=payment.user_id, amount=payment.amount, payment_id=payment_id)
        
        return {
            "payment_id": payment_id,
            "status": "success",
            "amount": payment.amount,
            "currency": payment.currency,
            "timestamp": time.time()
        }

@app.get("/metrics")
async def get_metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
