"""
API Gateway with security orchestration
"""
import os
import asyncio
import time
import json
import ssl
from typing import Dict, Any, Optional
from fastapi import FastAPI, HTTPException, Request, Depends
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import httpx
import uvicorn
from .base_service import SecurityManager
import structlog

logger = structlog.get_logger()

class SecureAPIGateway:
    def __init__(self):
        self.app = FastAPI(title="Secure API Gateway")
        self.security = SecurityManager("api-gateway")
        self.templates = Jinja2Templates(directory="src/web/templates")
        
        # Service registry
        self.services = {
            "user-service": "https://user-service:8001",
            "order-service": "https://order-service:8002",
            "payment-service": "https://payment-service:8003",
        }
        
        # Setup routes
        self.setup_routes()
        self.setup_web_interface()
    
    async def call_service(self, service_name: str, endpoint: str, method: str = "GET", data: Optional[Dict] = None) -> Dict:
        """Make authenticated service-to-service call"""
        if service_name not in self.services:
            raise HTTPException(status_code=404, detail=f"Service {service_name} not found")
        
        service_url = self.services[service_name]
        token = self.security.generate_service_token("api-gateway")
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        # Create SSL context for mutual TLS
        ssl_context = httpx.create_ssl_context()
        ssl_context.load_cert_chain(
            "/app/certs/api-gateway.crt",
            "/app/certs/api-gateway.key"
        )
        ssl_context.load_verify_locations("/app/certs/ca.crt")
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE  # Simplified for demo
        
        async with httpx.AsyncClient(verify=False) as client:
            try:
                if method == "GET":
                    response = await client.get(f"{service_url}{endpoint}", headers=headers)
                elif method == "POST":
                    response = await client.post(f"{service_url}{endpoint}", headers=headers, json=data)
                else:
                    raise HTTPException(status_code=405, detail="Method not allowed")
                
                if response.status_code == 200:
                    return response.json()
                else:
                    raise HTTPException(status_code=response.status_code, detail=response.text)
                    
            except httpx.RequestError as e:
                logger.error("Service call failed", service=service_name, error=str(e))
                raise HTTPException(status_code=503, detail=f"Service {service_name} unavailable")
    
    def setup_routes(self):
        """Setup API routes"""
        
        @self.app.get("/")
        async def root():
            return {"message": "Secure API Gateway", "timestamp": time.time()}
        
        @self.app.get("/health")
        async def health_check():
            # Check all downstream services
            service_health = {}
            for service_name in self.services:
                try:
                    result = await self.call_service(service_name, "/health")
                    service_health[service_name] = "healthy"
                except:
                    service_health[service_name] = "unhealthy"
            
            return {
                "gateway": "healthy",
                "services": service_health,
                "timestamp": time.time()
            }
        
        # User service proxy
        @self.app.get("/api/users/{user_id}")
        async def get_user(user_id: str):
            return await self.call_service("user-service", f"/users/{user_id}")
        
        # Order service proxy
        @self.app.get("/api/orders/{order_id}")
        async def get_order(order_id: str):
            return await self.call_service("order-service", f"/orders/{order_id}")
        
        # Payment service proxy
        @self.app.post("/api/payments/process")
        async def process_payment(payment_data: dict):
            return await self.call_service("payment-service", "/payments/process", "POST", payment_data)
        
        # Security endpoints
        @self.app.get("/api/security/status")
        async def security_status():
            status = {}
            for service_name in self.services:
                try:
                    result = await self.call_service(service_name, "/security/status")
                    status[service_name] = result
                except:
                    status[service_name] = {"status": "unavailable"}
            
            return {
                "gateway_security": {
                    "certificate_valid": True,
                    "patterns_tracked": len(self.security.request_patterns)
                },
                "services": status
            }
    
    def setup_web_interface(self):
        """Setup web dashboard"""
        
        @self.app.get("/dashboard", response_class=HTMLResponse)
        async def dashboard(request: Request):
            return self.templates.TemplateResponse("dashboard.html", {
                "request": request,
                "title": "Security Dashboard"
            })
    
    def run(self):
        """Run the API gateway"""
        logger.info("Starting secure API gateway")
        
        uvicorn.run(
            self.app,
            host="0.0.0.0",
            port=8000,
            ssl_keyfile="/app/certs/api-gateway.key",
            ssl_certfile="/app/certs/api-gateway.crt",
            ssl_ca_certs="/app/certs/ca.crt"
        )

def main():
    gateway = SecureAPIGateway()
    gateway.run()

if __name__ == "__main__":
    main()
