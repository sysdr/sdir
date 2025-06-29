import pytest
import asyncio
import sys
import os

# Add the app directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from main import GlobalLoadBalancer, RegionStatus, CircuitBreakerState

class TestGlobalLoadBalancer:
    def setup_method(self):
        self.glb = GlobalLoadBalancer()
    
    def test_region_initialization(self):
        """Test that regions are properly initialized"""
        assert len(self.glb.regions) == 5
        assert "us-west" in self.glb.regions
        assert "asia-southeast" in self.glb.regions
        
        us_west = self.glb.regions["us-west"]
        assert us_west.status == RegionStatus.HEALTHY
        assert us_west.latency_base == 25
        assert us_west.location == "San Francisco"
    
    def test_circuit_breaker_initialization(self):
        """Test that circuit breakers are properly initialized"""
        assert len(self.glb.circuit_breakers) == 5
        
        for cb in self.glb.circuit_breakers.values():
            assert cb.state == CircuitBreakerState.CLOSED
            assert cb.failure_count == 0
            assert cb.success_count == 0
    
    def test_latency_calculation(self):
        """Test latency calculation between regions"""
        latency = self.glb.calculate_latency("us-west", "us-east")
        assert latency > 0
        assert latency != float('inf')
        
        # Test failed region
        self.glb.regions["us-east"].status = RegionStatus.FAILED
        latency = self.glb.calculate_latency("us-west", "us-east")
        assert latency == float('inf')
    
    def test_best_region_selection(self):
        """Test that the best region is selected correctly"""
        best = self.glb.get_best_region("us-west")
        assert best in self.glb.regions
        
        # Fail all regions except one
        for name in ["us-east", "eu-west", "asia-southeast", "asia-northeast"]:
            self.glb.regions[name].status = RegionStatus.FAILED
        
        best = self.glb.get_best_region("us-west")
        assert best == "us-west"
    
    def test_request_handling(self):
        """Test request handling and circuit breaker logic"""
        result = self.glb.handle_request("us-west")
        
        assert "success" in result
        assert "region" in result
        assert "latency" in result
        assert "circuit_breaker_state" in result
        assert result["region"] == "us-west"
    
    def test_circuit_breaker_failure_threshold(self):
        """Test that circuit breaker opens after failure threshold"""
        region_name = "us-west"
        self.glb.regions[region_name].status = RegionStatus.FAILED
        
        # Trigger enough failures to open circuit breaker
        for _ in range(6):
            self.glb.handle_request(region_name)
        
        cb = self.glb.circuit_breakers[region_name]
        assert cb.state == CircuitBreakerState.OPEN
        assert cb.failure_count >= 5
    
    def test_data_replication(self):
        """Test data replication between regions"""
        test_data = {"user_id": 123, "action": "update"}
        result = self.glb.replicate_data("us-west", test_data)
        
        assert result["source"] == "us-west"
        assert result["data"] == test_data
        assert len(result["replicated_to"]) == 4  # All other regions
        
        # Check that replication log is updated
        assert len(self.glb.replication_log) == 1
    
    def test_degraded_region_behavior(self):
        """Test behavior with degraded regions"""
        self.glb.regions["us-west"].status = RegionStatus.DEGRADED
        
        # Multiple requests to see failure pattern
        results = []
        for _ in range(10):
            result = self.glb.handle_request("us-west")
            results.append(result["success"])
        
        # Should have some failures but not all
        failures = sum(1 for success in results if not success)
        assert 0 < failures < 10

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
