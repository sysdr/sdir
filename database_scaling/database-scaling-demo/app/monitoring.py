import time
import asyncio
from typing import Dict, Any
import json

class MetricsCollector:
    def __init__(self):
        self.metrics = {
            'requests_per_second': 0,
            'average_latency': 0,
            'active_connections': 0,
            'error_rate': 0,
            'last_updated': time.time()
        }
        self.historical_metrics = []

    async def get_current_stats(self) -> Dict[str, Any]:
        """Get current system statistics"""
        return {
            'timestamp': time.time(),
            'metrics': self.metrics,
            'system_health': 'healthy',
            'database_status': {
                'primary': 'online',
                'replicas': ['online', 'online'],
                'shards': {
                    'us': 'online',
                    'eu': 'online'
                }
            }
        }

    async def get_live_metrics(self) -> Dict[str, Any]:
        """Get live performance metrics for dashboard"""
        current_time = time.time()
        
        # Simulate real-time metrics
        metrics = {
            'timestamp': current_time,
            'queries_per_second': 100 + (50 * (0.5 - abs(0.5 - ((current_time % 10) / 10)))),
            'primary_latency': 15 + (10 * abs(0.5 - ((current_time % 8) / 8))),
            'replica_latency': 12 + (8 * abs(0.5 - ((current_time % 6) / 6))),
            'shard_us_latency': 8 + (5 * abs(0.5 - ((current_time % 7) / 7))),
            'shard_eu_latency': 9 + (5 * abs(0.5 - ((current_time % 9) / 9))),
            'connection_pool_usage': {
                'primary': 75 + (20 * abs(0.5 - ((current_time % 5) / 5))),
                'replica1': 60 + (15 * abs(0.5 - ((current_time % 4) / 4))),
                'replica2': 55 + (15 * abs(0.5 - ((current_time % 6) / 6))),
                'shard_us': 45 + (10 * abs(0.5 - ((current_time % 3) / 3))),
                'shard_eu': 40 + (10 * abs(0.5 - ((current_time % 4) / 4)))
            }
        }
        
        return metrics

    def record_metric(self, metric_name: str, value: float):
        """Record a performance metric"""
        self.metrics[metric_name] = value
        self.metrics['last_updated'] = time.time()
        
        # Keep historical data (last 100 points)
        self.historical_metrics.append({
            'timestamp': time.time(),
            'metric': metric_name,
            'value': value
        })
        
        if len(self.historical_metrics) > 100:
            self.historical_metrics.pop(0)
