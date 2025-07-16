import pytest
import asyncio
import aiohttp
import json

BASE_URL = "http://localhost:8080"

@pytest.mark.asyncio
async def test_core_functionality_always_available():
    """Core features should always be available"""
    async with aiohttp.ClientSession() as session:
        # Simulate high load
        await session.get(f"{BASE_URL}/api/load/90")
        await asyncio.sleep(2)
        
        # Core functionality should still work
        async with session.get(f"{BASE_URL}/api/products") as response:
            assert response.status == 200
            data = await response.json()
            assert len(data["products"]) > 0

@pytest.mark.asyncio
async def test_feature_degradation_under_load():
    """Non-essential features should degrade under load"""
    async with aiohttp.ClientSession() as session:
        # Check features under normal load
        async with session.get(f"{BASE_URL}/api/status") as response:
            normal_data = await response.json()
        
        # Simulate extreme load
        await session.get(f"{BASE_URL}/api/load/100")
        await asyncio.sleep(3)
        
        # Check features under high load
        async with session.get(f"{BASE_URL}/api/status") as response:
            high_load_data = await response.json()
        
        # Should have fewer active features under high load
        assert len(high_load_data["active_features"]) <= len(normal_data["active_features"])

@pytest.mark.asyncio
async def test_circuit_breaker_functionality():
    """Circuit breakers should prevent cascading failures"""
    async with aiohttp.ClientSession() as session:
        # Trigger multiple failures
        for _ in range(10):
            try:
                await session.get(f"{BASE_URL}/api/recommendations/123")
            except:
                pass
        
        # Check circuit breaker status
        async with session.get(f"{BASE_URL}/api/status") as response:
            data = await response.json()
            # At least one circuit breaker should be in non-CLOSED state
            states = [cb["state"] for cb in data["circuit_breakers"].values()]
            assert any(state != "CLOSED" for state in states)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
