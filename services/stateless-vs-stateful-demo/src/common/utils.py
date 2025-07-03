"""
Common utilities and helper functions
"""
import jwt
import json
import time
import psutil
import structlog
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="ISO"),
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

# JWT secret for stateless authentication
JWT_SECRET = "your-super-secret-jwt-key-for-demo-only"

def create_jwt_token(user_data: Dict[str, Any], expires_in_hours: int = 24) -> str:
    """Create a JWT token for stateless authentication"""
    payload = {
        **user_data,
        'exp': datetime.utcnow() + timedelta(hours=expires_in_hours),
        'iat': datetime.utcnow()
    }
    return jwt.encode(payload, JWT_SECRET, algorithm='HS256')

def verify_jwt_token(token: str) -> Optional[Dict[str, Any]]:
    """Verify and decode a JWT token"""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
        return payload
    except jwt.ExpiredSignatureError:
        logger.warning("JWT token expired")
        return None
    except jwt.InvalidTokenError:
        logger.warning("Invalid JWT token")
        return None

def get_system_metrics() -> Dict[str, float]:
    """Get current system metrics"""
    return {
        'cpu_percent': psutil.cpu_percent(interval=0.1),
        'memory_percent': psutil.virtual_memory().percent,
        'memory_used_gb': psutil.virtual_memory().used / (1024**3),
        'disk_usage_percent': psutil.disk_usage('/').percent
    }

def generate_user_id() -> str:
    """Generate a unique user ID"""
    return f"user_{int(time.time() * 1000)}"

def simulate_processing_delay(delay_ms: int = 10):
    """Simulate processing delay for realistic behavior"""
    time.sleep(delay_ms / 1000.0)
