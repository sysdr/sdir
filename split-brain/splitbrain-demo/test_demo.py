#!/usr/bin/env python3
"""
Test script for Split-Brain Prevention Demo
Validates all functionality works correctly
"""
import asyncio
import httpx
import json
import time
import websockets
import sys

async def test_api_endpoints():
    """Test all API endpoints"""
    print("🧪 Testing API endpoints...")
    
    base_url = "http://localhost:8000"
    
    async with httpx.AsyncClient() as client:
        # Test cluster creation
        print("  Testing cluster creation...")
        response = await client.post(f"{base_url}/api/cluster/create", 
                                   json={"node_count": 5})
        assert response.status_code == 200
        result = response.json()
        assert result["status"] == "success"
        print("  ✅ Cluster creation works")
        
        # Wait for cluster to stabilize
        await asyncio.sleep(3)
        
        # Test status endpoint
        print("  Testing status endpoint...")
        response = await client.get(f"{base_url}/api/cluster/status")
        assert response.status_code == 200
        status = response.json()
        assert len(status) == 5  # Should have 5 nodes
        print("  ✅ Status endpoint works")
        
        # Test partition simulation
        print("  Testing partition simulation...")
        response = await client.post(f"{base_url}/api/cluster/partition",
                                   json={
                                       "group_a": ["node1", "node2", "node3"],
                                       "group_b": ["node4", "node5"]
                                   })
        assert response.status_code == 200
        print("  ✅ Partition simulation works")
        
        # Wait for partition effects
        await asyncio.sleep(5)
        
        # Check status after partition
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        # Verify partition effects
        partitioned_nodes = [node for node in status.values() if node["is_partitioned"]]
        assert len(partitioned_nodes) > 0
        print("  ✅ Partition effects verified")
        
        # Test healing
        print("  Testing partition healing...")
        response = await client.post(f"{base_url}/api/cluster/heal")
        assert response.status_code == 200
        print("  ✅ Partition healing works")
        
        await asyncio.sleep(2)
        
        # Verify healing
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        partitioned_nodes = [node for node in status.values() if node["is_partitioned"]]
        assert len(partitioned_nodes) == 0
        print("  ✅ Healing effects verified")

async def test_websocket():
    """Test WebSocket functionality"""
    print("🔌 Testing WebSocket connection...")
    
    try:
        uri = "ws://localhost:8000/ws"
        async with websockets.connect(uri) as websocket:
            # Should receive status update
            message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
            data = json.loads(message)
            assert data["type"] == "status_update"
            assert "data" in data
            print("  ✅ WebSocket communication works")
    except Exception as e:
        print(f"  ❌ WebSocket test failed: {e}")
        raise

async def test_consensus_behavior():
    """Test actual consensus behavior"""
    print("🤝 Testing consensus behavior...")
    
    async with httpx.AsyncClient() as client:
        base_url = "http://localhost:8000"
        
        # Create fresh cluster
        await client.post(f"{base_url}/api/cluster/create", json={"node_count": 5})
        await asyncio.sleep(3)
        
        # Check initial state - should have one leader
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        leaders = [node for node in status.values() if node["state"] == "leader"]
        print(f"  Initial leaders: {len(leaders)}")
        
        # Simulate partition
        await client.post(f"{base_url}/api/cluster/partition",
                         json={
                             "group_a": ["node1", "node2", "node3"],
                             "group_b": ["node4", "node5"]
                         })
        
        # Wait for election
        await asyncio.sleep(8)
        
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        leaders = [node for node in status.values() if node["state"] == "leader"]
        majority_group = [node for node in status.values() 
                         if node.get("partition_group") == "A"]
        minority_group = [node for node in status.values() 
                         if node.get("partition_group") == "B"]
        
        print(f"  Leaders after partition: {len(leaders)}")
        print(f"  Majority group size: {len(majority_group)}")
        print(f"  Minority group size: {len(minority_group)}")
        
        # Verify split-brain prevention
        assert len(leaders) <= 1, "Split-brain detected - multiple leaders!"
        
        # If there's a leader, it should be in the majority group
        if leaders:
            leader_in_majority = any(leader["partition_group"] == "A" for leader in leaders)
            assert leader_in_majority, "Leader should be in majority partition"
        
        print("  ✅ Split-brain prevention verified")

async def run_tests():
    """Run all tests"""
    print("🚀 Starting Split-Brain Demo Tests")
    print("=" * 50)
    
    try:
        await test_api_endpoints()
        await test_websocket()
        await test_consensus_behavior()
        
        print("\n" + "=" * 50)
        print("✅ All tests passed! Demo is working correctly.")
        return True
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = asyncio.run(run_tests())
    sys.exit(0 if success else 1)
