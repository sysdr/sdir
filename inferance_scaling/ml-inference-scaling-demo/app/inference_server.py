"""
Production-grade ML Inference Server with Dynamic Batching
Demonstrates scaling patterns for high-throughput ML serving
"""
import asyncio
import time
import logging
import json
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor
import uvicorn
from fastapi import FastAPI, HTTPException, BackgroundTasks, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import torch
import numpy as np
from transformers import pipeline, AutoTokenizer, AutoModel
import redis
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import psutil
import threading
import queue
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Metrics - with registry cleanup to avoid duplicates
from prometheus_client import REGISTRY

# Clear any existing metrics to avoid duplicates
for metric_name in list(REGISTRY._names_to_collectors.keys()):
    if metric_name.startswith('ml_inference_'):
        try:
            REGISTRY.unregister(REGISTRY._names_to_collectors[metric_name])
        except KeyError:
            # Metric might have been already unregistered
            pass

# Initialize metrics
REQUEST_COUNT = Counter('ml_inference_requests_total', 'Total inference requests')
INFERENCE_DURATION = Histogram('ml_inference_duration_seconds', 'Time spent on inference')
BATCH_SIZE_GAUGE = Gauge('ml_inference_batch_size', 'Current batch size')
GPU_MEMORY = Gauge('ml_inference_gpu_memory_mb', 'GPU memory usage')
CPU_USAGE = Gauge('ml_inference_cpu_percent', 'CPU usage percentage')

@dataclass
class InferenceRequest:
    id: str
    text: str
    timestamp: float
    priority: int = 1
    
@dataclass
class BatchConfig:
    max_batch_size: int = 32
    max_wait_time: float = 0.1
    min_batch_size: int = 1
    adaptive: bool = True

class ModelManager:
    """Manages model loading, caching, and inference operations"""
    
    def __init__(self):
        self.models = {}
        self.model_cache = {}
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Using device: {self.device}")
        
    def load_sentiment_model(self):
        """Load and cache sentiment analysis model"""
        if 'sentiment' not in self.models:
            logger.info("Loading sentiment analysis model...")
            # For demo purposes, use dummy model to start quickly
            # In production, you would load a real model here
            logger.info("Using dummy sentiment model for demo")
            self.models['sentiment'] = self._create_dummy_sentiment_model()
                
    def _create_dummy_sentiment_model(self):
        """Create a dummy sentiment model for demo purposes"""
        class DummySentimentModel:
            def __call__(self, texts):
                results = []
                for text in texts:
                    # Simple rule-based sentiment for demo
                    score = np.random.random()
                    label = "POSITIVE" if score > 0.5 else "NEGATIVE"
                    results.append({"label": label, "score": score})
                return results
        return DummySentimentModel()
        
    def load_text_generation_model(self):
        """Load text generation model with proper error handling"""
        if 'generation' not in self.models:
            logger.info("Loading text generation model...")
            # For demo purposes, use dummy model to start quickly
            # In production, you would load a real model here
            logger.info("Using dummy text generation model for demo")
            self.models['generation'] = self._create_dummy_generation_model()
                
    def _create_dummy_generation_model(self):
        """Create a dummy text generation model"""
        class DummyGenerationModel:
            def __call__(self, texts, **kwargs):
                results = []
                for text in texts:
                    generated = f"{text} [Generated continuation with {len(text)} chars input]"
                    results.append([{"generated_text": generated}])
                return results
        return DummyGenerationModel()

class DynamicBatcher:
    """Implements dynamic batching with adaptive batch sizing"""
    
    def __init__(self, config: BatchConfig):
        self.config = config
        self.request_queue = queue.Queue()
        self.response_futures = {}
        self.current_load = 0
        self.avg_processing_time = 0.1
        self.batch_thread = None
        self.running = False
        
    def start(self):
        """Start the batching process"""
        self.running = True
        self.batch_thread = threading.Thread(target=self._batch_processor)
        self.batch_thread.daemon = True
        self.batch_thread.start()
        logger.info("Dynamic batcher started")
        
    def stop(self):
        """Stop the batching process"""
        self.running = False
        if self.batch_thread:
            self.batch_thread.join(timeout=5)
            
    def add_request(self, request: InferenceRequest) -> asyncio.Future:
        """Add a request to the batch queue"""
        future = asyncio.Future()
        self.request_queue.put((request, future))
        self.response_futures[request.id] = future
        return future
        
    def _calculate_optimal_batch_size(self) -> int:
        """Calculate optimal batch size based on current load"""
        if not self.config.adaptive:
            return self.config.max_batch_size
            
        # Adaptive sizing based on queue length and processing time
        queue_size = self.request_queue.qsize()
        
        if queue_size < 5:
            return min(queue_size, self.config.min_batch_size)
        elif queue_size < 20:
            return min(queue_size, self.config.max_batch_size // 2)
        else:
            return self.config.max_batch_size
            
    def _batch_processor(self):
        """Main batch processing loop"""
        while self.running:
            batch_requests = []
            batch_futures = []
            batch_size = self._calculate_optimal_batch_size()
            
            # Collect requests for batching
            start_wait = time.time()
            while (len(batch_requests) < batch_size and 
                   time.time() - start_wait < self.config.max_wait_time):
                try:
                    request, future = self.request_queue.get(timeout=0.01)
                    batch_requests.append(request)
                    batch_futures.append(future)
                except queue.Empty:
                    break
                    
            if batch_requests:
                BATCH_SIZE_GAUGE.set(len(batch_requests))
                self._process_batch(batch_requests, batch_futures)
            else:
                time.sleep(0.001)  # Small sleep to prevent CPU spinning
                
    def _process_batch(self, requests: List[InferenceRequest], 
                      futures: List[asyncio.Future]):
        """Process a batch of requests"""
        start_time = time.time()
        
        try:
            # Extract texts for batch processing
            texts = [req.text for req in requests]
            
            # Simulate batch inference (replace with actual model call)
            results = self._simulate_batch_inference(texts)
            
            # Send results back to waiting coroutines
            for future, result in zip(futures, results):
                if not future.done():
                    future.get_loop().call_soon_threadsafe(
                        future.set_result, result
                    )
                    
        except Exception as e:
            logger.error(f"Batch processing error: {e}")
            for future in futures:
                if not future.done():
                    future.get_loop().call_soon_threadsafe(
                        future.set_exception, e
                    )
                    
        finally:
            processing_time = time.time() - start_time
            self.avg_processing_time = (
                0.9 * self.avg_processing_time + 0.1 * processing_time
            )
            INFERENCE_DURATION.observe(processing_time)
            
    def _simulate_batch_inference(self, texts: List[str]) -> List[Dict]:
        """Simulate batch inference processing"""
        # Simulate GPU computation time
        processing_time = 0.05 + len(texts) * 0.001
        time.sleep(processing_time)
        
        results = []
        for text in texts:
            # Simulate sentiment analysis results
            sentiment_score = np.random.random()
            result = {
                "text": text,
                "sentiment": "positive" if sentiment_score > 0.5 else "negative",
                "confidence": float(sentiment_score),
                "processing_time": processing_time / len(texts)
            }
            results.append(result)
            
        return results

class InferenceService:
    """Main inference service orchestrating models and batching"""
    
    def __init__(self):
        self.model_manager = ModelManager()
        self.redis_client = None
        self.batcher = DynamicBatcher(BatchConfig())
        self.stats = {
            "requests_processed": 0,
            "total_latency": 0,
            "avg_latency": 0
        }
        
    async def initialize(self):
        """Initialize all components"""
        logger.info("Initializing inference service...")
        
        # Initialize Redis connection
        try:
            self.redis_client = redis.Redis(
                host=os.getenv('REDIS_HOST', 'localhost'),
                port=6379,
                decode_responses=True
            )
            await asyncio.to_thread(self.redis_client.ping)
            logger.info("Redis connected successfully")
        except Exception as e:
            logger.warning(f"Redis connection failed: {e}")
            self.redis_client = None
            
        # Load models
        await asyncio.to_thread(self.model_manager.load_sentiment_model)
        
        # Start batching system
        self.batcher.start()
        
        logger.info("Inference service initialized successfully")
        
    async def predict(self, text: str, request_id: str) -> Dict[str, Any]:
        """Main prediction endpoint with caching and batching"""
        start_time = time.time()
        REQUEST_COUNT.inc()
        
        # Check cache first
        cache_key = f"prediction:{hash(text)}"
        if self.redis_client:
            try:
                cached_result = self.redis_client.get(cache_key)
                if cached_result:
                    logger.info(f"Cache hit for request {request_id}")
                    return json.loads(cached_result)
            except Exception as e:
                logger.warning(f"Cache read error: {e}")
                
        # Create inference request
        request = InferenceRequest(
            id=request_id,
            text=text,
            timestamp=start_time
        )
        
        # Add to batch queue and wait for result
        try:
            future = self.batcher.add_request(request)
            result = await asyncio.wait_for(future, timeout=30.0)
            
            # Cache the result
            if self.redis_client:
                try:
                    self.redis_client.setex(
                        cache_key, 
                        300,  # 5 minutes TTL
                        json.dumps(result)
                    )
                except Exception as e:
                    logger.warning(f"Cache write error: {e}")
                    
            # Update stats
            latency = time.time() - start_time
            self.stats["requests_processed"] += 1
            self.stats["total_latency"] += latency
            self.stats["avg_latency"] = (
                self.stats["total_latency"] / self.stats["requests_processed"]
            )
            
            result["request_id"] = request_id
            result["latency"] = latency
            return result
            
        except asyncio.TimeoutError:
            raise HTTPException(status_code=504, detail="Request timeout")
        except Exception as e:
            logger.error(f"Prediction error: {e}")
            raise HTTPException(status_code=500, detail=str(e))

# Initialize FastAPI app
app = FastAPI(title="ML Inference Scaling Demo", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize inference service
inference_service = InferenceService()

@app.on_event("startup")
async def startup_event():
    await inference_service.initialize()
    
@app.on_event("shutdown")
async def shutdown_event():
    inference_service.batcher.stop()

@app.post("/predict")
async def predict_endpoint(request: Dict[str, Any]):
    """Main prediction endpoint"""
    text = request.get("text", "")
    request_id = request.get("id", f"req_{int(time.time() * 1000)}")
    
    if not text:
        raise HTTPException(status_code=400, detail="Text is required")
        
    result = await inference_service.predict(text, request_id)
    return result

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": time.time(),
        "stats": inference_service.stats
    }

@app.get("/metrics")
async def metrics_endpoint():
    """Prometheus metrics endpoint"""
    # Update system metrics
    CPU_USAGE.set(psutil.cpu_percent())
    
    if torch.cuda.is_available():
        try:
            GPU_MEMORY.set(torch.cuda.memory_allocated() / 1024 / 1024)
        except:
            pass
            
    return generate_latest()

@app.get("/stats")
async def get_stats():
    """Get detailed system statistics"""
    return {
        "service_stats": inference_service.stats,
        "batch_config": asdict(inference_service.batcher.config),
        "queue_size": inference_service.batcher.request_queue.qsize(),
        "system": {
            "cpu_percent": psutil.cpu_percent(),
            "memory_percent": psutil.virtual_memory().percent,
            "gpu_available": torch.cuda.is_available()
        }
    }

# Mount static files for frontend
app.mount("/static", StaticFiles(directory="frontend"), name="static")

@app.get("/", response_class=HTMLResponse)
async def read_root():
    """Serve the main application page"""
    with open("frontend/index.html", "r") as f:
        return HTMLResponse(content=f.read())

if __name__ == "__main__":
    uvicorn.run(
        "inference_server:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        workers=1
    )
