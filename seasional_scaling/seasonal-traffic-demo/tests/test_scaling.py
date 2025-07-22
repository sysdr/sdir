"""
Tests for seasonal traffic scaling components
"""

import pytest
import asyncio
import time
from src.app import (
    PredictiveAutoScaler, 
    QueueManager, 
    CircuitBreaker, 
    TrafficScalingSystem,
    TrafficPattern
)

def test_predictive_autoscaler():
    """Test predictive auto-scaling logic"""
    scaler = PredictiveAutoScaler()
    
    # Test with no historical data
    prediction = scaler.predict_next_rps(100)
    assert prediction >= 0
    
    # Add some historical data
    base_time = time.time()
    for i in range(20):
        scaler.add_data_point(100 + i * 5, base_time + i)
    
    # Test prediction with trend
    prediction = scaler.predict_next_rps(200)
    assert prediction > 200  # Should predict upward trend
    
    # Test instance calculation
    instances = scaler.calculate_target_instances(600)
    assert instances >= scaler.min_instances
    assert instances <= scaler.max_instances

def test_queue_manager():
    """Test queue management functionality"""
    queue_mgr = QueueManager()
    
    # Test adding requests
    assert queue_mgr.add_request(1, "req1") == True
    assert queue_mgr.add_request(2, "req2") == True
    
    # Test queue processing
    processed = queue_mgr.process_requests(100)
    assert processed >= 0

def test_circuit_breaker():
    """Test circuit breaker state transitions"""
    cb = CircuitBreaker()
    
    # Test initial state
    assert cb.state == "closed"
    assert cb.can_execute() == True
    
    # Test failure threshold
    for i in range(cb.failure_threshold + 1):
        cb.call_failure()
    
    assert cb.state == "open"
    assert cb.can_execute() == False
    
    # Test recovery after timeout
    cb.last_failure_time = time.time() - cb.timeout - 1
    assert cb.can_execute() == True
    assert cb.state == "half-open"

def test_traffic_scaling_system():
    """Test integrated scaling system"""
    system = TrafficScalingSystem()
    
    # Test initial state
    assert system.active_instances == 3
    assert system.success_rate == 100.0
    
    # Test metrics update
    metrics = system.update_metrics()
    assert metrics.active_instances >= 3
    assert 0 <= metrics.success_rate <= 100

@pytest.mark.asyncio
async def test_request_handling():
    """Test request handling with protection mechanisms"""
    system = TrafficScalingSystem()
    
    # Test successful request
    result = await system.handle_request()
    assert isinstance(result, bool)

def test_traffic_patterns():
    """Test traffic pattern definitions"""
    pattern = TrafficPattern("Test", 60, 500, "spike")
    
    assert pattern.name == "Test"
    assert pattern.duration_seconds == 60
    assert pattern.peak_rps == 500
    assert pattern.pattern_type == "spike"

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
