"""
Test suite for Clock Synchronization Observatory
Validates all components work correctly together.
"""

import time
import requests
import pytest
import subprocess
import json
from typing import Dict, List

class TestClockSyncObservatory:
    """Comprehensive test suite for the observatory system"""
    
    @classmethod
    def setup_class(cls):
        """Setup test environment"""
        cls.base_url = "http://localhost"
        cls.services = {
            'clock_node_1': 8001,
            'clock_node_2': 8002,
            'clock_node_3': 8003,
            'vector_service': 8004,
            'truetime_service': 8005,
            'dashboard': 3000
        }
        
        # Wait for services to be ready
        cls._wait_for_services()
    
    @classmethod
    def _wait_for_services(cls, timeout: int = 60):
        """Wait for all services to be ready"""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            all_ready = True
            
            for service, port in cls.services.items():
                try:
                    if 'clock_node' in service:
                        response = requests.get(f"{cls.base_url}:{port}/health", timeout=2)
                    elif service == 'dashboard':
                        response = requests.get(f"{cls.base_url}:{port}/", timeout=2)
                    else:
                        response = requests.get(f"{cls.base_url}:{port}/", timeout=2)
                    
                    if response.status_code not in [200, 404]:  # 404 is OK for some endpoints
                        all_ready = False
                        break
                        
                except requests.exceptions.RequestException:
                    all_ready = False
                    break
            
            if all_ready:
                print("All services are ready!")
                return
            
            time.sleep(2)
        
        raise TimeoutError("Services did not become ready within timeout period")
    
    def test_clock_nodes_running(self):
        """Test that all clock nodes are running and healthy"""
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/health")
            assert response.status_code == 200
            
            health_data = response.json()
            assert health_data['status'] == 'healthy'
            assert health_data['node_id'] == i
            assert 'drift_rate' in health_data
    
    def test_clock_readings(self):
        """Test clock reading functionality"""
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/time")
            assert response.status_code == 200
            
            reading = response.json()
            assert 'node_id' in reading
            assert 'physical_time' in reading
            assert 'logical_time' in reading
            assert 'drift_offset' in reading
            assert 'uncertainty_bound' in reading
    
    def test_clock_synchronization(self):
        """Test NTP-style synchronization"""
        node_url = f"{self.base_url}:8001"
        
        # Trigger synchronization
        sync_data = {
            'source_time': time.time(),
            'rtt_ms': 10.0
        }
        
        response = requests.post(f"{node_url}/sync", json=sync_data)
        assert response.status_code == 200
        
        sync_result = response.json()
        assert 'node_id' in sync_result
        assert 'offset_correction' in sync_result
        assert 'rtt_ms' in sync_result
    
    def test_vector_clock_service(self):
        """Test vector clock event creation and causality"""
        vector_url = f"{self.base_url}:8004"
        
        # Reset state first
        requests.post(f"{vector_url}/reset")
        
        # Create events on different nodes
        event1_data = {
            'node_id': 1,
            'event_type': 'local',
            'data': {'message': 'First event'}
        }
        
        response1 = requests.post(f"{vector_url}/event", json=event1_data)
        assert response1.status_code == 200
        result1 = response1.json()
        
        # Create second event that receives message from first
        event2_data = {
            'node_id': 2,
            'event_type': 'message_received',
            'sender_clock': result1['vector_clock'],
            'data': {'message': 'Received from node 1'}
        }
        
        response2 = requests.post(f"{vector_url}/event", json=event2_data)
        assert response2.status_code == 200
        result2 = response2.json()
        
        # Verify causality
        causality_response = requests.get(
            f"{vector_url}/causality/{result1['event_id']}/{result2['event_id']}"
        )
        assert causality_response.status_code == 200
        
        causality_data = causality_response.json()
        assert causality_data['relationship'] == 'event1_before_event2'
    
    def test_vector_clock_scenarios(self):
        """Test predefined vector clock scenarios"""
        vector_url = f"{self.base_url}:8004"
        
        scenarios = ['basic', 'concurrent', 'complex']
        
        for scenario in scenarios:
            response = requests.post(f"{vector_url}/simulate", json={'scenario': scenario})
            assert response.status_code == 200
            
            result = response.json()
            assert result['status'] == 'simulation_complete'
            assert result['scenario'] == scenario
    
    def test_truetime_service(self):
        """Test TrueTime uncertainty intervals"""
        truetime_url = f"{self.base_url}:8005"
        
        # Get TrueTime reading
        response = requests.get(f"{truetime_url}/now")
        assert response.status_code == 200
        
        reading = response.json()
        assert 'earliest' in reading
        assert 'latest' in reading
        assert 'uncertainty_ms' in reading
        assert 'confidence' in reading
        assert reading['earliest'] <= reading['latest']
    
    def test_truetime_commit_wait(self):
        """Test commit wait protocol"""
        truetime_url = f"{self.base_url}:8005"
        
        # Start transaction commit
        commit_data = {'transaction_id': 'test_tx_001'}
        response = requests.post(f"{truetime_url}/commit", json=commit_data)
        assert response.status_code == 200
        
        commit_result = response.json()
        assert 'transaction_id' in commit_result
        assert 'commit_timestamp' in commit_result
        assert 'wait_duration_ms' in commit_result
        assert 'status' in commit_result
        
        # Check commit status
        status_response = requests.get(f"{truetime_url}/commit/test_tx_001")
        assert status_response.status_code == 200
    
    def test_truetime_ordering(self):
        """Test transaction ordering logic"""
        truetime_url = f"{self.base_url}:8005"
        
        current_time = time.time()
        ordering_data = {
            'tx1_commit_time': current_time,
            'tx2_commit_time': current_time + 0.1  # 100ms later
        }
        
        response = requests.post(f"{truetime_url}/ordering", json=ordering_data)
        assert response.status_code == 200
        
        ordering_result = response.json()
        assert 'can_safely_order' in ordering_result
        assert 'tx1_bounds' in ordering_result
        assert 'tx2_bounds' in ordering_result
    
    def test_dashboard_endpoints(self):
        """Test dashboard API endpoints"""
        dashboard_url = f"{self.base_url}:3000"
        
        # Test main page
        response = requests.get(f"{dashboard_url}/")
        assert response.status_code == 200
        assert 'Clock Synchronization Observatory' in response.text
        
        # Test API endpoints
        api_endpoints = [
            '/api/clock-readings',
            '/api/vector-events',
            '/api/truetime-reading',
            '/api/truetime-stats'
        ]
        
        for endpoint in api_endpoints:
            response = requests.get(f"{dashboard_url}{endpoint}")
            assert response.status_code == 200
            
            # Should return valid JSON
            data = response.json()
            assert isinstance(data, (dict, list))
    
    def test_clock_drift_analysis(self):
        """Test clock drift visualization"""
        dashboard_url = f"{self.base_url}:3000"
        
        # Wait a bit for some drift data to accumulate
        time.sleep(5)
        
        response = requests.get(f"{dashboard_url}/api/clock-drift-chart")
        assert response.status_code == 200
        
        # Should return Plotly chart data
        chart_data = response.json()
        assert 'data' in chart_data or 'error' in chart_data
    
    def test_integration_workflow(self):
        """Test complete integration workflow"""
        # 1. Check all clock nodes are synchronized
        readings = []
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/time")
            reading = response.json()
            readings.append(reading)
        
        # All nodes should have similar physical times (within reasonable bounds)
        times = [r['physical_time'] for r in readings]
        time_spread = max(times) - min(times)
        assert time_spread < 1.0  # Within 1 second
        
        # 2. Create vector clock events and verify causality
        vector_url = f"{self.base_url}:8004"
        requests.post(f"{vector_url}/simulate", json={'scenario': 'basic'})
        
        events_response = requests.get(f"{vector_url}/events")
        events = events_response.json()
        assert len(events) > 0
        
        # 3. Test TrueTime commit with uncertainty
        truetime_url = f"{self.base_url}:8005"
        commit_response = requests.post(
            f"{truetime_url}/commit",
            json={'transaction_id': 'integration_test_tx'}
        )
        commit_result = commit_response.json()
        assert 'wait_duration_ms' in commit_result
        
        # 4. Verify dashboard reflects all the above
        dashboard_url = f"{self.base_url}:3000"
        
        clock_readings = requests.get(f"{dashboard_url}/api/clock-readings").json()
        assert len(clock_readings) == 3
        
        vector_events = requests.get(f"{dashboard_url}/api/vector-events").json()
        assert len(vector_events) > 0
        
        truetime_stats = requests.get(f"{dashboard_url}/api/truetime-stats").json()
        assert 'current_uncertainty_ms' in truetime_stats

def main():
    """Run tests with proper error handling"""
    pytest_args = [
        __file__,
        '-v',
        '--tb=short',
        '--color=yes'
    ]
    
    exit_code = pytest.main(pytest_args)
    return exit_code

if __name__ == '__main__':
    exit(main())
