import time
import random
import logging
import asyncio
from enum import Enum
from dataclasses import dataclass
from typing import Optional
import aiohttp
import json

class CircuitState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"

@dataclass
class CircuitBreaker:
    failure_threshold: int = 5
    recovery_timeout: int = 30
    success_threshold: int = 3
    
    def __post_init__(self):
        self.failure_count = 0
        self.last_failure_time = 0
        self.state = CircuitState.CLOSED
        self.success_count = 0

    async def call(self, func, *args, **kwargs):
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.recovery_timeout:
                self.state = CircuitState.HALF_OPEN
                self.success_count = 0
            else:
                raise Exception("Circuit breaker is OPEN")
        
        try:
            result = await func(*args, **kwargs)
            await self.on_success()
            return result
        except Exception as e:
            await self.on_failure()
            raise e

    async def on_success(self):
        if self.state == CircuitState.HALF_OPEN:
            self.success_count += 1
            if self.success_count >= self.success_threshold:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
        elif self.state == CircuitState.CLOSED:
            self.failure_count = max(0, self.failure_count - 1)

    async def on_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN

class HealthMonitor:
    def __init__(self):
        self.services = {}
        self.cascade_events = []
    
    def update_service_health(self, service_name: str, is_healthy: bool, response_time: float):
        self.services[service_name] = {
            'healthy': is_healthy,
            'response_time': response_time,
            'timestamp': time.time()
        }
        
        # Detect cascade patterns
        if not is_healthy:
            self._check_cascade_pattern(service_name)
    
    def _check_cascade_pattern(self, failed_service: str):
        recent_failures = [
            name for name, health in self.services.items()
            if not health['healthy'] and time.time() - health['timestamp'] < 60
        ]
        
        if len(recent_failures) >= 2:
            self.cascade_events.append({
                'timestamp': time.time(),
                'trigger': failed_service,
                'affected_services': recent_failures
            })

monitor = HealthMonitor()
