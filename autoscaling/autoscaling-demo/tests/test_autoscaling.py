#!/usr/bin/env python3
"""
Test suite for autoscaling demo
"""

import sys
import os
import time
import requests
import threading
from unittest import TestCase, main

# Add src to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import AutoscalingEngine, SystemMetrics

class TestAutoscalingDemo(TestCase):
    """Test autoscaling algorithms and web interface"""
    
    @classmethod
    def setUpClass(cls):
        """Start the demo server for testing"""
        cls.base_url = 'http://localhost:5000'
        # Give server time to start
        time.sleep(2)
    
    def test_reactive_autoscaler(self):
        """Test reactive autoscaling logic"""
        engine = AutoscalingEngine()
        reactive = engine.autoscalers['reactive']
        
        # Test scale out
        high_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=80.0,
            memory_percent=60.0,
            active_connections=100,
            request_rate=50.0,
            response_time=200.0,
            queue_depth=5
        )
        
        decision = reactive.should_scale(high_cpu_metrics, 2)
        self.assertEqual(decision.action, 'scale_out')
        self.assertEqual(decision.target_instances, 3)
        
        # Test scale in
        low_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=20.0,
            memory_percent=30.0,
            active_connections=20,
            request_rate=5.0,
            response_time=100.0,
            queue_depth=0
        )
        
        # Wait for cooldown
        time.sleep(0.1)
        decision = reactive.should_scale(low_cpu_metrics, 3)
        self.assertEqual(decision.action, 'scale_in')
        self.assertEqual(decision.target_instances, 2)
    
    def test_predictive_autoscaler(self):
        """Test predictive autoscaling logic"""
        engine = AutoscalingEngine()
        predictive = engine.autoscalers['predictive']
        
        # Add some history
        for i in range(20):
            metrics = SystemMetrics(
                timestamp=time.time() - (20-i),
                cpu_percent=50.0 + i * 2,  # Increasing trend
                memory_percent=50.0,
                active_connections=50,
                request_rate=10.0,
                response_time=150.0,
                queue_depth=0
            )
            predictive.add_metrics(metrics)
        
        # Should predict high CPU and recommend scale out
        current_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=70.0,
            memory_percent=60.0,
            active_connections=80,
            request_rate=20.0,
            response_time=180.0,
            queue_depth=2
        )
        
        decision = predictive.should_scale(current_metrics, 2)
        # With increasing trend, should scale out proactively
        self.assertIn(decision.action, ['scale_out', 'no_action'])
    
    def test_hybrid_autoscaler(self):
        """Test hybrid autoscaling logic"""
        engine = AutoscalingEngine()
        hybrid = engine.autoscalers['hybrid']
        
        # Test with high CPU - should scale out
        high_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=85.0,
            memory_percent=70.0,
            active_connections=120,
            request_rate=60.0,
            response_time=250.0,
            queue_depth=8
        )
        
        decision = hybrid.should_scale(high_cpu_metrics, 2)
        self.assertEqual(decision.action, 'scale_out')
        self.assertEqual(decision.algorithm, 'hybrid')
    
    def test_web_interface(self):
        """Test web interface endpoints"""
        try:
            # Test main page
            response = requests.get(f'{self.base_url}/')
            self.assertEqual(response.status_code, 200)
            self.assertIn('Autoscaling Strategies Demo', response.text)
            
            # Test API endpoints
            response = requests.get(f'{self.base_url}/api/status')
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn('running', data)
            self.assertIn('instances', data)
            
            # Test load pattern change
            response = requests.post(f'{self.base_url}/api/load_pattern', 
                                   json={'pattern': 'spike'})
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(data['pattern'], 'spike')
            
        except requests.exceptions.ConnectionError:
            self.skipTest("Web server not running")
    
    def test_metrics_generation(self):
        """Test metrics generation"""
        engine = AutoscalingEngine()
        
        # Test steady pattern
        engine.load_simulator.pattern = 'steady'
        metrics = engine.generate_metrics()
        
        self.assertIsInstance(metrics.cpu_percent, float)
        self.assertGreaterEqual(metrics.cpu_percent, 0)
        self.assertLessEqual(metrics.cpu_percent, 100)
        self.assertIsInstance(metrics.timestamp, float)
        
        # Test spike pattern
        engine.load_simulator.pattern = 'spike'
        metrics = engine.generate_metrics()
        
        self.assertIsInstance(metrics.cpu_percent, float)
        self.assertGreaterEqual(metrics.cpu_percent, 0)
    
    def test_load_patterns(self):
        """Test different load patterns"""
        engine = AutoscalingEngine()
        
        patterns = ['steady', 'spike', 'gradual', 'oscillating', 'chaos']
        
        for pattern in patterns:
            engine.set_load_pattern(pattern)
            self.assertEqual(engine.load_simulator.pattern, pattern)
            
            # Generate a few metrics to ensure no errors
            for _ in range(3):
                metrics = engine.generate_metrics()
                self.assertIsInstance(metrics.cpu_percent, float)
                self.assertGreaterEqual(metrics.cpu_percent, 0)

if __name__ == '__main__':
    print("🧪 Running Autoscaling Demo Tests...")
    main(verbosity=2)
