"""Partition data models and utilities."""

from typing import Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import math
import numpy as np

@dataclass
class PartitionMetrics:
    """Metrics for a single partition."""
    partition_id: str
    request_count: int = 0
    memory_usage_mb: float = 0.0
    cpu_usage_percent: float = 0.0
    avg_response_time_ms: float = 0.0
    error_rate: float = 0.0
    timestamp: datetime = field(default_factory=datetime.now)

@dataclass
class HotPartitionAlert:
    """Alert data for hot partition detection."""
    partition_id: str
    severity: str  # LOW, MEDIUM, HIGH, CRITICAL
    entropy_score: float
    load_factor: float
    recommended_action: str
    timestamp: datetime = field(default_factory=datetime.now)

class PartitionAnalyzer:
    """Analyzes partition metrics for hot partition detection."""
    
    def __init__(self, entropy_threshold: float = 0.7):
        self.entropy_threshold = entropy_threshold
        self.historical_metrics: Dict[str, List[PartitionMetrics]] = {}
        
    def calculate_entropy(self, partition_loads: List[float]) -> float:
        """Calculate Shannon entropy for load distribution."""
        if not partition_loads or sum(partition_loads) == 0:
            return 1.0
            
        total = sum(partition_loads)
        probabilities = [load / total for load in partition_loads if load > 0]
        
        if len(probabilities) <= 1:
            return 0.0
            
        entropy = -sum(p * math.log2(p) for p in probabilities)
        max_entropy = math.log2(len(partition_loads))
        
        return entropy / max_entropy if max_entropy > 0 else 0.0
    
    def detect_temporal_patterns(self, partition_id: str, 
                                window_minutes: int = 5) -> Dict:
        """Detect temporal access patterns for a partition."""
        if partition_id not in self.historical_metrics:
            return {"trend": "stable", "acceleration": 0.0}
            
        metrics = self.historical_metrics[partition_id]
        cutoff_time = datetime.now() - timedelta(minutes=window_minutes)
        recent_metrics = [m for m in metrics if m.timestamp >= cutoff_time]
        
        if len(recent_metrics) < 3:
            return {"trend": "insufficient_data", "acceleration": 0.0}
            
        # Calculate acceleration in request rate
        times = [(m.timestamp - recent_metrics[0].timestamp).total_seconds() 
                for m in recent_metrics]
        loads = [m.request_count for m in recent_metrics]
        
        if len(times) > 2:
            # Linear regression to find acceleration
            coeffs = np.polyfit(times, loads, 2) if len(times) > 2 else [0, 0, 0]
            acceleration = coeffs[0] * 2  # Second derivative
            
            if acceleration > 10:
                trend = "accelerating"
            elif acceleration < -10:
                trend = "decelerating"
            else:
                trend = "stable"
                
            return {"trend": trend, "acceleration": acceleration}
        
        return {"trend": "stable", "acceleration": 0.0}
    
    def analyze_memory_correlation(self, all_metrics: List[PartitionMetrics]) -> Dict:
        """Analyze memory usage correlation with request load."""
        if len(all_metrics) < 2:
            return {"correlation": 0.0, "memory_pressure_detected": False}
            
        loads = [m.request_count for m in all_metrics]
        memory = [m.memory_usage_mb for m in all_metrics]
        
        correlation = np.corrcoef(loads, memory)[0, 1] if len(loads) > 1 else 0.0
        
        # Detect memory pressure
        avg_memory = np.mean(memory)
        std_memory = np.std(memory)
        memory_pressure = any(m > avg_memory + 2 * std_memory for m in memory)
        
        return {
            "correlation": correlation,
            "memory_pressure_detected": memory_pressure,
            "avg_memory_mb": avg_memory
        }
    
    def generate_alert(self, partition_id: str, metrics: PartitionMetrics,
                      entropy_score: float, temporal_analysis: Dict) -> Optional[HotPartitionAlert]:
        """Generate alert based on analysis results."""
        load_factor = metrics.request_count / 1000.0  # Normalize to expected load
        
        # Determine severity
        if entropy_score < 0.3 or load_factor > 5.0:
            severity = "CRITICAL"
            action = "Immediate range splitting required"
        elif entropy_score < 0.5 or load_factor > 3.0:
            severity = "HIGH" 
            action = "Consider replication or load shedding"
        elif entropy_score < self.entropy_threshold or load_factor > 2.0:
            severity = "MEDIUM"
            action = "Monitor closely, prepare mitigation"
        else:
            return None
            
        if temporal_analysis["trend"] == "accelerating":
            severity = "CRITICAL" if severity != "CRITICAL" else severity
            action = f"{action} (Accelerating pattern detected)"
            
        return HotPartitionAlert(
            partition_id=partition_id,
            severity=severity,
            entropy_score=entropy_score,
            load_factor=load_factor,
            recommended_action=action
        )
    
    def add_metrics(self, metrics: PartitionMetrics):
        """Add metrics to historical data."""
        if metrics.partition_id not in self.historical_metrics:
            self.historical_metrics[metrics.partition_id] = []
            
        self.historical_metrics[metrics.partition_id].append(metrics)
        
        # Keep only last 100 entries per partition
        if len(self.historical_metrics[metrics.partition_id]) > 100:
            self.historical_metrics[metrics.partition_id] = \
                self.historical_metrics[metrics.partition_id][-100:]
