"""
Base service implementation with security features
"""
import os
import ssl
import logging
import asyncio
import time
import json
from typing import Dict, Any, Optional
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
import httpx
import uvicorn
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import jwt
from prometheus_client import Counter, Histogram, generate_latest
import structlog

# Configure structured logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

# Security metrics
REQUESTS_TOTAL = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
SECURITY_EVENTS = Counter('security_events_total', 'Security events', ['event_type', 'severity'])

class SecurityManager:
    def __init__(self, service_name: str):
        self.service_name = service_name
        self.cert_path = f"/app/certs/{service_name}.crt"
        self.key_path = f"/app/certs/{service_name}.key"
        self.ca_cert_path = "/app/certs/ca.crt"
        self.jwt_secret = "your-secret-key-change-in-production"
        
        # Load certificates
        self._load_certificates()
        
        # Initialize behavioral analysis
        self.request_patterns = {}
        self.baseline_established = False
        
    def _load_certificates(self):
        """Load TLS certificates for mutual authentication"""
        try:
            with open(self.cert_path, 'rb') as f:
                self.cert = x509.load_pem_x509_certificate(f.read(), default_backend())
            
            with open(self.ca_cert_path, 'rb') as f:
                self.ca_cert = x509.load_pem_x509_certificate(f.read(), default_backend())
                
            logger.info("Certificates loaded successfully", service=self.service_name)
        except Exception as e:
            logger.error("Failed to load certificates", error=str(e))
            raise
    
    def verify_service_certificate(self, client_cert: str) -> bool:
        """Verify client certificate against CA"""
        try:
            cert = x509.load_pem_x509_certificate(client_cert.encode(), default_backend())
            # Verify certificate chain (simplified)
            return cert.issuer == self.ca_cert.subject
        except Exception as e:
            logger.warning("Certificate verification failed", error=str(e))
            return False
    
    def generate_service_token(self, service_name: str) -> str:
        """Generate JWT token for service-to-service communication"""
        payload = {
            "service": service_name,
            "iat": time.time(),
            "exp": time.time() + 3600  # 1 hour expiration
        }
        return jwt.encode(payload, self.jwt_secret, algorithm="HS256")
    
    def verify_service_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify JWT token from other services"""
        try:
            payload = jwt.decode(token, self.jwt_secret, algorithms=["HS256"])
            return payload
        except jwt.ExpiredSignatureError:
            SECURITY_EVENTS.labels(event_type="token_expired", severity="medium").inc()
            return None
        except jwt.InvalidTokenError:
            SECURITY_EVENTS.labels(event_type="invalid_token", severity="high").inc()
            return None
    
    def analyze_request_pattern(self, request: Request) -> Dict[str, Any]:
        """Analyze request for anomalous behavior"""
        client_ip = request.client.host
        endpoint = request.url.path
        method = request.method
        timestamp = time.time()
        
        # Track request patterns
        pattern_key = f"{client_ip}:{endpoint}"
        if pattern_key not in self.request_patterns:
            self.request_patterns[pattern_key] = []
        
        self.request_patterns[pattern_key].append({
            "timestamp": timestamp,
            "method": method,
            "user_agent": request.headers.get("user-agent", ""),
        })
        
        # Keep only recent requests (last hour)
        hour_ago = timestamp - 3600
        self.request_patterns[pattern_key] = [
            req for req in self.request_patterns[pattern_key] 
            if req["timestamp"] > hour_ago
        ]
        
        # Analyze for anomalies
        recent_requests = len(self.request_patterns[pattern_key])
        
        # Simple rate limiting detection
        if recent_requests > 100:  # More than 100 requests per hour
            SECURITY_EVENTS.labels(event_type="rate_limit_exceeded", severity="medium").inc()
            return {"anomaly": "high_request_rate", "severity": "medium"}
        
        # Check for scanning behavior
        unique_endpoints = len(set(req.get("endpoint", endpoint) for req in self.request_patterns[pattern_key]))
        if unique_endpoints > 20:  # Accessing many different endpoints
            SECURITY_EVENTS.labels(event_type="potential_scanning", severity="high").inc()
            return {"anomaly": "scanning_behavior", "severity": "high"}
        
        return {"anomaly": "none", "severity": "low"}

class SecureService:
    def __init__(self, service_name: str, port: int):
        self.service_name = service_name
        self.port = port
        self.app = FastAPI(title=f"Secure {service_name}")
        self.security = SecurityManager(service_name)
        self.security_bearer = HTTPBearer()
        
        # Add CORS middleware
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        # Add middleware for security monitoring
        self.app.middleware("http")(self.security_middleware)
        
        # Add routes
        self.setup_routes()
    
    async def security_middleware(self, request: Request, call_next):
        """Security middleware for request analysis"""
        start_time = time.time()
        
        # Analyze request pattern
        analysis = self.security.analyze_request_pattern(request)
        
        # Log security events
        if analysis["anomaly"] != "none":
            logger.warning(
                "Security anomaly detected",
                service=self.service_name,
                client_ip=request.client.host,
                anomaly=analysis["anomaly"],
                severity=analysis["severity"]
            )
        
        response = await call_next(request)
        
        # Record metrics
        duration = time.time() - start_time
        REQUEST_DURATION.observe(duration)
        REQUESTS_TOTAL.labels(
            method=request.method,
            endpoint=request.url.path,
            status=response.status_code
        ).inc()
        
        return response
    
    def verify_token(self, credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())):
        """Dependency for token verification"""
        token = credentials.credentials
        payload = self.security.verify_service_token(token)
        if not payload:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        return payload
    
    def setup_routes(self):
        """Setup service routes"""
        
        @self.app.get("/health")
        async def health_check():
            return {
                "status": "healthy",
                "service": self.service_name,
                "timestamp": time.time()
            }
        
        @self.app.get("/metrics")
        async def metrics():
            return generate_latest()
        
        @self.app.get("/security/status")
        async def security_status(token_data: dict = Depends(self.verify_token)):
            return {
                "service": self.service_name,
                "security_enabled": True,
                "certificate_valid": True,
                "patterns_tracked": len(self.security.request_patterns),
                "caller": token_data.get("service")
            }
        
        # Service-specific endpoints
        if self.service_name == "user-service":
            
            @self.app.get("/users/{user_id}")
            async def get_user(user_id: str, token_data: dict = Depends(self.verify_token)):
                return {
                    "user_id": user_id,
                    "name": f"User {user_id}",
                    "email": f"user{user_id}@example.com",
                    "service": self.service_name,
                    "caller": token_data.get("service")
                }
        
        elif self.service_name == "order-service":
            
            @self.app.get("/orders/{order_id}")
            async def get_order(order_id: str, token_data: dict = Depends(self.verify_token)):
                return {
                    "order_id": order_id,
                    "status": "processing",
                    "amount": 99.99,
                    "service": self.service_name,
                    "caller": token_data.get("service")
                }
        
        elif self.service_name == "payment-service":
            
            @self.app.post("/payments/process")
            async def process_payment(payment_data: dict, token_data: dict = Depends(self.verify_token)):
                return {
                    "payment_id": f"pay_{int(time.time())}",
                    "status": "completed",
                    "amount": payment_data.get("amount", 0),
                    "service": self.service_name,
                    "caller": token_data.get("service")
                }
    
    def run(self):
        """Run the service"""
        # Create SSL context for mutual TLS
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.load_cert_chain(
            f"/app/certs/{self.service_name}.crt",
            f"/app/certs/{self.service_name}.key"
        )
        ssl_context.load_verify_locations("/app/certs/ca.crt")
        ssl_context.verify_mode = ssl.CERT_OPTIONAL
        
        logger.info("Starting secure service", service=self.service_name, port=self.port)
        
        uvicorn.run(
            self.app,
            host="0.0.0.0",
            port=self.port,
            ssl_keyfile=f"/app/certs/{self.service_name}.key",
            ssl_certfile=f"/app/certs/{self.service_name}.crt",
            ssl_ca_certs="/app/certs/ca.crt"
        )

def main():
    service_name = os.getenv("SERVICE_NAME", "unknown-service")
    service_port = int(os.getenv("SERVICE_PORT", 8001))
    
    service = SecureService(service_name, service_port)
    service.run()

if __name__ == "__main__":
    main()
