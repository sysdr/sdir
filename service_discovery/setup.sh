
#!/bin/bash

# Service Discovery Patterns Demo
# Demonstrates client-side discovery, service registration, health checking, and failure scenarios
# Compatible with latest Docker and Python libraries

set -e

echo "🚀 Service Discovery Patterns Demo Setup"
echo "========================================"

# Create project structure
mkdir -p service-discovery-demo/{consul,services/{api-gateway,user-service,order-service},web-dashboard,docker}
cd service-discovery-demo

# Create Docker Compose configuration
cat > docker-compose.yml << 'EOF'
services:
  consul:
    image: hashicorp/consul:1.15
    container_name: consul-server
    ports:
      - "8500:8500"
      - "8600:8600/udp"
    environment:
      - CONSUL_BIND_INTERFACE=eth0
    volumes:
      - consul-data:/consul/data
    command: >
      consul agent -server -ui -node=server-1 -bootstrap-expect=1 
      -client=0.0.0.0 -log-level=INFO -data-dir=/consul/data
    networks:
      - discovery-net
    healthcheck:
      test: ["CMD", "consul", "members"]
      interval: 10s
      timeout: 3s
      retries: 3

  user-service-1:
    build: ./services/user-service
    container_name: user-service-1
    environment:
      - SERVICE_NAME=user-service
      - SERVICE_ID=user-service-1
      - SERVICE_PORT=8001
      - CONSUL_HOST=consul
      - FAILURE_RATE=0.0
    ports:
      - "8001:8001"
    depends_on:
      consul:
        condition: service_healthy
    networks:
      - discovery-net

  user-service-2:
    build: ./services/user-service
    container_name: user-service-2
    environment:
      - SERVICE_NAME=user-service
      - SERVICE_ID=user-service-2
      - SERVICE_PORT=8002
      - CONSUL_HOST=consul
      - FAILURE_RATE=0.1
    ports:
      - "8002:8002"
    depends_on:
      consul:
        condition: service_healthy
    networks:
      - discovery-net

  order-service-1:
    build: ./services/order-service
    container_name: order-service-1
    environment:
      - SERVICE_NAME=order-service
      - SERVICE_ID=order-service-1
      - SERVICE_PORT=8003
      - CONSUL_HOST=consul
      - FAILURE_RATE=0.0
    ports:
      - "8003:8003"
    depends_on:
      consul:
        condition: service_healthy
    networks:
      - discovery-net

  api-gateway:
    build: ./services/api-gateway
    container_name: api-gateway
    environment:
      - CONSUL_HOST=consul
      - GATEWAY_PORT=8000
    ports:
      - "8000:8000"
    depends_on:
      consul:
        condition: service_healthy
    networks:
      - discovery-net

  web-dashboard:
    build: ./web-dashboard
    container_name: web-dashboard
    environment:
      - CONSUL_HOST=consul
    ports:
      - "3000:3000"
    depends_on:
      consul:
        condition: service_healthy
    networks:
      - discovery-net

networks:
  discovery-net:
    driver: bridge

volumes:
  consul-data:
EOF
# Create User Service
mkdir -p services/user-service
cat > services/user-service/base_service.py << 'EOF'
import asyncio
import json
import logging
import os
import random
import signal
import sys
import time
from datetime import datetime
from typing import Dict, List, Optional

import aiohttp
import consul
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class ServiceDiscoveryClient:
    """Advanced service discovery client with circuit breaker and health checking"""
    
    def __init__(self, consul_host: str = "localhost", consul_port: int = 8500):
        self.consul_host = consul_host
        self.consul_port = consul_port
        self.consul_client = consul.Consul(host=consul_host, port=consul_port)
        self.service_cache = {}
        self.cache_ttl = 30  # seconds
        self.circuit_breaker = CircuitBreaker()
        
    async def register_service(self, service_id: str, service_name: str, 
                             address: str, port: int, health_check_url: str):
        """Register service with Consul including health check"""
        try:
            check = consul.Check.http(health_check_url, timeout="10s", interval="15s")
            
            result = self.consul_client.agent.service.register(
                name=service_name,
                service_id=service_id,
                address=address,
                port=port,
                check=check,
                tags=[f"version:1.0", f"environment:demo"]
            )
            
            logger.info(f"✅ Service {service_id} registered successfully")
            return result
            
        except Exception as e:
            logger.error(f"❌ Failed to register service {service_id}: {e}")
            raise
    
    async def deregister_service(self, service_id: str):
        """Deregister service from Consul"""
        try:
            self.consul_client.agent.service.deregister(service_id)
            logger.info(f"🔄 Service {service_id} deregistered")
        except Exception as e:
            logger.error(f"❌ Failed to deregister service {service_id}: {e}")
    
    async def discover_services(self, service_name: str) -> List[Dict]:
        """Discover healthy service instances with caching and circuit breaker"""
        cache_key = f"service:{service_name}"
        now = time.time()
        
        # Check cache first
        if cache_key in self.service_cache:
            cached_data, timestamp = self.service_cache[cache_key]
            if now - timestamp < self.cache_ttl:
                logger.debug(f"📋 Using cached data for {service_name}")
                return cached_data
        
        # Fetch from Consul with circuit breaker
        try:
            if self.circuit_breaker.can_execute():
                _, services = self.consul_client.health.service(service_name, passing=True)
                
                # Transform to simplified format
                service_instances = []
                for service in services:
                    instance = {
                        'id': service['Service']['ID'],
                        'address': service['Service']['Address'],
                        'port': service['Service']['Port'],
                        'status': 'healthy',
                        'tags': service['Service']['Tags']
                    }
                    service_instances.append(instance)
                
                # Update cache
                self.service_cache[cache_key] = (service_instances, now)
                self.circuit_breaker.record_success()
                
                logger.info(f"🔍 Discovered {len(service_instances)} instances of {service_name}")
                return service_instances
                
            else:
                logger.warning(f"⚡ Circuit breaker open for service discovery")
                # Return cached data if available
                if cache_key in self.service_cache:
                    cached_data, _ = self.service_cache[cache_key]
                    return cached_data
                return []
                
        except Exception as e:
            self.circuit_breaker.record_failure()
            logger.error(f"❌ Service discovery failed for {service_name}: {e}")
            
            # Return cached data as fallback
            if cache_key in self.service_cache:
                cached_data, _ = self.service_cache[cache_key]
                logger.info(f"📋 Using stale cache for {service_name}")
                return cached_data
            return []

class CircuitBreaker:
    """Simple circuit breaker implementation"""
    
    def __init__(self, failure_threshold: int = 5, recovery_timeout: int = 60):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = 'closed'  # closed, open, half-open
    
    def can_execute(self) -> bool:
        if self.state == 'closed':
            return True
        elif self.state == 'open':
            if time.time() - self.last_failure_time > self.recovery_timeout:
                self.state = 'half-open'
                return True
            return False
        else:  # half-open
            return True
    
    def record_success(self):
        self.failure_count = 0
        self.state = 'closed'
        
    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            self.state = 'open'
            logger.warning(f"⚡ Circuit breaker opened after {self.failure_count} failures")

class BaseService:
    """Base service class with discovery capabilities"""
    
    def __init__(self, service_name: str, service_id: str, port: int):
        self.service_name = service_name
        self.service_id = service_id
        self.port = port
        self.consul_host = os.getenv('CONSUL_HOST', 'localhost')
        self.failure_rate = float(os.getenv('FAILURE_RATE', '0.0'))
        
        # Initialize discovery client
        self.discovery_client = ServiceDiscoveryClient(self.consul_host)
        
        # Create FastAPI app
        self.app = FastAPI(
            title=f"{service_name} Service",
            lifespan=self.lifespan
        )
        
        # Add CORS middleware
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        # Setup routes
        self.setup_routes()
        
        # Setup graceful shutdown
        self.setup_signal_handlers()
    
    @asynccontextmanager
    async def lifespan(self, app: FastAPI):
        """Manage service lifecycle with discovery registration"""
        # Startup
        await self.register_with_discovery()
        logger.info(f"🚀 {self.service_name} service started on port {self.port}")
        
        yield
        
        # Shutdown
        await self.deregister_from_discovery()
        logger.info(f"🛑 {self.service_name} service stopped")
    
    async def register_with_discovery(self):
        """Register this service with the discovery system"""
        # Use container name for Docker networking
        container_name = os.getenv('HOSTNAME', self.service_id)
        health_check_url = f"http://{container_name}:{self.port}/health"
        await self.discovery_client.register_service(
            service_id=self.service_id,
            service_name=self.service_name,
            address=container_name,
            port=self.port,
            health_check_url=health_check_url
        )
    
    async def deregister_from_discovery(self):
        """Deregister from discovery system"""
        await self.discovery_client.deregister_service(self.service_id)
    
    def setup_routes(self):
        """Setup common routes"""
        
        @self.app.get("/health")
        async def health_check():
            """Health check endpoint with failure simulation"""
            if random.random() < self.failure_rate:
                logger.warning(f"💔 Simulated health check failure for {self.service_id}")
                raise HTTPException(status_code=503, detail="Service temporarily unavailable")
            
            return {
                "status": "healthy",
                "service": self.service_name,
                "instance": self.service_id,
                "timestamp": datetime.now().isoformat(),
                "uptime": time.time()
            }
        
        @self.app.get("/info")
        async def service_info():
            """Service information endpoint"""
            return {
                "service_name": self.service_name,
                "service_id": self.service_id,
                "port": self.port,
                "failure_rate": self.failure_rate,
                "consul_host": self.consul_host
            }
    
    def setup_signal_handlers(self):
        """Setup graceful shutdown signal handlers"""
        def signal_handler(signum, frame):
            logger.info(f"📢 Received signal {signum}, shutting down gracefully...")
            asyncio.create_task(self.shutdown())
        
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)
    
    async def shutdown(self):
        """Graceful shutdown process"""
        logger.info(f"🔄 Starting graceful shutdown for {self.service_id}")
        await self.deregister_from_discovery()
        sys.exit(0)
EOF

cat > services/user-service/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8001

CMD ["python", "main.py"]
EOF

cat > services/user-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
python-consul==1.1.0
aiohttp==3.9.0
EOF

cat > services/user-service/main.py << 'EOF'
import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import BaseService

import uvicorn
from fastapi import HTTPException

class UserService(BaseService):
    """User service with service discovery capabilities"""
    
    def __init__(self):
        service_name = os.getenv('SERVICE_NAME', 'user-service')
        service_id = os.getenv('SERVICE_ID', 'user-service-1')
        port = int(os.getenv('SERVICE_PORT', '8001'))
        
        super().__init__(service_name, service_id, port)
        
        # Mock user data
        self.users = {
            "1": {"id": "1", "name": "Alice Johnson", "email": "alice@example.com"},
            "2": {"id": "2", "name": "Bob Smith", "email": "bob@example.com"},
            "3": {"id": "3", "name": "Carol Davis", "email": "carol@example.com"}
        }
        
        self.setup_user_routes()
    
    def setup_user_routes(self):
        """Setup user-specific routes"""
        
        @self.app.get("/users")
        async def list_users():
            """List all users"""
            # Simulate some processing time
            await asyncio.sleep(random.uniform(0.1, 0.3))
            
            return {
                "users": list(self.users.values()),
                "served_by": self.service_id,
                "total": len(self.users)
            }
        
        @self.app.get("/users/{user_id}")
        async def get_user(user_id: str):
            """Get specific user"""
            # Simulate random failures
            if random.random() < self.failure_rate:
                raise HTTPException(status_code=500, detail="Internal server error")
            
            if user_id not in self.users:
                raise HTTPException(status_code=404, detail="User not found")
            
            await asyncio.sleep(random.uniform(0.05, 0.15))
            
            return {
                "user": self.users[user_id],
                "served_by": self.service_id
            }

if __name__ == "__main__":
    service = UserService()
    uvicorn.run(
        service.app,
        host="0.0.0.0",
        port=service.port,
        access_log=False
    )
EOF

# Create Order Service - copy base_service.py
mkdir -p services/order-service
cp services/user-service/base_service.py services/order-service/

cat > services/order-service/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8003

CMD ["python", "main.py"]
EOF

cat > services/order-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
python-consul==1.1.0
aiohttp==3.9.0
EOF

cat > services/order-service/main.py << 'EOF'
import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import BaseService

import uvicorn
from fastapi import HTTPException

class OrderService(BaseService):
    """Order service with user service discovery"""
    
    def __init__(self):
        service_name = os.getenv('SERVICE_NAME', 'order-service')
        service_id = os.getenv('SERVICE_ID', 'order-service-1')
        port = int(os.getenv('SERVICE_PORT', '8003'))
        
        super().__init__(service_name, service_id, port)
        
        # Mock orders data
        self.orders = {
            "1": {"id": "1", "user_id": "1", "items": ["laptop", "mouse"], "total": 1299.99},
            "2": {"id": "2", "user_id": "2", "items": ["phone"], "total": 599.99},
            "3": {"id": "3", "user_id": "1", "items": ["keyboard"], "total": 99.99}
        }
        
        self.setup_order_routes()
    
    def setup_order_routes(self):
        """Setup order-specific routes"""
        
        @self.app.get("/orders")
        async def list_orders():
            """List all orders"""
            await asyncio.sleep(random.uniform(0.1, 0.2))
            
            return {
                "orders": list(self.orders.values()),
                "served_by": self.service_id,
                "total": len(self.orders)
            }
        
        @self.app.get("/orders/{order_id}")
        async def get_order(order_id: str):
            """Get specific order with user information"""
            if random.random() < self.failure_rate:
                raise HTTPException(status_code=500, detail="Internal server error")
            
            if order_id not in self.orders:
                raise HTTPException(status_code=404, detail="Order not found")
            
            order = self.orders[order_id].copy()
            
            # Discover and call user service
            try:
                user_services = await self.discovery_client.discover_services("user-service")
                if user_services:
                    # Simple load balancing - random selection
                    selected_service = random.choice(user_services)
                    user_url = f"http://{selected_service['address']}:{selected_service['port']}/users/{order['user_id']}"
                    
                    import aiohttp
                    async with aiohttp.ClientSession() as session:
                        async with session.get(user_url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                            if response.status == 200:
                                user_data = await response.json()
                                order['user'] = user_data['user']
                                order['discovery_used'] = selected_service['id']
                            else:
                                order['user'] = {"error": "User service unavailable"}
                else:
                    order['user'] = {"error": "No user service instances found"}
                    
            except Exception as e:
                order['user'] = {"error": f"Failed to fetch user: {str(e)}"}
            
            return {
                "order": order,
                "served_by": self.service_id
            }

if __name__ == "__main__":
    service = OrderService()
    uvicorn.run(
        service.app,
        host="0.0.0.0",
        port=service.port,
        access_log=False
    )
EOF

# Create API Gateway - copy base_service.py
mkdir -p services/api-gateway
cp services/user-service/base_service.py services/api-gateway/

cat > services/api-gateway/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["python", "main.py"]
EOF

cat > services/api-gateway/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
python-consul==1.1.0
aiohttp==3.9.0
EOF

cat > services/api-gateway/main.py << 'EOF'
import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import ServiceDiscoveryClient

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import aiohttp

class APIGateway:
    """API Gateway with service discovery and load balancing"""
    
    def __init__(self):
        self.port = int(os.getenv('GATEWAY_PORT', '8000'))
        self.consul_host = os.getenv('CONSUL_HOST', 'localhost')
        
        self.app = FastAPI(title="API Gateway")
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        self.discovery_client = ServiceDiscoveryClient(self.consul_host)
        self.setup_routes()
    
    def setup_routes(self):
        """Setup gateway routes"""
        
        @self.app.get("/health")
        async def health():
            return {"status": "healthy", "service": "api-gateway"}
        
        @self.app.get("/api/users")
        async def proxy_users():
            """Proxy to user service"""
            return await self.proxy_request("user-service", "/users")
        
        @self.app.get("/api/users/{user_id}")
        async def proxy_user(user_id: str):
            """Proxy to user service"""
            return await self.proxy_request("user-service", f"/users/{user_id}")
        
        @self.app.get("/api/orders")
        async def proxy_orders():
            """Proxy to order service"""
            return await self.proxy_request("order-service", "/orders")
        
        @self.app.get("/api/orders/{order_id}")
        async def proxy_order(order_id: str):
            """Proxy to order service"""
            return await self.proxy_request("order-service", f"/orders/{order_id}")
        
        @self.app.get("/api/discovery/services")
        async def list_services():
            """List all discovered services"""
            user_services = await self.discovery_client.discover_services("user-service")
            order_services = await self.discovery_client.discover_services("order-service")
            
            return {
                "services": {
                    "user-service": user_services,
                    "order-service": order_services
                },
                "total_instances": len(user_services) + len(order_services)
            }
    
    async def proxy_request(self, service_name: str, path: str):
        """Proxy request to discovered service with load balancing"""
        try:
            services = await self.discovery_client.discover_services(service_name)
            
            if not services:
                raise HTTPException(status_code=503, detail=f"No healthy {service_name} instances found")
            
            # Simple round-robin load balancing
            selected_service = random.choice(services)
            target_url = f"http://{selected_service['address']}:{selected_service['port']}{path}"
            
            async with aiohttp.ClientSession() as session:
                async with session.get(target_url, timeout=aiohttp.ClientTimeout(total=10)) as response:
                    if response.status == 200:
                        data = await response.json()
                        # Add gateway metadata
                        data['gateway_routing'] = {
                            'target_service': selected_service['id'],
                            'service_address': f"{selected_service['address']}:{selected_service['port']}",
                            'discovery_time': asyncio.get_event_loop().time()
                        }
                        return data
                    else:
                        error_text = await response.text()
                        raise HTTPException(status_code=response.status, detail=error_text)
                        
        except aiohttp.ClientError as e:
            raise HTTPException(status_code=503, detail=f"Service communication error: {str(e)}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Gateway error: {str(e)}")

if __name__ == "__main__":
    gateway = APIGateway()
    uvicorn.run(
        gateway.app,
        host="0.0.0.0",
        port=gateway.port,
        access_log=True
    )
EOF

# Create Web Dashboard
mkdir -p web-dashboard
cat > web-dashboard/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
EOF

cat > web-dashboard/package.json << 'EOF'
{
  "name": "service-discovery-dashboard",
  "version": "1.0.0",
  "description": "Service Discovery Visualization Dashboard",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "ws": "^8.14.2"
  }
}
EOF

cat > web-dashboard/server.js << 'EOF'
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const axios = require('axios');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const CONSUL_HOST = process.env.CONSUL_HOST || 'localhost';
const CONSUL_URL = `http://${CONSUL_HOST}:8500`;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// API endpoint to get service discovery data
app.get('/api/services', async (req, res) => {
    try {
        const response = await axios.get(`${CONSUL_URL}/v1/agent/services`);
        const services = response.data;
        
        // Get health status for each service
        const servicesWithHealth = await Promise.all(
            Object.entries(services).map(async ([id, service]) => {
                try {
                    const healthResponse = await axios.get(
                        `${CONSUL_URL}/v1/health/service/${service.Service}?passing=true`
                    );
                    return {
                        id: service.ID,
                        name: service.Service,
                        address: service.Address,
                        port: service.Port,
                        tags: service.Tags,
                        health: healthResponse.data.length > 0 ? 'healthy' : 'unhealthy'
                    };
                } catch (error) {
                    return {
                        id: service.ID,
                        name: service.Service,
                        address: service.Address,
                        port: service.Port,
                        tags: service.Tags,
                        health: 'unknown'
                    };
                }
            })
        );
        
        res.json(servicesWithHealth);
    } catch (error) {
        console.error('Error fetching services:', error.message);
        res.status(500).json({ error: 'Failed to fetch services' });
    }
});

// WebSocket for real-time updates
wss.on('connection', (ws) => {
    console.log('Client connected to dashboard');
    
    // Send initial data
    const sendServicesUpdate = async () => {
        try {
            const response = await axios.get('http://localhost:3000/api/services');
            ws.send(JSON.stringify({
                type: 'services_update',
                data: response.data
            }));
        } catch (error) {
            console.error('Error sending update:', error.message);
        }
    };
    
    // Send updates every 5 seconds
    const interval = setInterval(sendServicesUpdate, 5000);
    sendServicesUpdate(); // Send initial update
    
    ws.on('close', () => {
        console.log('Client disconnected');
        clearInterval(interval);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Dashboard server running on port ${PORT}`);
});
EOF

cat > web-dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Discovery Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }

        .header {
            text-align: center;
            margin-bottom: 40px;
            color: white;
        }

        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
        }

        .header p {
            font-size: 1.1rem;
            opacity: 0.9;
        }

        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }

        .stat-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            text-align: center;
        }

        .stat-number {
            font-size: 2rem;
            font-weight: bold;
            color: #667eea;
        }

        .stat-label {
            color: #666;
            margin-top: 5px;
        }

        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
        }

        .service-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            transition: transform 0.2s;
        }

        .service-card:hover {
            transform: translateY(-2px);
        }

        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }

        .service-name {
            font-size: 1.2rem;
            font-weight: bold;
            color: #333;
        }

        .health-status {
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
            text-transform: uppercase;
        }

        .health-healthy {
            background: #d4edda;
            color: #155724;
        }

        .health-unhealthy {
            background: #f8d7da;
            color: #721c24;
        }

        .health-unknown {
            background: #fff3cd;
            color: #856404;
        }

        .service-details {
            color: #666;
            line-height: 1.6;
        }

        .instance-id {
            font-family: 'Courier New', monospace;
            background: #f8f9fa;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.9rem;
        }

        .tags {
            margin-top: 10px;
        }

        .tag {
            display: inline-block;
            background: #e9ecef;
            color: #495057;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 0.8rem;
            margin-right: 5px;
            margin-bottom: 5px;
        }

        .connection-status {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 10px 15px;
            border-radius: 5px;
            font-weight: bold;
            z-index: 1000;
        }

        .connected {
            background: #d4edda;
            color: #155724;
        }

        .disconnected {
            background: #f8d7da;
            color: #721c24;
        }

        .test-buttons {
            margin: 20px 0;
            text-align: center;
        }

        .test-button {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            margin: 0 10px;
            cursor: pointer;
            font-size: 1rem;
            transition: background 0.2s;
        }

        .test-button:hover {
            background: #5a6fd8;
        }

        .api-response {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 5px;
            padding: 15px;
            margin: 20px 0;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Service Discovery Dashboard</h1>
            <p>Real-time monitoring of distributed service instances</p>
        </div>

        <div class="connection-status" id="connectionStatus">
            Connecting...
        </div>

        <div class="stats">
            <div class="stat-card">
                <div class="stat-number" id="totalServices">-</div>
                <div class="stat-label">Total Services</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="healthyInstances">-</div>
                <div class="stat-label">Healthy Instances</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="unhealthyInstances">-</div>
                <div class="stat-label">Unhealthy Instances</div>
            </div>
            <div class="stat-card">
                <div class="stat-number" id="lastUpdate">-</div>
                <div class="stat-label">Last Update</div>
            </div>
        </div>

        <div class="test-buttons">
            <button class="test-button" onclick="testAPICall('/api/users')">Test User Service</button>
            <button class="test-button" onclick="testAPICall('/api/orders')">Test Order Service</button>
            <button class="test-button" onclick="testAPICall('/api/discovery/services')">Test Discovery</button>
        </div>

        <div id="apiResponse" class="api-response" style="display: none;"></div>

        <div class="services-grid" id="servicesGrid">
            <!-- Services will be populated here -->
        </div>
    </div>

    <script>
        let ws;
        let services = [];

        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(`${protocol}//${window.location.host}`);

            ws.onopen = function() {
                updateConnectionStatus(true);
                console.log('Connected to dashboard');
            };

            ws.onmessage = function(event) {
                const message = JSON.parse(event.data);
                if (message.type === 'services_update') {
                    services = message.data;
                    updateDashboard();
                }
            };

            ws.onclose = function() {
                updateConnectionStatus(false);
                console.log('Disconnected from dashboard');
                // Reconnect after 5 seconds
                setTimeout(connectWebSocket, 5000);
            };

            ws.onerror = function(error) {
                console.error('WebSocket error:', error);
                updateConnectionStatus(false);
            };
        }

        function updateConnectionStatus(connected) {
            const statusElement = document.getElementById('connectionStatus');
            if (connected) {
                statusElement.textContent = '🟢 Connected';
                statusElement.className = 'connection-status connected';
            } else {
                statusElement.textContent = '🔴 Disconnected';
                statusElement.className = 'connection-status disconnected';
            }
        }

        function updateDashboard() {
            updateStats();
            updateServicesGrid();
        }

        function updateStats() {
            const totalServices = new Set(services.map(s => s.name)).size;
            const healthyInstances = services.filter(s => s.health === 'healthy').length;
            const unhealthyInstances = services.filter(s => s.health !== 'healthy').length;

            document.getElementById('totalServices').textContent = totalServices;
            document.getElementById('healthyInstances').textContent = healthyInstances;
            document.getElementById('unhealthyInstances').textContent = unhealthyInstances;
            document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
        }

        function updateServicesGrid() {
            const grid = document.getElementById('servicesGrid');
            grid.innerHTML = '';

            services.forEach(service => {
                const card = document.createElement('div');
                card.className = 'service-card';
                
                const healthClass = `health-${service.health}`;
                const tags = service.tags ? service.tags.map(tag => 
                    `<span class="tag">${tag}</span>`).join('') : '';

                card.innerHTML = `
                    <div class="service-header">
                        <div class="service-name">${service.name}</div>
                        <div class="health-status ${healthClass}">${service.health}</div>
                    </div>
                    <div class="service-details">
                        <div><strong>Instance:</strong> <span class="instance-id">${service.id}</span></div>
                        <div><strong>Address:</strong> ${service.address}:${service.port}</div>
                        <div class="tags">${tags}</div>
                    </div>
                `;
                
                grid.appendChild(card);
            });
        }

        async function testAPICall(endpoint) {
            const responseDiv = document.getElementById('apiResponse');
            responseDiv.style.display = 'block';
            responseDiv.textContent = 'Loading...';

            try {
                const response = await fetch(`http://localhost:8000${endpoint}`);
                const data = await response.json();
                responseDiv.textContent = `Status: ${response.status}\n\n${JSON.stringify(data, null, 2)}`;
            } catch (error) {
                responseDiv.textContent = `Error: ${error.message}`;
            }
        }

        // Initialize dashboard
        connectWebSocket();
    </script>
</body>
</html>
EOF

# Create demo script
cat > run-demo.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Service Discovery Demo"
echo "================================"

# Build and start all services
echo "📦 Building Docker images..."
docker-compose build

echo "🔄 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "✅ Demo is ready!"
echo ""
echo "🌐 Access Points:"
echo "  • Consul UI:        http://localhost:8500"
echo "  • API Gateway:      http://localhost:8000"
echo "  • Web Dashboard:    http://localhost:3000"
echo "  • User Service 1:   http://localhost:8001"
echo "  • User Service 2:   http://localhost:8002"
echo "  • Order Service:    http://localhost:8003"
echo ""
echo "🧪 Test Commands:"
echo "  curl http://localhost:8000/api/users"
echo "  curl http://localhost:8000/api/orders/1"
echo "  curl http://localhost:8000/api/discovery/services"
echo ""
echo "📊 Monitor logs with: docker-compose logs -f"
echo "🛑 Stop demo with: docker-compose down"
EOF

chmod +x run-demo.sh

# Create test script
cat > test-discovery.sh << 'EOF'
#!/bin/bash

echo "🔬 Testing Service Discovery Patterns"
echo "===================================="

# Test basic service calls
echo "1. Testing User Service through Gateway..."
curl -s http://localhost:8000/api/users | jq '.'

echo -e "\n2. Testing Order Service (with user discovery)..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n3. Testing Discovery API..."
curl -s http://localhost:8000/api/discovery/services | jq '.'

# Test failure scenarios
echo -e "\n4. Testing Circuit Breaker (stopping user-service-2)..."
docker-compose stop user-service-2
sleep 5

echo "Calling order service after user-service-2 failure..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n5. Restarting user-service-2..."
docker-compose start user-service-2
sleep 10

echo "Service should recover automatically..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n✅ Discovery testing complete!"
EOF

chmod +x test-discovery.sh

echo ""
echo "🎉 Service Discovery Demo Setup Complete!"
echo "========================================"
echo ""
echo "📁 Created project structure with individual service copies"
echo ""
echo "🚀 Quick Start:"
echo "  1. Run: ./run-demo.sh"
echo "  2. Open: http://localhost:3000 (Dashboard)"
echo "  3. Test: ./test-discovery.sh"
echo ""
echo "🔍 Features Demonstrated:"
echo "  • Client-side service discovery with Consul"
echo "  • Health checking and failure detection"
echo "  • Load balancing and circuit breakers"
echo "  • Service registration/deregistration"
echo "  • Real-time discovery monitoring"
echo "  • Cross-service communication patterns"
echo ""
echo "Ready to explore service discovery patterns!"