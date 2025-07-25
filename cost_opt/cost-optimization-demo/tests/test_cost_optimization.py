import pytest
import asyncio
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import CostTracker, ResourceMetrics

class TestCostTracker:
    def setup_method(self):
        """Set up test fixtures"""
        self.cost_tracker = CostTracker()
    
    def test_cost_tracker_initialization(self):
        """Test CostTracker initializes correctly"""
        assert self.cost_tracker.metrics_history == []
        assert len(self.cost_tracker.cost_per_hour) == 4
        assert len(self.cost_tracker.optimization_rules) == 3
    
    def test_get_current_metrics(self):
        """Test metrics collection"""
        metrics = self.cost_tracker.get_current_metrics()
        
        assert isinstance(metrics, ResourceMetrics)
        assert 0 <= metrics.cpu_usage <= 100
        assert 0 <= metrics.memory_usage <= 100
        assert metrics.network_io > 0
        assert metrics.disk_io > 0
        assert metrics.estimated_cost > 0
        assert len(self.cost_tracker.metrics_history) == 1
    
    def test_metrics_history_limit(self):
        """Test metrics history doesn't exceed limit"""
        # Generate more than 100 metrics
        for _ in range(105):
            self.cost_tracker.get_current_metrics()
        
        assert len(self.cost_tracker.metrics_history) == 100
    
    def test_optimization_recommendations(self):
        """Test optimization recommendations generation"""
        # Generate some metrics first
        for _ in range(10):
            self.cost_tracker.get_current_metrics()
        
        recommendations = self.cost_tracker.get_optimization_recommendations()
        
        assert isinstance(recommendations, list)
        assert len(recommendations) >= 2  # Should have at least storage and batch recommendations
        
        for rec in recommendations:
            assert hasattr(rec, 'type')
            assert hasattr(rec, 'description')
            assert hasattr(rec, 'potential_savings')
            assert hasattr(rec, 'implementation_effort')
    
    def test_projected_savings_calculation(self):
        """Test projected savings calculation"""
        # Generate some metrics
        for _ in range(30):
            self.cost_tracker.get_current_metrics()
        
        savings = self.cost_tracker.calculate_projected_savings()
        
        assert 'current_monthly_cost' in savings
        assert 'projected_savings' in savings
        assert 'savings_percentage' in savings
        assert savings['current_monthly_cost'] >= 0
        assert savings['projected_savings'] >= 0
        assert savings['savings_percentage'] >= 0

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
