import asyncio
import aiohttp
import pytest
import time

class TestCascadeBehavior:
    
    @pytest.mark.asyncio
    async def test_normal_operation(self):
        """Test normal operation without failures"""
        async with aiohttp.ClientSession() as session:
            # Ensure services are in healthy state
            await session.post('http://auth-service:8001/control/recover')
            await asyncio.sleep(5)
            
            # Test order creation
            async with session.post(
                'http://order-service:8003/order/create',
                json={'user_id': 'test_user', 'items': ['item1'], 'total': 50.0}
            ) as response:
                assert response.status == 200
                data = await response.json()
                assert 'order_id' in data
                # In normal operation, user should be verified
                assert data['user_verified'] == True
    
    @pytest.mark.asyncio
    async def test_cascade_failure(self):
        """Test cascade failure and circuit breaker activation"""
        async with aiohttp.ClientSession() as session:
            # Trigger auth service failure
            await session.post('http://auth-service:8001/control/trigger_failure')
            
            # Wait for circuit breakers to open - need more time for failures to accumulate
            await asyncio.sleep(15)
            
            # Make multiple requests to trigger the cascade through the order service
            for i in range(5):
                try:
                    await session.post(
                        'http://order-service:8003/order/create',
                        json={'user_id': f'test_user_{i}', 'items': ['item1'], 'total': 50.0}
                    )
                except:
                    pass  # Expected failures during cascade
            
            # Test order creation during cascade
            async with session.post(
                'http://order-service:8003/order/create',
                json={'user_id': 'test_user', 'items': ['item1'], 'total': 50.0}
            ) as response:
                assert response.status == 200
                data = await response.json()
                # Should work in degraded mode
                assert 'warning' in data or data.get('user_verified') == False
    
    @pytest.mark.asyncio
    async def test_recovery_behavior(self):
        """Test system recovery after cascade"""
        async with aiohttp.ClientSession() as session:
            # Recover services
            await session.post('http://auth-service:8001/control/recover')
            
            # Wait for recovery - circuit breakers need 30s timeout + time for successful calls
            await asyncio.sleep(35)
            
            # Test normal operation
            async with session.post(
                'http://order-service:8003/order/create',
                json={'user_id': 'test_user', 'items': ['item1'], 'total': 50.0}
            ) as response:
                assert response.status == 200
                data = await response.json()
                assert data.get('user_verified') == True
