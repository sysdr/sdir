#!/usr/bin/env python3
"""
Global Load Balancing Strategies Demo Tests
System Design Interview Roadmap - Issue #99
"""

import unittest
import sys
import os
import requests
import time
import json

# Add app directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from main import app, GlobalLoadBalancer, DATA_CENTERS

class TestGlobalLoadBalancer(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        self.lb = GlobalLoadBalancer()

    def test_health_endpoint(self):
        """Test health check endpoint"""
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')

    def test_data_centers_endpoint(self):
        """Test data centers API endpoint"""
        response = self.app.get('/api/data-centers')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('us-east-1', data)
        self.assertIn('us-west-2', data)

    def test_stats_endpoint(self):
        """Test global statistics endpoint"""
        response = self.app.get('/api/stats')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('total_requests', data)
        self.assertIn('successful_requests', data)

    def test_load_balancer_distance_calculation(self):
        """Test distance calculation between locations"""
        # New York to London
        ny_location = (40.7128, -74.0060)
        london_location = (51.5074, -0.1278)
        
        distance = self.lb.calculate_distance(ny_location, london_location)
        # Should be approximately 5500 km
        self.assertGreater(distance, 5000)
        self.assertLess(distance, 6000)

    def test_latency_calculation(self):
        """Test latency calculation"""
        distance = 1000  # 1000 km
        base_latency = 50
        
        latency = self.lb.calculate_latency(distance, base_latency)
        # Should include base latency + network delay
        self.assertGreater(latency, base_latency)

    def test_data_center_selection_latency(self):
        """Test latency-based data center selection"""
        user_location = (40.7128, -74.0060)  # New York
        
        selected_dc, latency, strategy = self.lb.select_data_center(
            user_location, 'latency'
        )
        
        self.assertIsNotNone(selected_dc)
        self.assertIn(selected_dc, DATA_CENTERS)
        self.assertEqual(strategy, 'latency_optimized')

    def test_data_center_selection_geographic(self):
        """Test geographic data center selection"""
        user_location = (40.7128, -74.0060)  # New York
        
        selected_dc, latency, strategy = self.lb.select_data_center(
            user_location, 'geographic'
        )
        
        self.assertIsNotNone(selected_dc)
        # Should select us-east-1 for New York user
        self.assertEqual(selected_dc, 'us-east-1')

    def test_request_processing(self):
        """Test request processing"""
        result = self.lb.process_request('new_york')
        
        self.assertIn('success', result)
        if result.get('success', False):
            self.assertIn('selected_dc', result)
            self.assertIn('latency', result)
            self.assertIn('strategy', result)

    def test_healthy_data_centers_filter(self):
        """Test filtering of healthy data centers"""
        # Make one DC unhealthy
        original_health = DATA_CENTERS['us-east-1']['health']
        DATA_CENTERS['us-east-1']['health'] = 'unhealthy'
        
        healthy_dcs = self.lb.get_healthy_data_centers()
        self.assertNotIn('us-east-1', healthy_dcs)
        
        # Restore original health
        DATA_CENTERS['us-east-1']['health'] = original_health

    def test_config_update_endpoint(self):
        """Test configuration update endpoint"""
        response = self.app.post('/api/config',
                                data=json.dumps({'strategy': 'geographic'}),
                                content_type='application/json')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertTrue(data['success'])

    def test_request_endpoint(self):
        """Test request processing endpoint"""
        response = self.app.post('/api/request',
                                data=json.dumps({'user_location': 'new_york'}),
                                content_type='application/json')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        # Should have either success or error
        self.assertTrue('success' in data or 'error' in data)

class TestEndToEndFunctionality(unittest.TestCase):
    """End-to-end tests that verify the complete system"""
    
    @classmethod
    def setUpClass(cls):
        """Start the Flask application for testing"""
        cls.base_url = 'http://localhost:5000'
        # Note: These tests assume the application is running
        
    def test_web_interface_accessibility(self):
        """Test that the web interface is accessible"""
        try:
            response = requests.get(f'{self.base_url}/')
            self.assertEqual(response.status_code, 200)
            self.assertIn('Global Load Balancing Strategies', response.text)
        except requests.exceptions.ConnectionError:
            self.skipTest("Application not running - skipping integration test")

    def test_api_endpoints_integration(self):
        """Test API endpoints integration"""
        try:
            # Test health endpoint
            response = requests.get(f'{self.base_url}/health')
            self.assertEqual(response.status_code, 200)
            
            # Test data centers endpoint
            response = requests.get(f'{self.base_url}/api/data-centers')
            self.assertEqual(response.status_code, 200)
            
            # Test stats endpoint
            response = requests.get(f'{self.base_url}/api/stats')
            self.assertEqual(response.status_code, 200)
            
        except requests.exceptions.ConnectionError:
            self.skipTest("Application not running - skipping integration test")

def run_tests():
    """Run all tests and return success status"""
    # Create test suite
    test_suite = unittest.TestLoader().loadTestsFromTestCase(TestGlobalLoadBalancer)
    integration_suite = unittest.TestLoader().loadTestsFromTestCase(TestEndToEndFunctionality)
    
    # Combine test suites
    combined_suite = unittest.TestSuite([test_suite, integration_suite])
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(combined_suite)
    
    return result.wasSuccessful()

if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
