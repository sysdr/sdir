"""
Cache Invalidation Strategies Demo
Production-grade cache invalidation patterns with real-time monitoring
"""

import asyncio
import json
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from collections import defaultdict
import random

from fastapi import FastAPI, WebSocket, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
import redis.asyncio as redis
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

app = FastAPI(title="Cache Invalidation Strategies Demo", version="1.0.0")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Global state for demo
cache_metrics = defaultdict(int)
active_connections = []
redis_client = None

class CacheInvalidationManager:
    """Production-grade cache invalidation with multiple strategies"""
    
    def __init__(self, redis_client):
        self.redis = redis_client
        self.strategies = {
            'ttl': self._ttl_strategy,
            'event_driven': self._event_driven_strategy,
            'lazy': self._lazy_strategy,
            'hybrid': self._hybrid_strategy
        }
        self.metrics = defaultdict(int)
        
    async def _ttl_strategy(self, key: str, data: Any, ttl_seconds: int = 60):
        """Time-based expiration with intelligent TTL calculation"""
        # Simulate Netflix's dynamic TTL calculation
        content_type = data.get('type', 'default')
        base_ttl = ttl_seconds
        
        # Adjust TTL based on content freshness requirements
        if content_type == 'user_profile':
            ttl = base_ttl * 2  # Less frequent changes
        elif content_type == 'real_time_data':
            ttl = base_ttl // 4  # More frequent changes
        else:
            ttl = base_ttl
            
        # Add jitter to prevent thundering herd (Twitter's approach)
        ttl_with_jitter = int(ttl * random.uniform(0.85, 1.0))
        
        await self.redis.setex(key, ttl_with_jitter, json.dumps(data))
        await self._update_metrics('ttl_set', key, ttl_with_jitter)
        
        logger.info("TTL strategy applied", 
                   key=key, ttl=ttl_with_jitter, strategy="ttl")
        return ttl_with_jitter
        
    async def _event_driven_strategy(self, key: str, data: Any):
        """Immediate invalidation on data change"""
        # Store data without TTL
        await self.redis.set(key, json.dumps(data))
        
        # Publish invalidation event to all subscribers
        invalidation_event = {
            'key': key,
            'action': 'invalidate',
            'timestamp': datetime.utcnow().isoformat(),
            'strategy': 'event_driven'
        }
        
        await self.redis.publish('cache_invalidation', json.dumps(invalidation_event))
        await self._update_metrics('event_driven_set', key)
        
        logger.info("Event-driven strategy applied", 
                   key=key, strategy="event_driven")
        
    async def _lazy_strategy(self, key: str, data: Any, ttl_seconds: int = 300):
        """Facebook TAO-style lazy invalidation"""
        # Store with extended TTL but mark validation timestamp
        cache_data = {
            'data': data,
            'cached_at': datetime.utcnow().isoformat(),
            'validation_ttl': ttl_seconds // 2  # Validate at 50% of TTL
        }
        
        await self.redis.setex(key, ttl_seconds, json.dumps(cache_data))
        await self._update_metrics('lazy_set', key, ttl_seconds)
        
        logger.info("Lazy strategy applied", 
                   key=key, ttl=ttl_seconds, strategy="lazy")
        
    async def _hybrid_strategy(self, key: str, data: Any):
        """Instagram's three-tier approach simulation"""
        # L1: Local cache (30s TTL)
        l1_key = f"l1:{key}"
        await self.redis.setex(l1_key, 30, json.dumps(data))
        
        # L2: Regional cache (5min TTL) 
        l2_key = f"l2:{key}"
        await self.redis.setex(l2_key, 300, json.dumps(data))
        
        # L3: Global cache (1hour TTL)
        l3_key = f"l3:{key}"
        await self.redis.setex(l3_key, 3600, json.dumps(data))
        
        await self._update_metrics('hybrid_set', key)
        
        logger.info("Hybrid strategy applied", 
                   key=key, strategy="hybrid")
        
    async def _update_metrics(self, action: str, key: str, value: Any = None):
        """Update cache metrics for monitoring"""
        try:
            # Update local metrics
            self.metrics[action] += 1
            self.metrics['total_operations'] += 1
            
            # Store metrics in Redis for persistence
            metrics_key = "cache_metrics"
            current_metrics = await self.redis.get(metrics_key)
            
            if current_metrics:
                metrics = json.loads(current_metrics)
            else:
                metrics = {}
                
            # Ensure metrics is a dict with proper defaults
            if not isinstance(metrics, dict):
                metrics = {}
            
            # Increment the specific action counter
            if action not in metrics:
                metrics[action] = 0
            metrics[action] += 1
            
            # Add timestamp
            metrics['last_updated'] = datetime.utcnow().isoformat()
            
            # Store back to Redis
            await self.redis.setex(metrics_key, 3600, json.dumps(metrics))
            
            logger.info("Metrics updated", action=action, key=key, value=metrics[action])
            
        except Exception as e:
            logger.error("Metrics update error", action=action, key=key, error=str(e))
        
    async def get_cache_data(self, key: str, strategy: str = 'ttl'):
        """Retrieve data using specified strategy with fallback handling"""
        try:
            if strategy == 'hybrid':
                # Try L1, then L2, then L3
                for level in ['l1', 'l2', 'l3']:
                    cache_key = f"{level}:{key}"
                    data = await self.redis.get(cache_key)
                    if data:
                        await self._update_metrics(f'{level}_hit', key)
                        return json.loads(data)
                        
                await self._update_metrics('cache_miss', key)
                return None
                
            elif strategy == 'lazy':
                data = await self.redis.get(key)
                if data:
                    cache_data = json.loads(data)
                    cached_at = datetime.fromisoformat(cache_data['cached_at'])
                    validation_ttl = cache_data['validation_ttl']
                    
                    # Check if validation is needed
                    if (datetime.utcnow() - cached_at).seconds > validation_ttl:
                        await self._update_metrics('lazy_validation_needed', key)
                        # In real system, would trigger background validation
                        
                    await self._update_metrics('lazy_hit', key)
                    return cache_data['data']
                    
            else:
                # Standard TTL or event-driven retrieval
                data = await self.redis.get(key)
                if data:
                    await self._update_metrics(f'{strategy}_hit', key)
                    return json.loads(data)
                    
            await self._update_metrics('cache_miss', key)
            return None
            
        except Exception as e:
            logger.error("Cache retrieval error", key=key, strategy=strategy, error=str(e))
            await self._update_metrics('cache_error', key)
            return None
            
    async def invalidate_cache(self, key: str, strategy: str = 'event_driven'):
        """Invalidate cache entry using specified strategy"""
        try:
            if strategy == 'hybrid':
                # Invalidate all levels
                for level in ['l1', 'l2', 'l3']:
                    cache_key = f"{level}:{key}"
                    await self.redis.delete(cache_key)
                    
            else:
                await self.redis.delete(key)
                
            # Publish invalidation event
            invalidation_event = {
                'key': key,
                'action': 'invalidate',
                'timestamp': datetime.utcnow().isoformat(),
                'strategy': strategy
            }
            
            await self.redis.publish('cache_invalidation', json.dumps(invalidation_event))
            await self._update_metrics('cache_invalidated', key)
            
            logger.info("Cache invalidated", key=key, strategy=strategy)
            
        except Exception as e:
            logger.error("Cache invalidation error", key=key, strategy=strategy, error=str(e))

# Initialize cache manager
cache_manager = None

@app.on_event("startup")
async def startup_event():
    """Initialize Redis connection and cache manager"""
    global redis_client, cache_manager
    
    try:
        redis_client = redis.from_url("redis://redis:6379", decode_responses=True)
        await redis_client.ping()
        
        cache_manager = CacheInvalidationManager(redis_client)
        
        logger.info("Application startup complete", redis_connected=True)
        
    except Exception as e:
        logger.error("Startup failed", error=str(e))
        raise

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup resources"""
    global redis_client
    
    if redis_client:
        await redis_client.close()
        
    logger.info("Application shutdown complete")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/api/cache/set")
async def set_cache_data(request: dict):
    """Set cache data using specified strategy"""
    try:
        key = request.get('key')
        data = request.get('data')
        strategy = request.get('strategy', 'ttl')
        ttl = request.get('ttl', 60)
        
        if not key or not data:
            raise HTTPException(status_code=400, detail="Key and data are required")
            
        if strategy == 'ttl':
            ttl_used = await cache_manager._ttl_strategy(key, data, ttl)
            result = {'success': True, 'ttl_used': ttl_used}
        elif strategy == 'event_driven':
            await cache_manager._event_driven_strategy(key, data)
            result = {'success': True, 'ttl_used': None}
        elif strategy == 'lazy':
            await cache_manager._lazy_strategy(key, data, ttl)
            result = {'success': True, 'ttl_used': ttl}
        elif strategy == 'hybrid':
            await cache_manager._hybrid_strategy(key, data)
            result = {'success': True, 'ttl_used': 'multi-tier'}
        else:
            raise HTTPException(status_code=400, detail="Invalid strategy")
            
        # Broadcast to WebSocket clients
        await broadcast_update({
            'type': 'cache_set',
            'key': key,
            'strategy': strategy,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        return result
        
    except Exception as e:
        logger.error("Cache set error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cache/get/{key}")
async def get_cache_data(key: str, strategy: str = 'ttl'):
    """Get cache data using specified strategy"""
    try:
        data = await cache_manager.get_cache_data(key, strategy)
        
        result = {
            'key': key,
            'data': data,
            'found': data is not None,
            'strategy': strategy,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Broadcast to WebSocket clients
        await broadcast_update({
            'type': 'cache_get',
            'key': key,
            'found': data is not None,
            'strategy': strategy,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        return result
        
    except Exception as e:
        logger.error("Cache get error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/cache/invalidate/{key}")
async def invalidate_cache(key: str, strategy: str = 'event_driven'):
    """Invalidate cache entry"""
    try:
        await cache_manager.invalidate_cache(key, strategy)
        
        # Broadcast to WebSocket clients
        await broadcast_update({
            'type': 'cache_invalidated',
            'key': key,
            'strategy': strategy,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        return {'success': True, 'key': key, 'strategy': strategy}
        
    except Exception as e:
        logger.error("Cache invalidation error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/metrics")
async def get_metrics():
    """Get cache metrics"""
    try:
        # Get metrics from Redis
        metrics_data = await redis_client.get("cache_metrics")
        
        if metrics_data:
            metrics = json.loads(metrics_data)
            # Ensure we have a proper dict
            if not isinstance(metrics, dict):
                metrics = {}
        else:
            metrics = {}
            
        # Add runtime metrics
        runtime_metrics = {
            'redis_connection_status': 'connected',
            'active_websocket_connections': len(active_connections),
            'current_time': datetime.utcnow().isoformat()
        }
        
        # Add summary statistics
        total_operations = sum(metrics.get(k, 0) for k in metrics.keys() if k != 'last_updated')
        cache_hits = sum(metrics.get(k, 0) for k in metrics.keys() if 'hit' in k)
        cache_misses = sum(metrics.get(k, 0) for k in metrics.keys() if 'miss' in k)
        
        enhanced_metrics = {
            **metrics,
            'summary': {
                'total_operations': total_operations,
                'cache_hits': cache_hits,
                'cache_misses': cache_misses,
                'hit_rate': (cache_hits / (cache_hits + cache_misses)) if (cache_hits + cache_misses) > 0 else 0
            }
        }
        
        return {
            'cache_metrics': enhanced_metrics,
            'runtime_metrics': runtime_metrics
        }
        
    except Exception as e:
        logger.error("Metrics retrieval error", error=str(e))
        return {'error': str(e)}

@app.post("/api/load-test/simulate")
async def simulate_load_test(request: dict):
    """Simulate load testing with cache avalanche scenarios"""
    try:
        test_type = request.get('test_type', 'cache_avalanche')
        duration = request.get('duration', 30)  # seconds
        concurrent_requests = request.get('concurrent_requests', 10)
        
        results = {
            'test_type': test_type,
            'duration': duration,
            'concurrent_requests': concurrent_requests,
            'start_time': datetime.utcnow().isoformat(),
            'metrics_before': await get_metrics(),
            'operations': []
        }
        
        # Simulate different load test scenarios
        if test_type == 'cache_avalanche':
            # Simulate cache miss avalanche
            for i in range(concurrent_requests):
                key = f"avalanche_key_{i}"
                # Force cache miss by using non-existent key
                result = await cache_manager.get_cache_data(key, 'ttl')
                results['operations'].append({
                    'operation': 'cache_get',
                    'key': key,
                    'result': 'miss' if result is None else 'hit'
                })
                
        elif test_type == 'ttl_expiration':
            # Test TTL expiration with multiple keys
            for i in range(concurrent_requests):
                key = f"ttl_test_{i}"
                data = {'test_data': f'value_{i}', 'type': 'ttl_test'}
                await cache_manager._ttl_strategy(key, data, 5)  # Short TTL
                results['operations'].append({
                    'operation': 'cache_set',
                    'key': key,
                    'strategy': 'ttl',
                    'ttl': 5
                })
                
        elif test_type == 'hybrid_strategy':
            # Test hybrid multi-tier caching
            for i in range(concurrent_requests):
                key = f"hybrid_test_{i}"
                data = {'test_data': f'value_{i}', 'type': 'hybrid_test'}
                await cache_manager._hybrid_strategy(key, data)
                results['operations'].append({
                    'operation': 'cache_set',
                    'key': key,
                    'strategy': 'hybrid'
                })
                
        elif test_type == 'event_driven':
            # Test event-driven invalidation
            for i in range(concurrent_requests):
                key = f"event_test_{i}"
                data = {'test_data': f'value_{i}', 'type': 'event_test'}
                await cache_manager._event_driven_strategy(key, data)
                results['operations'].append({
                    'operation': 'cache_set',
                    'key': key,
                    'strategy': 'event_driven'
                })
        
        # Wait for duration
        await asyncio.sleep(duration)
        
        results['end_time'] = datetime.utcnow().isoformat()
        results['metrics_after'] = await get_metrics()
        
        # Broadcast test results
        await broadcast_update({
            'type': 'load_test_complete',
            'test_type': test_type,
            'results': results
        })
        
        return results
        
    except Exception as e:
        logger.error("Load test error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/load-test/cache-avalanche")
async def simulate_cache_avalanche():
    """Simulate cache avalanche scenario (thundering herd problem)"""
    try:
        # Create a scenario where many requests hit the same expired key
        key = "avalanche_target"
        
        # First, set the key with a very short TTL (minimum 1 second)
        await cache_manager._ttl_strategy(key, {'data': 'original'}, 2)
        
        # Wait for it to expire
        await asyncio.sleep(3)
        
        # Simulate multiple concurrent requests for the same expired key
        concurrent_requests = 20
        tasks = []
        
        for i in range(concurrent_requests):
            task = cache_manager.get_cache_data(key, 'ttl')
            tasks.append(task)
        
        # Execute all requests concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        avalanche_results = {
            'scenario': 'cache_avalanche',
            'key': key,
            'concurrent_requests': concurrent_requests,
            'cache_misses': len([r for r in results if r is None]),
            'cache_hits': len([r for r in results if r is not None]),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Broadcast avalanche results
        await broadcast_update({
            'type': 'cache_avalanche_simulation',
            'results': avalanche_results
        })
        
        return avalanche_results
        
    except Exception as e:
        logger.error("Cache avalanche simulation error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/load-test/ttl-jitter")
async def test_ttl_jitter():
    """Test TTL jitter to prevent thundering herd"""
    try:
        results = []
        
        # Test multiple keys with TTL jitter
        for i in range(10):
            key = f"jitter_test_{i}"
            data = {'data': f'value_{i}', 'type': 'jitter_test'}
            
            # This will apply jitter automatically
            ttl_used = await cache_manager._ttl_strategy(key, data, 60)
            
            results.append({
                'key': key,
                'base_ttl': 60,
                'actual_ttl': ttl_used,
                'jitter_applied': ttl_used != 60
            })
        
        jitter_results = {
            'scenario': 'ttl_jitter_test',
            'total_keys': len(results),
            'keys_with_jitter': len([r for r in results if r['jitter_applied']]),
            'results': results,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Broadcast jitter results
        await broadcast_update({
            'type': 'ttl_jitter_test',
            'results': jitter_results
        })
        
        return jitter_results
        
    except Exception as e:
        logger.error("TTL jitter test error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/load-test/status")
async def get_load_test_status():
    """Get current load test status and metrics"""
    try:
        # Get current metrics
        current_metrics = await get_metrics()
        
        # Get Redis info for additional monitoring
        redis_info = await redis_client.info()
        
        status = {
            'timestamp': datetime.utcnow().isoformat(),
            'metrics': current_metrics,
            'redis_info': {
                'connected_clients': redis_info.get('connected_clients', 0),
                'used_memory': redis_info.get('used_memory_human', '0B'),
                'total_commands_processed': redis_info.get('total_commands_processed', 0),
                'keyspace_hits': redis_info.get('keyspace_hits', 0),
                'keyspace_misses': redis_info.get('keyspace_misses', 0)
            },
            'active_websocket_connections': len(active_connections)
        }
        
        return status
        
    except Exception as e:
        logger.error("Load test status error", error=str(e))
        return {'error': str(e)}

@app.post("/api/test/metrics-update")
async def test_metrics_update():
    """Test endpoint to verify metrics are being updated correctly"""
    try:
        # Get initial metrics
        initial_metrics = await get_metrics()
        
        # Perform some cache operations
        test_key = f"metrics_test_{int(time.time())}"
        test_data = {'test': 'data', 'timestamp': datetime.utcnow().isoformat()}
        
        # Set cache data
        await cache_manager._ttl_strategy(test_key, test_data, 60)
        
        # Get cache data (should be a hit)
        retrieved_data = await cache_manager.get_cache_data(test_key, 'ttl')
        
        # Try to get non-existent key (should be a miss)
        await cache_manager.get_cache_data('non_existent_key', 'ttl')
        
        # Get final metrics
        final_metrics = await get_metrics()
        
        test_results = {
            'initial_metrics': initial_metrics,
            'final_metrics': final_metrics,
            'test_operations': {
                'cache_set': True,
                'cache_hit': retrieved_data is not None,
                'cache_miss': True
            },
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return test_results
        
    except Exception as e:
        logger.error("Metrics test error", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    active_connections.append(websocket)
    
    try:
        while True:
            # Keep connection alive and handle incoming messages
            data = await websocket.receive_text()
            
            # Echo back for connection testing
            await websocket.send_text(json.dumps({
                'type': 'pong',
                'timestamp': datetime.utcnow().isoformat()
            }))
            
    except Exception as e:
        logger.info("WebSocket disconnected", error=str(e))
    finally:
        if websocket in active_connections:
            active_connections.remove(websocket)

async def broadcast_update(message: dict):
    """Broadcast update to all WebSocket connections"""
    if active_connections:
        disconnected = []
        
        for connection in active_connections:
            try:
                await connection.send_text(json.dumps(message))
            except:
                disconnected.append(connection)
                
        # Remove disconnected connections
        for conn in disconnected:
            active_connections.remove(conn)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        await redis_client.ping()
        return {
            'status': 'healthy',
            'redis_connected': True,
            'timestamp': datetime.utcnow().isoformat()
        }
    except:
        return {
            'status': 'unhealthy',
            'redis_connected': False,
            'timestamp': datetime.utcnow().isoformat()
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
