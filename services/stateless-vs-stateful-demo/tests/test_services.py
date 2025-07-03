"""
Test suite for stateless vs stateful services
"""
import pytest
import httpx
import asyncio

@pytest.mark.asyncio
async def test_stateless_service():
    """Test stateless service endpoints"""
    async with httpx.AsyncClient() as client:
        # Test health endpoint
        response = await client.get("http://stateless-service:8000/health")
        assert response.status_code == 200
        
        # Test metrics endpoint
        response = await client.get("http://stateless-service:8000/metrics")
        assert response.status_code == 200
        data = response.json()
        assert data['service_type'] == 'stateless'

@pytest.mark.asyncio
async def test_stateful_service():
    """Test stateful service endpoints"""
    async with httpx.AsyncClient() as client:
        # Test health endpoint
        response = await client.get("http://stateful-service:8001/health")
        assert response.status_code == 200
        
        # Test metrics endpoint
        response = await client.get("http://stateful-service:8001/metrics")
        assert response.status_code == 200
        data = response.json()
        assert data['service_type'] == 'stateful'

@pytest.mark.asyncio
async def test_user_flow():
    """Test complete user flow on both services"""
    services = [
        ("http://stateless-service:8000", "stateless"),
        ("http://stateful-service:8001", "stateful")
    ]
    
    for base_url, service_type in services:
        async with httpx.AsyncClient() as client:
            # Login
            login_data = {
                'username': 'testuser',
                'email': 'test@example.com'
            }
            response = await client.post(f"{base_url}/login", data=login_data)
            assert response.status_code == 200
            
            # Add item to cart
            item_data = {
                'product_id': 'test_prod',
                'name': 'Test Product',
                'price': 29.99,
                'quantity': 1
            }
            response = await client.post(f"{base_url}/cart/add", json=item_data)
            assert response.status_code == 200
            
            # Get cart
            response = await client.get(f"{base_url}/cart")
            assert response.status_code == 200
            cart_data = response.json()
            assert len(cart_data['cart']['items']) > 0

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
