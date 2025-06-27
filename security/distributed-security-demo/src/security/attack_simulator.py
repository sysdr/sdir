"""
Attack simulation for testing security defenses
"""
import asyncio
import time
import random
import json
import httpx
import structlog

logger = structlog.get_logger()

class AttackSimulator:
    def __init__(self):
        self.target_host = "api-gateway"
        self.target_port = 8000
        self.base_url = f"https://{self.target_host}:{self.target_port}"
        
    async def simulate_sql_injection(self):
        """Simulate SQL injection attacks"""
        logger.info("Starting SQL injection simulation")
        
        payloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "1' UNION SELECT password FROM admin--",
            "admin'/*",
            "1' OR 1=1#"
        ]
        
        async with httpx.AsyncClient(verify=False) as client:
            for payload in payloads:
                try:
                    response = await client.get(
                        f"{self.base_url}/api/users/{payload}",
                        timeout=5.0
                    )
                    logger.info("SQL injection attempt", payload=payload, status=response.status_code)
                except Exception as e:
                    logger.warning("SQL injection blocked", payload=payload, error=str(e))
                
                await asyncio.sleep(1)
    
    async def simulate_brute_force(self):
        """Simulate brute force attacks"""
        logger.info("Starting brute force simulation")
        
        async with httpx.AsyncClient(verify=False) as client:
            for i in range(20):
                try:
                    response = await client.post(
                        f"{self.base_url}/api/login",
                        json={"username": "admin", "password": f"password{i}"},
                        timeout=5.0
                    )
                    logger.info("Brute force attempt", attempt=i, status=response.status_code)
                except Exception as e:
                    logger.warning("Brute force blocked", attempt=i, error=str(e))
                
                await asyncio.sleep(0.5)
    
    async def simulate_scanning(self):
        """Simulate port/endpoint scanning"""
        logger.info("Starting scanning simulation")
        
        endpoints = [
            "/admin", "/backup", "/config", "/debug", "/test",
            "/api/admin", "/api/config", "/api/debug", "/api/internal",
            "/.env", "/database.sql", "/backup.zip"
        ]
        
        async with httpx.AsyncClient(verify=False) as client:
            for endpoint in endpoints:
                try:
                    response = await client.get(
                        f"{self.base_url}{endpoint}",
                        timeout=5.0
                    )
                    logger.info("Scanning attempt", endpoint=endpoint, status=response.status_code)
                except Exception as e:
                    logger.warning("Scanning blocked", endpoint=endpoint, error=str(e))
                
                await asyncio.sleep(0.2)
    
    async def run_attack_scenarios(self):
        """Run all attack scenarios"""
        scenarios = [
            self.simulate_sql_injection,
            self.simulate_brute_force,
            self.simulate_scanning
        ]
        
        for scenario in scenarios:
            try:
                await scenario()
                await asyncio.sleep(5)  # Wait between scenarios
            except Exception as e:
                logger.error("Attack scenario failed", scenario=scenario.__name__, error=str(e))

async def main():
    simulator = AttackSimulator()
    
    # Wait for services to start
    await asyncio.sleep(30)
    
    while True:
        logger.info("Starting attack simulation cycle")
        await simulator.run_attack_scenarios()
        
        # Wait before next cycle
        await asyncio.sleep(60)

if __name__ == "__main__":
    asyncio.run(main())
