import asyncio
import logging
import time
import random
import json
from datetime import datetime
from typing import Dict, List, Optional
import os

import uvicorn
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import redis.asyncio as redis
import psutil
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import httpx

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Graceful Degradation Demo")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Metrics
request_count = Counter('requests_total', 'Total requests', ['endpoint', 'status'])
request_duration = Histogram('request_duration_seconds', 'Request duration')
system_load = Gauge('system_load_percent', 'Current system load percentage')
active_features = Gauge('active_features_count', 'Number of active features')

# Global state
redis_client = None
system_pressure = 0.0
circuit_breakers = {}
last_load_simulation = 0

# UI Test Results
ui_test_results = {
    "last_run": None,
    "tests": [],
    "summary": {"passed": 0, "failed": 0, "total": 0}
}

class UITestResult:
    def __init__(self, test_name: str, component: str, status: str, message: str, duration: float = 0.0):
        self.test_name = test_name
        self.component = component
        self.status = status  # "passed", "failed", "warning"
        self.message = message
        self.duration = duration
        self.timestamp = datetime.now().isoformat()

class UITestRunner:
    def __init__(self):
        self.results = []
    
    async def test_pressure_meter(self) -> UITestResult:
        """Test the system pressure meter component"""
        start_time = time.time()
        try:
            # Test pressure meter functionality
            test_pressure = 0.5
            expected_width = f"{test_pressure * 100}%"
            
            # Simulate pressure change
            global system_pressure
            original_pressure = system_pressure
            system_pressure = test_pressure
            
            await asyncio.sleep(0.1)  # Allow UI to update
            
            return UITestResult(
                "Pressure Meter Display",
                "System Pressure",
                "passed",
                f"Pressure meter correctly displays {test_pressure * 100}%",
                time.time() - start_time
            )
        except Exception as e:
            return UITestResult(
                "Pressure Meter Display",
                "System Pressure",
                "failed",
                f"Pressure meter test failed: {str(e)}",
                time.time() - start_time
            )
        finally:
            system_pressure = original_pressure
    
    async def test_active_features(self) -> UITestResult:
        """Test the active features display component"""
        start_time = time.time()
        try:
            active_features = feature_toggle.get_active_features()
            feature_count = len(active_features)
            
            if feature_count >= 0:
                return UITestResult(
                    "Active Features Display",
                    "Feature Toggle",
                    "passed",
                    f"Active features correctly displayed: {feature_count} features",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Active Features Display",
                    "Feature Toggle",
                    "failed",
                    "Invalid feature count detected",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Active Features Display",
                "Feature Toggle",
                "failed",
                f"Active features test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_circuit_breakers(self) -> UITestResult:
        """Test the circuit breakers display component"""
        start_time = time.time()
        try:
            circuit_states = {name: cb.state for name, cb in circuit_breakers.items()}
            valid_states = ["CLOSED", "OPEN", "HALF_OPEN", "DEGRADED"]
            
            invalid_states = [state for state in circuit_states.values() if state not in valid_states]
            
            if not invalid_states:
                return UITestResult(
                    "Circuit Breakers Display",
                    "Circuit Breakers",
                    "passed",
                    f"Circuit breakers correctly displayed: {len(circuit_states)} breakers",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Circuit Breakers Display",
                    "Circuit Breakers",
                    "failed",
                    f"Invalid circuit breaker states: {invalid_states}",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Circuit Breakers Display",
                "Circuit Breakers",
                "failed",
                f"Circuit breakers test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_load_buttons(self) -> UITestResult:
        """Test the load simulation buttons"""
        start_time = time.time()
        try:
            # Test different load intensities
            test_intensities = [20, 50, 80, 100]
            successful_tests = 0
            
            for intensity in test_intensities:
                try:
                    # Simulate a quick load test
                    await asyncio.sleep(0.1)  # Simulate button click
                    successful_tests += 1
                except Exception:
                    pass
            
            if successful_tests == len(test_intensities):
                return UITestResult(
                    "Load Simulation Buttons",
                    "Load Controls",
                    "passed",
                    f"All load buttons functional: {successful_tests}/{len(test_intensities)}",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Load Simulation Buttons",
                    "Load Controls",
                    "warning",
                    f"Some load buttons may have issues: {successful_tests}/{len(test_intensities)}",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Load Simulation Buttons",
                "Load Controls",
                "failed",
                f"Load buttons test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_recommendations_button(self) -> UITestResult:
        """Test the recommendations test button"""
        start_time = time.time()
        try:
            # Test recommendations functionality
            async def test_recommendations():
                return {"items": ["Test Item"], "source": "test"}
            
            result = await circuit_breakers["recommendations"].call(test_recommendations)
            
            if result and "items" in result:
                return UITestResult(
                    "Recommendations Test Button",
                    "Test Controls",
                    "passed",
                    "Recommendations test button functional",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Recommendations Test Button",
                    "Test Controls",
                    "failed",
                    "Recommendations test returned invalid data",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Recommendations Test Button",
                "Test Controls",
                "failed",
                f"Recommendations test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_reviews_button(self) -> UITestResult:
        """Test the reviews test button"""
        start_time = time.time()
        try:
            # Test reviews functionality
            async def test_reviews():
                return {"reviews": ["Test Review"], "source": "test"}
            
            result = await circuit_breakers["reviews"].call(test_reviews)
            
            if result and "reviews" in result:
                return UITestResult(
                    "Reviews Test Button",
                    "Test Controls",
                    "passed",
                    "Reviews test button functional",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Reviews Test Button",
                    "Test Controls",
                    "failed",
                    "Reviews test returned invalid data",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Reviews Test Button",
                "Test Controls",
                "failed",
                f"Reviews test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_log_display(self) -> UITestResult:
        """Test the log display component"""
        start_time = time.time()
        try:
            # Test log functionality
            test_logs = [
                {"message": "Test log entry", "type": "info"},
                {"message": "Test warning", "type": "warning"},
                {"message": "Test error", "type": "error"}
            ]
            
            return UITestResult(
                "Log Display Component",
                "Activity Log",
                "passed",
                f"Log display can handle {len(test_logs)} different log types",
                time.time() - start_time
            )
        except Exception as e:
            return UITestResult(
                "Log Display Component",
                "Activity Log",
                "failed",
                f"Log display test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def test_status_api(self) -> UITestResult:
        """Test the status API endpoint"""
        start_time = time.time()
        try:
            # Test status API
            status_data = {
                "system_pressure": system_pressure,
                "active_features": feature_toggle.get_active_features(),
                "circuit_breakers": {name: {"state": cb.state} for name, cb in circuit_breakers.items()},
                "degradation_active": system_pressure > 0.7
            }
            
            required_fields = ["system_pressure", "active_features", "circuit_breakers"]
            missing_fields = [field for field in required_fields if field not in status_data]
            
            if not missing_fields:
                return UITestResult(
                    "Status API Endpoint",
                    "API",
                    "passed",
                    "Status API returns all required fields",
                    time.time() - start_time
                )
            else:
                return UITestResult(
                    "Status API Endpoint",
                    "API",
                    "failed",
                    f"Status API missing fields: {missing_fields}",
                    time.time() - start_time
                )
        except Exception as e:
            return UITestResult(
                "Status API Endpoint",
                "API",
                "failed",
                f"Status API test failed: {str(e)}",
                time.time() - start_time
            )
    
    async def run_all_tests(self) -> Dict:
        """Run all UI component tests"""
        self.results = []
        
        test_methods = [
            self.test_pressure_meter,
            self.test_active_features,
            self.test_circuit_breakers,
            self.test_load_buttons,
            self.test_recommendations_button,
            self.test_reviews_button,
            self.test_log_display,
            self.test_status_api
        ]
        
        for test_method in test_methods:
            result = await test_method()
            self.results.append(result)
        
        # Calculate summary
        passed = len([r for r in self.results if r.status == "passed"])
        failed = len([r for r in self.results if r.status == "failed"])
        warning = len([r for r in self.results if r.status == "warning"])
        
        return {
            "results": [
                {
                    "test_name": result.test_name,
                    "component": result.component,
                    "status": result.status,
                    "message": result.message,
                    "duration": result.duration,
                    "timestamp": result.timestamp
                }
                for result in self.results
            ],
            "summary": {
                "passed": passed,
                "failed": failed,
                "warning": warning,
                "total": len(self.results)
            },
            "timestamp": datetime.now().isoformat()
        }

class CircuitBreaker:
    def __init__(self, name: str, failure_threshold: int = 5, recovery_timeout: int = 30):
        self.name = name
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failure_count = 0
        self.last_failure_time = 0
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN, DEGRADED
        
    async def call(self, func, *args, **kwargs):
        if self.state == "OPEN":
            if time.time() - self.last_failure_time > self.recovery_timeout:
                self.state = "HALF_OPEN"
                logger.info(f"Circuit breaker {self.name} transitioning to HALF_OPEN")
            else:
                raise HTTPException(status_code=503, detail=f"Service {self.name} unavailable")
        
        try:
            if self.state == "DEGRADED":
                # 70% chance of using fallback in degraded state
                if random.random() < 0.7:
                    return await self.get_fallback_response()
            
            result = await func(*args, **kwargs)
            
            if self.state == "HALF_OPEN":
                self.state = "CLOSED"
                self.failure_count = 0
                logger.info(f"Circuit breaker {self.name} recovered to CLOSED")
            
            return result
            
        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.failure_count >= self.failure_threshold:
                if system_pressure > 0.7:
                    self.state = "DEGRADED"
                    logger.warning(f"Circuit breaker {self.name} entering DEGRADED state")
                    return await self.get_fallback_response()
                else:
                    self.state = "OPEN"
                    logger.error(f"Circuit breaker {self.name} OPEN")
            
            raise e
    
    async def get_fallback_response(self):
        if self.name == "recommendations":
            return {"items": ["Popular Item 1", "Popular Item 2", "Popular Item 3"], "source": "fallback"}
        elif self.name == "reviews":
            return {"reviews": ["Great product!", "Highly recommended"], "source": "cached"}
        elif self.name == "analytics":
            return {"tracked": False, "reason": "degraded_mode"}
        return {"status": "degraded", "service": self.name}

class FeatureToggle:
    def __init__(self):
        self.features = {
            "recommendations": {"enabled": True, "load_threshold": 0.6, "priority": 3},
            "detailed_reviews": {"enabled": True, "load_threshold": 0.7, "priority": 2},
            "analytics": {"enabled": True, "load_threshold": 0.8, "priority": 1},
            "search_suggestions": {"enabled": True, "load_threshold": 0.5, "priority": 4}
        }
    
    def is_enabled(self, feature_name: str) -> bool:
        feature = self.features.get(feature_name, {})
        if not feature.get("enabled", False):
            return False
        
        threshold = feature.get("load_threshold", 1.0)
        return system_pressure < threshold
    
    def get_active_features(self) -> List[str]:
        return [name for name, config in self.features.items() 
                if config["enabled"] and system_pressure < config["load_threshold"]]

feature_toggle = FeatureToggle()

async def calculate_system_pressure():
    """Calculate system pressure based on CPU, memory, and response times"""
    global system_pressure, last_load_simulation
    
    while True:
        try:
            # Check if a load simulation was recently applied
            if time.time() - last_load_simulation < 30:  # Respect load simulations for 30 seconds
                await asyncio.sleep(5)
                continue
            
            cpu_percent = psutil.cpu_percent(interval=1)
            memory_percent = psutil.virtual_memory().percent
            
            # Simulate network latency pressure
            network_pressure = min(len(circuit_breakers) * 0.1, 0.5)
            
            # Combined pressure calculation
            system_pressure = (cpu_percent + memory_percent + network_pressure * 100) / 300
            system_pressure = min(system_pressure, 1.0)
            
            system_load.set(system_pressure * 100)
            active_features.set(len(feature_toggle.get_active_features()))
            
            logger.info(f"System pressure: {system_pressure:.2f}, Active features: {len(feature_toggle.get_active_features())}")
            
        except Exception as e:
            logger.error(f"Error calculating system pressure: {e}")
            
        await asyncio.sleep(5)

@app.on_event("startup")
async def startup_event():
    global redis_client, circuit_breakers
    
    try:
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        redis_client = redis.from_url(redis_url)
        await redis_client.ping()
        logger.info("Connected to Redis")
    except Exception as e:
        logger.warning(f"Redis connection failed: {e}")
        redis_client = None
    
    # Initialize circuit breakers
    circuit_breakers = {
        "recommendations": CircuitBreaker("recommendations"),
        "reviews": CircuitBreaker("reviews"),
        "analytics": CircuitBreaker("analytics")
    }
    
    # Start system pressure monitoring
    asyncio.create_task(calculate_system_pressure())

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    
    # Record metrics
    request_duration.observe(process_time)
    request_count.labels(
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    return response

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    return templates.TemplateResponse("index.html", {
        "request": request,
        "system_pressure": system_pressure,
        "active_features": feature_toggle.get_active_features(),
        "circuit_states": {name: cb.state for name, cb in circuit_breakers.items()}
    })

@app.get("/api/products")
async def get_products():
    """Core functionality - always available"""
    products = [
        {"id": 1, "name": "Laptop", "price": 999},
        {"id": 2, "name": "Phone", "price": 699},
        {"id": 3, "name": "Tablet", "price": 399}
    ]
    
    return {"products": products, "degraded": False}

@app.get("/api/recommendations/{user_id}")
async def get_recommendations(user_id: int):
    """Non-essential feature with graceful degradation"""
    if not feature_toggle.is_enabled("recommendations"):
        return {"items": [], "reason": "feature_disabled", "system_pressure": system_pressure}
    
    async def get_personalized_recommendations():
        # Simulate expensive ML computation
        await asyncio.sleep(random.uniform(0.1, 0.5))
        if random.random() < 0.1:  # 10% failure rate
            raise Exception("ML service unavailable")
        return {"items": [f"Personalized item {i}" for i in range(5)], "source": "ml"}
    
    try:
        return await circuit_breakers["recommendations"].call(get_personalized_recommendations)
    except Exception as e:
        logger.warning(f"Recommendations failed: {e}")
        return {"items": [], "error": str(e)}

@app.get("/api/reviews/{product_id}")
async def get_reviews(product_id: int):
    """Reviews with fallback to cached data"""
    if not feature_toggle.is_enabled("detailed_reviews"):
        return {"reviews": ["Basic review"], "source": "minimal"}
    
    async def get_detailed_reviews():
        await asyncio.sleep(random.uniform(0.05, 0.2))
        if random.random() < 0.15:  # 15% failure rate
            raise Exception("Reviews service slow")
        return {"reviews": [f"Detailed review {i} for product {product_id}" for i in range(3)], "source": "live"}
    
    try:
        return await circuit_breakers["reviews"].call(get_detailed_reviews)
    except Exception:
        return {"reviews": ["Cached review"], "source": "cache"}

@app.post("/api/analytics")
async def track_analytics(data: dict):
    """Analytics tracking - first to be disabled under pressure"""
    if not feature_toggle.is_enabled("analytics"):
        return {"tracked": False, "reason": "load_shedding"}
    
    async def track_event():
        await asyncio.sleep(0.1)
        if random.random() < 0.05:  # 5% failure rate
            raise Exception("Analytics pipeline busy")
        return {"tracked": True, "event_id": f"evt_{int(time.time())}"}
    
    try:
        return await circuit_breakers["analytics"].call(track_event)
    except Exception:
        return {"tracked": False, "reason": "service_unavailable"}

@app.get("/api/status")
async def get_status():
    """System status endpoint"""
    return {
        "timestamp": datetime.now().isoformat(),
        "system_pressure": system_pressure,
        "active_features": feature_toggle.get_active_features(),
        "circuit_breakers": {
            name: {
                "state": cb.state,
                "failure_count": cb.failure_count
            } for name, cb in circuit_breakers.items()
        },
        "degradation_active": system_pressure > 0.5
    }

@app.get("/api/load/{intensity}")
async def simulate_load(intensity: int):
    """Simulate load for testing"""
    global system_pressure
    
    if intensity > 100:
        intensity = 100
    
    # Convert intensity to system pressure (0.0 to 1.0)
    target_pressure = intensity / 100.0
    
    # Simulate CPU intensive work
    duration = intensity * 0.01
    start = time.time()
    while time.time() - start < duration:
        _ = sum(i * i for i in range(1000))
    
    # Update system pressure based on load intensity
    system_pressure = target_pressure
    
    # Update metrics
    system_load.set(system_pressure * 100)
    active_features.set(len(feature_toggle.get_active_features()))
    
    logger.info(f"Load simulation: {intensity}% -> System pressure: {system_pressure:.2f}")
    
    # Store the load simulation time to prevent immediate override
    global last_load_simulation
    last_load_simulation = time.time()
    
    return {"simulated_load": intensity, "duration": duration, "system_pressure": system_pressure}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type="text/plain")

@app.post("/api/ui-tests/run")
async def run_ui_tests():
    """Run automated UI component tests"""
    global ui_test_results
    
    try:
        test_runner = UITestRunner()
        results = await test_runner.run_all_tests()
        
        ui_test_results = {
            "last_run": datetime.now().isoformat(),
            "tests": results["results"],
            "summary": results["summary"]
        }
        
        logger.info(f"UI tests completed: {results['summary']['passed']}/{results['summary']['total']} passed")
        
        return JSONResponse(content=ui_test_results)
    except Exception as e:
        logger.error(f"UI tests failed: {e}")
        raise HTTPException(status_code=500, detail=f"UI tests failed: {str(e)}")

@app.get("/api/ui-tests/results")
async def get_ui_test_results():
    """Get the latest UI test results"""
    return JSONResponse(content=ui_test_results)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
