import time
import json
from typing import Dict, Any, List
import redis.asyncio as redis
import logging

logger = logging.getLogger(__name__)

class MetricsCollector:
    """Collect and aggregate rate limiting metrics"""
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.metrics_key = "rate_limiting_metrics"
        self.stats_key = "rate_limiting_stats"
    
    async def record_request(self, limiter_type: str, user_id: str, allowed: bool, 
                           processing_time: float, metadata: Dict[str, Any]) -> None:
        """Record a rate limiting request"""
        timestamp = time.time()
        
        metric_data = {
            "timestamp": timestamp,
            "limiter_type": limiter_type,
            "user_id": user_id,
            "allowed": allowed,
            "processing_time_ms": processing_time,
            "metadata": metadata
        }
        
        try:
            # Store individual metric
            await self.redis.lpush(self.metrics_key, json.dumps(metric_data))
            await self.redis.ltrim(self.metrics_key, 0, 999)  # Keep last 1000 metrics
            
            # Update aggregated stats
            await self._update_stats(limiter_type, allowed, processing_time)
            
        except Exception as e:
            logger.error(f"Failed to record metric: {e}")
    
    async def _update_stats(self, limiter_type: str, allowed: bool, processing_time: float) -> None:
        """Update aggregated statistics"""
        now = int(time.time())
        minute_bucket = now // 60  # Group by minute
        
        stats_key = f"{self.stats_key}:{limiter_type}:{minute_bucket}"
        
        # Increment counters
        pipe = self.redis.pipeline()
        pipe.hincrby(stats_key, "total_requests", 1)
        
        if allowed:
            pipe.hincrby(stats_key, "allowed_requests", 1)
        else:
            pipe.hincrby(stats_key, "blocked_requests", 1)
        
        # Track processing times (simple average)
        pipe.hincrbyfloat(stats_key, "total_processing_time", processing_time)
        
        # Set expiration (keep stats for 1 hour)
        pipe.expire(stats_key, 3600)
        
        await pipe.execute()
    
    async def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics and statistics"""
        try:
            # Get recent individual metrics
            raw_metrics = await self.redis.lrange(self.metrics_key, 0, 99)
            recent_metrics = []
            
            for metric in raw_metrics:
                try:
                    recent_metrics.append(json.loads(metric))
                except json.JSONDecodeError:
                    continue
            
            # Get aggregated stats for last 10 minutes
            stats = await self._get_recent_stats(10)
            
            # Calculate real-time statistics
            realtime_stats = self._calculate_realtime_stats(recent_metrics)
            
            return {
                "recent_metrics": recent_metrics[:50],  # Last 50 requests
                "aggregated_stats": stats,
                "realtime_stats": realtime_stats,
                "timestamp": time.time()
            }
            
        except Exception as e:
            logger.error(f"Failed to get metrics: {e}")
            return {"error": str(e)}
    
    async def _get_recent_stats(self, minutes: int) -> Dict[str, Any]:
        """Get aggregated stats for recent time period"""
        now = int(time.time())
        current_minute = now // 60
        
        stats = {
            "token_bucket": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0},
            "sliding_window": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0},
            "fixed_window": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0}
        }
        
        try:
            for limiter_type in stats.keys():
                total_requests = 0
                total_allowed = 0
                total_blocked = 0
                total_processing_time = 0.0
                
                for i in range(minutes):
                    minute_bucket = current_minute - i
                    stats_key = f"{self.stats_key}:{limiter_type}:{minute_bucket}"
                    
                    minute_stats = await self.redis.hmget(
                        stats_key, 
                        "total_requests", "allowed_requests", "blocked_requests", "total_processing_time"
                    )
                    
                    if minute_stats[0]:  # If data exists
                        total_requests += int(minute_stats[0] or 0)
                        total_allowed += int(minute_stats[1] or 0)
                        total_blocked += int(minute_stats[2] or 0)
                        total_processing_time += float(minute_stats[3] or 0)
                
                stats[limiter_type] = {
                    "total": total_requests,
                    "allowed": total_allowed,
                    "blocked": total_blocked,
                    "block_rate": (total_blocked / total_requests * 100) if total_requests > 0 else 0,
                    "avg_processing_time": (total_processing_time / total_requests) if total_requests > 0 else 0
                }
        
        except Exception as e:
            logger.error(f"Failed to get recent stats: {e}")
        
        return stats
    
    def _calculate_realtime_stats(self, metrics: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate real-time statistics from recent metrics"""
        if not metrics:
            return {}
        
        # Group by limiter type
        by_limiter = {}
        for metric in metrics:
            limiter_type = metric.get("limiter_type")
            if limiter_type not in by_limiter:
                by_limiter[limiter_type] = []
            by_limiter[limiter_type].append(metric)
        
        stats = {}
        for limiter_type, limiter_metrics in by_limiter.items():
            total = len(limiter_metrics)
            allowed = sum(1 for m in limiter_metrics if m.get("allowed"))
            blocked = total - allowed
            
            processing_times = [m.get("processing_time_ms", 0) for m in limiter_metrics]
            avg_processing_time = sum(processing_times) / len(processing_times) if processing_times else 0
            
            # Calculate requests per second (approximate)
            if total > 1:
                time_span = limiter_metrics[0]["timestamp"] - limiter_metrics[-1]["timestamp"]
                rps = total / time_span if time_span > 0 else 0
            else:
                rps = 0
            
            stats[limiter_type] = {
                "total": total,
                "allowed": allowed,
                "blocked": blocked,
                "block_rate": (blocked / total * 100) if total > 0 else 0,
                "avg_processing_time": avg_processing_time,
                "requests_per_second": rps
            }
        
        return stats
