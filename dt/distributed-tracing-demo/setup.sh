# (Insert the following block after the EOF for the test script, e.g. after the line "EOF" for tests/test_distributed_tracing.py)

# --- Update common tracing.py (add functools.wraps) ---
cat > services/common/tracing.py << 'EOF_TRACING'
"""Common tracing utilities for all services."""

import os
import logging
import functools
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
from fastapi import FastAPI

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

def setup_tracing(service_name: str, app: FastAPI = None):
    """Initialize OpenTelemetry tracing for a service."""
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_VERSION: "1.0.0",
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: "demo"
    })
    trace.set_tracer_provider(TracerProvider(resource=resource))
    tracer = trace.get_tracer(__name__)
    jaeger_exporter = JaegerExporter(agent_host_name="jaeger", agent_port=6831)
    span_processor = BatchSpanProcessor(jaeger_exporter)
    trace.get_tracer_provider().add_span_processor(span_processor)
    if app is not None:
        FastAPIInstrumentor().instrument_app(app)
    HTTPXClientInstrumentor().instrument()
    RedisInstrumentor().instrument()
    logger.info("Tracing initialized", service=service_name)
    return tracer

def get_trace_context():
    """Get current trace context for logging."""
    span = trace.get_current_span()
    if span.get_span_context().is_valid:
        return { "trace_id": format(span.get_span_context().trace_id, "032x"), "span_id": format(span.get_span_context().span_id, "016x") }
    return {}

def trace_request(func_name: str):
    """Decorator to add tracing to functions."""
    def decorator(func):
        @functools.wraps(func)
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
                    logger.error("Function failed", function=func_name, error=str(e), **get_trace_context())
                    raise
        return wrapper
    return decorator
EOF_TRACING

# --- Update requirements.txt (use opentelemetry-instrumentation-* at 0.42b0) ---
cat > requirements.txt << 'EOF_REQS'
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
redis==5.0.1
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-instrumentation==0.42b0
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
EOF_REQS

# --- Summary of fixes ---
# 1. In common/tracing.py:
#    - Added import functools.
#    - Updated trace_request decorator to use @functools.wraps(func) so that FastAPI endpoints (decorated with @trace_request) preserve their signature.
# 2. In requirements.txt:
#    - Updated all opentelemetry-instrumentation-* packages (fastapi, httpx, redis) to version 0.42b0 (to match opentelemetry-sdk and semantic conventions) so that dependency conflicts are resolved.
# --- End of fixes --- 