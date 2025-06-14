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
