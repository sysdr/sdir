"""Tests for partition analysis functionality."""

import pytest
import math
from datetime import datetime
from src.models.partition import PartitionMetrics, PartitionAnalyzer

class TestPartitionAnalyzer:
    
    def test_entropy_calculation_perfect_balance(self):
        """Test entropy calculation with perfect load balance."""
        analyzer = PartitionAnalyzer()
        loads = [100, 100, 100, 100, 100]  # Perfect balance
        entropy = analyzer.calculate_entropy(loads)
        assert abs(entropy - 1.0) < 0.001  # Should be close to 1.0
    
    def test_entropy_calculation_complete_skew(self):
        """Test entropy calculation with complete skew."""
        analyzer = PartitionAnalyzer()
        loads = [500, 0, 0, 0, 0]  # Complete skew
        entropy = analyzer.calculate_entropy(loads)
        assert abs(entropy - 0.0) < 0.001  # Should be close to 0.0
    
    def test_entropy_calculation_moderate_skew(self):
        """Test entropy calculation with moderate skew."""
        analyzer = PartitionAnalyzer()
        loads = [300, 100, 100, 100, 100]  # Moderate skew
        entropy = analyzer.calculate_entropy(loads)
        assert 0.7 < entropy < 0.9  # Should be between thresholds
    
    def test_entropy_calculation_critical_skew(self):
        """Test entropy calculation with critical skew."""
        analyzer = PartitionAnalyzer()
        loads = [650, 100, 50, 50, 50]  # Critical skew
        entropy = analyzer.calculate_entropy(loads)
        assert entropy < 0.7  # Should be below critical threshold
    
    def test_alert_generation_critical(self):
        """Test alert generation for critical hotspot."""
        analyzer = PartitionAnalyzer()
        
        metrics = PartitionMetrics(
            partition_id="partition_0",
            request_count=5000,  # Very high load
            memory_usage_mb=800,
            cpu_usage_percent=95,
            avg_response_time_ms=2000
        )
        
        entropy_score = 0.3  # Critical entropy
        temporal_analysis = {"trend": "accelerating", "acceleration": 50.0}
        
        alert = analyzer.generate_alert(
            "partition_0", metrics, entropy_score, temporal_analysis
        )
        
        assert alert is not None
        assert alert.severity == "CRITICAL"
        assert "Accelerating" in alert.recommended_action
    
    def test_alert_generation_normal(self):
        """Test no alert generation for normal conditions."""
        analyzer = PartitionAnalyzer()
        
        metrics = PartitionMetrics(
            partition_id="partition_0",
            request_count=200,  # Normal load
            memory_usage_mb=150,
            cpu_usage_percent=25,
            avg_response_time_ms=100
        )
        
        entropy_score = 0.9  # Good entropy
        temporal_analysis = {"trend": "stable", "acceleration": 0.0}
        
        alert = analyzer.generate_alert(
            "partition_0", metrics, entropy_score, temporal_analysis
        )
        
        assert alert is None
    
    def test_temporal_pattern_detection(self):
        """Test temporal pattern detection."""
        analyzer = PartitionAnalyzer()
        
        # Add historical metrics showing acceleration
        base_time = datetime.now()
        for i in range(10):
            metrics = PartitionMetrics(
                partition_id="partition_0",
                request_count=100 + i * 50,  # Increasing load
                memory_usage_mb=100 + i * 10,
                cpu_usage_percent=20 + i * 5,
                avg_response_time_ms=100 + i * 20,
                timestamp=base_time
            )
            analyzer.add_metrics(metrics)
        
        temporal = analyzer.detect_temporal_patterns("partition_0")
        assert temporal["trend"] in ["accelerating", "stable"]
        assert isinstance(temporal["acceleration"], float)
    
    def test_memory_correlation_analysis(self):
        """Test memory correlation analysis."""
        analyzer = PartitionAnalyzer()
        
        # Create metrics with correlated memory and load
        metrics_list = []
        for i in range(10):
            load = 100 + i * 50
            memory = 50 + load * 0.5  # Correlated memory usage
            
            metrics = PartitionMetrics(
                partition_id=f"partition_{i % 5}",
                request_count=load,
                memory_usage_mb=memory,
                cpu_usage_percent=20 + i * 2,
                avg_response_time_ms=100 + i * 10
            )
            metrics_list.append(metrics)
        
        correlation_analysis = analyzer.analyze_memory_correlation(metrics_list)
        
        assert isinstance(correlation_analysis["correlation"], float)
        assert isinstance(correlation_analysis["memory_pressure_detected"], bool)
        assert correlation_analysis["correlation"] > 0.5  # Should show positive correlation

if __name__ == "__main__":
    pytest.main([__file__])
