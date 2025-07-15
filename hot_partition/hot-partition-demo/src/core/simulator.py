"""Partition workload simulator with hot partition generation."""

import asyncio
import random
import time
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List
import redis.asyncio as redis
import numpy as np

from src.models.partition import PartitionMetrics, PartitionAnalyzer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PartitionSimulator:
    """Simulates a distributed system with multiple partitions."""
    
    def __init__(self, num_partitions: int = 5, redis_url: str = None):
        self.num_partitions = num_partitions
        self.partitions = {f"partition_{i}": self._create_partition_state() 
                          for i in range(num_partitions)}
        self.analyzer = PartitionAnalyzer()
        self.redis_client = None
        self.redis_url = redis_url or os.getenv("REDIS_URL", "redis://localhost:6379")
        self.running = False
        
        # Hotspot configuration
        self.hotspot_active = False
        self.hotspot_partition = None
        self.hotspot_start_time = None
        self.hotspot_intensity = 1.0
        
    def _create_partition_state(self) -> Dict:
        """Create initial state for a partition."""
        return {
            "base_load": random.randint(100, 500),
            "memory_base": random.uniform(100, 300),
            "cpu_base": random.uniform(10, 30),
            "response_time_base": random.uniform(50, 150)
        }
    
    async def initialize(self):
        """Initialize Redis connection."""
        self.redis_client = redis.from_url(self.redis_url)
        await self.redis_client.ping()
        logger.info("Connected to Redis")
        
    async def trigger_hotspot(self, partition_id: str = None, intensity: float = 5.0):
        """Trigger a hotspot on a specific partition."""
        if partition_id is None:
            partition_id = random.choice(list(self.partitions.keys()))
            
        self.hotspot_active = True
        self.hotspot_partition = partition_id
        self.hotspot_start_time = datetime.now()
        self.hotspot_intensity = intensity
        
        logger.info(f"🔥 Hotspot triggered on {partition_id} with intensity {intensity}")
        
        # Store hotspot info in Redis
        hotspot_info = {
            "partition_id": partition_id,
            "intensity": intensity,
            "start_time": self.hotspot_start_time.isoformat(),
            "active": True
        }
        await self.redis_client.hset("hotspot_info", mapping=hotspot_info)
        
    async def end_hotspot(self):
        """End the current hotspot."""
        if self.hotspot_active:
            logger.info(f"🧯 Ending hotspot on {self.hotspot_partition}")
            self.hotspot_active = False
            self.hotspot_partition = None
            self.hotspot_start_time = None
            
            await self.redis_client.hset("hotspot_info", "active", "false")
    
    def _generate_partition_load(self, partition_id: str) -> PartitionMetrics:
        """Generate realistic load for a partition."""
        partition_state = self.partitions[partition_id]
        
        # Base load with some randomness
        base_requests = partition_state["base_load"]
        current_requests = base_requests + random.randint(-50, 100)
        
        # Apply hotspot if active
        if (self.hotspot_active and 
            partition_id == self.hotspot_partition and
            self.hotspot_start_time):
            
            # Calculate hotspot decay over time
            elapsed = (datetime.now() - self.hotspot_start_time).total_seconds()
            decay_factor = max(0.1, 1.0 - (elapsed / 300))  # 5 minute decay
            
            hotspot_multiplier = 1.0 + (self.hotspot_intensity - 1.0) * decay_factor
            current_requests = int(current_requests * hotspot_multiplier)
            
            # If hotspot has decayed significantly, end it
            if decay_factor < 0.2:
                asyncio.create_task(self.end_hotspot())
        
        # Generate correlated metrics
        memory_usage = (partition_state["memory_base"] + 
                       current_requests * 0.1 + 
                       random.uniform(-20, 30))
        
        cpu_usage = min(95, partition_state["cpu_base"] + 
                       current_requests * 0.05 + 
                       random.uniform(-5, 15))
        
        response_time = (partition_state["response_time_base"] + 
                        max(0, current_requests - base_requests) * 0.2 +
                        random.uniform(-10, 20))
        
        error_rate = max(0, min(100, (current_requests - base_requests * 2) * 0.01))
        
        return PartitionMetrics(
            partition_id=partition_id,
            request_count=max(0, current_requests),
            memory_usage_mb=max(50, memory_usage),
            cpu_usage_percent=max(5, cpu_usage),
            avg_response_time_ms=max(10, response_time),
            error_rate=max(0, error_rate)
        )
    
    async def _store_metrics(self, metrics: List[PartitionMetrics]):
        """Store metrics in Redis for API access."""
        try:
            # Store current metrics
            metrics_data = {}
            for metric in metrics:
                metrics_data[metric.partition_id] = json.dumps({
                    "request_count": metric.request_count,
                    "memory_usage_mb": metric.memory_usage_mb,
                    "cpu_usage_percent": metric.cpu_usage_percent,
                    "avg_response_time_ms": metric.avg_response_time_ms,
                    "error_rate": metric.error_rate,
                    "timestamp": metric.timestamp.isoformat()
                })
            
            await self.redis_client.hset("current_metrics", mapping=metrics_data)
            
            # Store historical metrics (last 50 entries)
            for metric in metrics:
                key = f"historical_{metric.partition_id}"
                value = json.dumps({
                    "request_count": metric.request_count,
                    "memory_usage_mb": metric.memory_usage_mb,
                    "cpu_usage_percent": metric.cpu_usage_percent,
                    "timestamp": metric.timestamp.isoformat()
                })
                
                await self.redis_client.lpush(key, value)
                await self.redis_client.ltrim(key, 0, 49)  # Keep last 50
                
        except Exception as e:
            logger.error(f"Error storing metrics: {e}")
    
    async def _analyze_and_alert(self, metrics: List[PartitionMetrics]):
        """Analyze metrics and generate alerts."""
        try:
            # Calculate entropy
            loads = [m.request_count for m in metrics]
            entropy = self.analyzer.calculate_entropy(loads)
            
            # Store entropy score
            await self.redis_client.hset("analysis_results", 
                                       "entropy_score", str(entropy))
            
            # Analyze each partition
            alerts = []
            for metric in metrics:
                # Add to analyzer history
                self.analyzer.add_metrics(metric)
                
                # Temporal analysis
                temporal = self.analyzer.detect_temporal_patterns(metric.partition_id)
                
                # Generate alert if needed
                alert = self.analyzer.generate_alert(
                    metric.partition_id, metric, entropy, temporal
                )
                
                if alert:
                    alerts.append(alert)
                    logger.warning(f"⚠️ Alert: {alert.partition_id} - {alert.severity} - {alert.recommended_action}")
            
            # Store alerts
            if alerts:
                alert_data = {}
                for i, alert in enumerate(alerts):
                    alert_data[f"alert_{i}"] = json.dumps({
                        "partition_id": alert.partition_id,
                        "severity": alert.severity,
                        "entropy_score": alert.entropy_score,
                        "load_factor": alert.load_factor,
                        "recommended_action": alert.recommended_action,
                        "timestamp": alert.timestamp.isoformat()
                    })
                
                await self.redis_client.hset("current_alerts", mapping=alert_data)
            else:
                await self.redis_client.delete("current_alerts")
                
        except Exception as e:
            logger.error(f"Error in analysis: {e}")
    
    async def run_simulation(self):
        """Main simulation loop."""
        logger.info("🚀 Starting partition simulation...")
        self.running = True
        
        # Auto-trigger hotspot after 30 seconds
        asyncio.create_task(self._auto_hotspot_cycle())
        
        iteration = 0
        while self.running:
            try:
                # Generate metrics for all partitions
                current_metrics = []
                for partition_id in self.partitions:
                    metrics = self._generate_partition_load(partition_id)
                    current_metrics.append(metrics)
                
                # Store metrics
                await self._store_metrics(current_metrics)
                
                # Analyze for hot partitions
                await self._analyze_and_alert(current_metrics)
                
                # Log summary every 10 iterations
                if iteration % 10 == 0:
                    total_requests = sum(m.request_count for m in current_metrics)
                    max_requests = max(m.request_count for m in current_metrics)
                    entropy = self.analyzer.calculate_entropy([m.request_count for m in current_metrics])
                    
                    logger.info(f"📊 Iteration {iteration}: Total={total_requests}, Max={max_requests}, Entropy={entropy:.3f}")
                
                iteration += 1
                await asyncio.sleep(2)  # Generate metrics every 2 seconds
                
            except Exception as e:
                logger.error(f"Error in simulation loop: {e}")
                await asyncio.sleep(5)
    
    async def _auto_hotspot_cycle(self):
        """Automatically trigger hotspots for demonstration."""
        await asyncio.sleep(30)  # Wait 30 seconds before first hotspot
        
        while self.running:
            if not self.hotspot_active:
                # Trigger random hotspot
                partition = random.choice(list(self.partitions.keys()))
                intensity = random.uniform(3.0, 8.0)
                await self.trigger_hotspot(partition, intensity)
                
                # Let hotspot run for 2-5 minutes
                await asyncio.sleep(random.uniform(120, 300))
            else:
                await asyncio.sleep(10)
    
    async def stop(self):
        """Stop the simulation."""
        self.running = False
        if self.redis_client:
            await self.redis_client.close()

async def main():
    """Main entry point for simulator."""
    simulator = PartitionSimulator(num_partitions=5)
    
    try:
        await simulator.initialize()
        await simulator.run_simulation()
    except KeyboardInterrupt:
        logger.info("Shutting down simulator...")
    finally:
        await simulator.stop()

if __name__ == "__main__":
    asyncio.run(main())
