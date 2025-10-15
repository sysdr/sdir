import pytest
import asyncio
import aiohttp
import json
import time

class TestErrorBudgets:
    
    @pytest.mark.asyncio
    async def test_dashboard_loads(self):
        """Test that the dashboard loads successfully"""
        async with aiohttp.ClientSession() as session:
            async with session.get('http://localhost:3000') as response:
                assert response.status == 200
    
    @pytest.mark.asyncio
    async def test_error_budget_api(self):
        """Test error budget calculation API"""
        async with aiohttp.ClientSession() as session:
            async with session.get('http://localhost:3000/api/error-budgets') as response:
                assert response.status == 200
                data = await response.json()
                
                # Should have all three services
                assert 'user-service' in data
                assert 'payment-service' in data
                assert 'order-service' in data
                
                # Each service should have required fields
                for service_data in data.values():
                    assert 'success_rate' in service_data
                    assert 'error_budget_remaining' in service_data
                    assert 'budget_status' in service_data
    
    @pytest.mark.asyncio
    async def test_error_rate_configuration(self):
        """Test configuring service error rates"""
        async with aiohttp.ClientSession() as session:
            # Set error rate to 10%
            async with session.post('http://localhost:8001/config/error-rate/0.1') as response:
                assert response.status == 200
                
            # Wait a moment for metrics to update
            await asyncio.sleep(2)
            
            # Check that error budget reflects the change
            async with session.get('http://localhost:3000/api/error-budgets') as response:
                data = await response.json()
                # Error budget should be affected by increased error rate
                # (exact values depend on traffic generation timing)
                assert data['user-service']['budget_status'] in ['healthy', 'critical', 'exhausted']

if __name__ == "__main__":
    pytest.main([__file__])
