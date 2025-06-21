"""
Load Generator - Creates configurable load to demonstrate backpressure
Features resilient connection handling and exponential backoff
"""
import asyncio
import time
import random
import os
import json
from typing import List
import httpx
from shared_utils import setup_logging, create_redis_client

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway-service:8000")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")

logger = setup_logging("load-generator")
redis_client = None

# Load generation configuration
load_config = {
    "concurrent_users": 10,
    "requests_per_second": 5,
    "test_duration": 300,  # 5 minutes
    "priority_distribution": {"high": 0.1, "normal": 0.7, "low": 0.2},
    "enabled": False
}

class ResilientLoadGenerator:
    def __init__(self):
        self.http_client = None
        self.statistics = {
            "total_requests": 0,
            "successful_requests": 0,
            "failed_requests": 0,
            "timeouts": 0,
            "backpressure_rejections": 0,
            "connection_errors": 0,
            "average_latency": 0.0
        }
        self.latencies = []
        self.consecutive_failures = 0
        self.max_retry_delay = 30  # Maximum delay between retries
    
    async def ensure_connection(self):
        """Ensure HTTP client is connected with exponential backoff retry"""
        max_retries = 10
        base_delay = 1.0
        
        for attempt in range(max_retries):
            try:
                if self.http_client is None:
                    self.http_client = httpx.AsyncClient(
                        timeout=httpx.Timeout(10.0, connect=5.0),
                        limits=httpx.Limits(max_connections=20, max_keepalive_connections=10)
                    )
                
                # Test connection with health check
                response = await self.http_client.get(f"{GATEWAY_URL}/health")
                if response.status_code == 200:
                    logger.info("Successfully connected to gateway service")
                    self.consecutive_failures = 0
                    return True
                    
            except Exception as e:
                logger.warning(
                    "Connection attempt failed", 
                    attempt=attempt + 1, 
                    error=str(e),
                    max_retries=max_retries
                )
                
                if self.http_client:
                    await self.http_client.aclose()
                    self.http_client = None
                
                if attempt < max_retries - 1:
                    # Exponential backoff with jitter
                    delay = min(base_delay * (2 ** attempt), self.max_retry_delay)
                    jitter = random.uniform(0, 0.1 * delay)
                    await asyncio.sleep(delay + jitter)
        
        logger.error("Failed to establish connection after all retries")
        return False
    
    async def generate_request(self, priority: str = "normal"):
        """Generate a single request with specified priority and resilient error handling"""
        start_time = time.time()
        
        try:
            if not await self.ensure_connection():
                self.statistics["total_requests"] += 1
                self.statistics["connection_errors"] += 1
                self.consecutive_failures += 1
                logger.error("Cannot establish connection", event="Request failed", priority=priority)
                return
            
            headers = {"X-Priority": priority}
            response = await self.http_client.get(
                f"{GATEWAY_URL}/api/process",
                headers=headers
            )
            
            latency = time.time() - start_time
            self.latencies.append(latency)
            
            self.statistics["total_requests"] += 1
            self.consecutive_failures = 0  # Reset failure counter on success
            
            if response.status_code == 200:
                self.statistics["successful_requests"] += 1
                logger.info("Request successful", latency=round(latency, 3), priority=priority)
            elif response.status_code == 503:
                self.statistics["backpressure_rejections"] += 1
                logger.info("Backpressure rejection received", priority=priority)
            else:
                self.statistics["failed_requests"] += 1
                logger.warning("Request failed", status_code=response.status_code, priority=priority)
            
            # Update average latency (keep only recent samples)
            if len(self.latencies) > 1000:
                self.latencies = self.latencies[-500:]  # Keep last 500 samples
            self.statistics["average_latency"] = sum(self.latencies) / len(self.latencies)
            
        except httpx.TimeoutException:
            self.statistics["total_requests"] += 1
            self.statistics["timeouts"] += 1
            self.consecutive_failures += 1
            logger.warning("Request timeout", priority=priority, event="Request timeout")
            
        except httpx.ConnectError as e:
            self.statistics["total_requests"] += 1
            self.statistics["connection_errors"] += 1
            self.consecutive_failures += 1
            logger.error("Connection error", error=str(e), priority=priority, event="Request failed")
            
            # Close client to force reconnection on next request
            if self.http_client:
                await self.http_client.aclose()
                self.http_client = None
            
        except Exception as e:
            self.statistics["total_requests"] += 1
            self.statistics["failed_requests"] += 1
            self.consecutive_failures += 1
            logger.error("Unexpected error", error=str(e), priority=priority, event="Request failed")
    
    def get_request_priority(self) -> str:
        """Get random priority based on distribution"""
        rand = random.random()
        cumulative = 0
        
        for priority, prob in load_config["priority_distribution"].items():
            cumulative += prob
            if rand <= cumulative:
                return priority
        
        return "normal"
    
    async def adaptive_delay(self):
        """Implement adaptive delay based on consecutive failures"""
        if self.consecutive_failures > 0:
            # Exponential backoff based on consecutive failures
            delay = min(0.1 * (2 ** self.consecutive_failures), 5.0)
            logger.info("Applying adaptive delay", delay=delay, consecutive_failures=self.consecutive_failures)
            await asyncio.sleep(delay)
    
    async def run_load_test(self):
        """Run continuous load test with adaptive behavior"""
        logger.info("Starting resilient load test", config=load_config)
        
        while load_config["enabled"]:
            try:
                # Apply adaptive delay if we're having connection issues
                await self.adaptive_delay()
                
                tasks = []
                
                # Reduce concurrent load if we're experiencing failures
                concurrent_users = load_config["concurrent_users"]
                if self.consecutive_failures > 3:
                    concurrent_users = max(1, concurrent_users // 2)
                    logger.info("Reducing load due to failures", reduced_users=concurrent_users)
                
                # Create concurrent requests
                for _ in range(concurrent_users):
                    priority = self.get_request_priority()
                    task = asyncio.create_task(self.generate_request(priority))
                    tasks.append(task)
                
                # Wait for all requests to complete
                await asyncio.gather(*tasks, return_exceptions=True)
                
                # Store statistics in Redis
                if redis_client:
                    await redis_client.set(
                        "load_generator_stats",
                        json.dumps(self.statistics)
                    )
                
                # Adaptive wait time based on request rate and failure rate
                base_wait = 1.0 / load_config["requests_per_second"]
                if self.consecutive_failures > 0:
                    # Slow down requests if experiencing failures
                    base_wait *= (1 + self.consecutive_failures * 0.5)
                
                await asyncio.sleep(base_wait)
                
            except Exception as e:
                logger.error("Load test iteration failed", error=str(e))
                await asyncio.sleep(5.0)  # Wait before retrying
        
        logger.info("Load test stopped")
        if self.http_client:
            await self.http_client.aclose()

async def wait_for_services():
    """Wait for services to be ready before starting load generation"""
    logger.info("Waiting for services to be ready...")
    
    max_wait_time = 120  # 2 minutes
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{GATEWAY_URL}/health")
                if response.status_code == 200:
                    logger.info("Gateway service is ready")
                    return True
        except Exception as e:
            logger.info("Services not ready yet, waiting...", error=str(e))
        
        await asyncio.sleep(5.0)
    
    logger.warning("Timeout waiting for services, proceeding anyway")
    return False

async def main():
    global redis_client
    
    logger.info("Starting resilient load generator")
    
    # Wait for services to be ready
    await wait_for_services()
    
    # Connect to Redis with retry logic
    for attempt in range(5):
        try:
            redis_client = await create_redis_client(host=REDIS_HOST)
            if redis_client:
                logger.info("Connected to Redis")
                break
        except Exception as e:
            logger.warning("Redis connection attempt failed", attempt=attempt + 1, error=str(e))
            await asyncio.sleep(2.0)
    
    if not redis_client:
        logger.error("Failed to connect to Redis, continuing without statistics storage")
    
    # Initialize load generator
    load_generator = ResilientLoadGenerator()
    
    # Start background task to continuously send stats to Redis
    asyncio.create_task(send_stats_to_redis(load_generator))
    
    # Start load generation if enabled
    if load_config["enabled"]:
        await load_generator.run_load_test()
    else:
        logger.info("Load generator ready, waiting for activation")
        while True:
            try:
                # Check for configuration updates from Redis
                if redis_client:
                    config_update = await redis_client.get("load_config")
                    if config_update:
                        updated_config = json.loads(config_update)
                        load_config.update(updated_config)
                        
                        if load_config["enabled"]:
                            await load_generator.run_load_test()
                
                await asyncio.sleep(1.0)
            except Exception as e:
                logger.error("Main loop error", error=str(e))
                await asyncio.sleep(5.0)

async def send_stats_to_redis(load_generator):
    """Send load generator statistics to Redis every second"""
    while True:
        try:
            if redis_client:
                await redis_client.set(
                    "load_generator_stats",
                    json.dumps(load_generator.statistics)
                )
            await asyncio.sleep(1.0)
        except Exception as e:
            logger.error("Error sending stats to Redis", error=str(e))
            await asyncio.sleep(5.0)

if __name__ == "__main__":
    asyncio.run(main())
