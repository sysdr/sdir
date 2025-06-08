#!/usr/bin/env python3
"""
Test scenarios for leader election demonstration
"""
import asyncio
import httpx
import json
import time
from typing import List, Dict

class LeaderElectionTester:
    def __init__(self, nodes: List[str]):
        self.nodes = nodes
        self.client = httpx.AsyncClient(timeout=2.0)
    
    async def get_cluster_status(self) -> Dict:
        """Get status from all nodes"""
        status = {}
        for node in self.nodes:
            try:
                response = await self.client.get(f"http://{node}/status")
                if response.status_code == 200:
                    status[node] = response.json()
                else:
                    status[node] = {"error": "unreachable"}
            except Exception as e:
                status[node] = {"error": str(e)}
        return status
    
    async def find_leader(self) -> str:
        """Find the current leader"""
        status = await self.get_cluster_status()
        for node, data in status.items():
            if data.get("state") == "leader":
                return node
        return None
    
    async def simulate_leader_failure(self):
        """Simulate leader failure scenario"""
        print("\n🔥 SCENARIO: Leader Failure Simulation")
        print("="*50)
        
        leader = await self.find_leader()
        if not leader:
            print("❌ No leader found")
            return
        
        print(f"Current leader: {leader}")
        
        # Simulate failure
        try:
            response = await self.client.post(f"http://{leader}/simulate_failure")
            print(f"✅ Simulated failure on {leader}")
        except Exception as e:
            print(f"❌ Failed to simulate failure: {e}")
            return
        
        # Monitor election process
        print("\n📊 Monitoring election process...")
        for i in range(10):
            await asyncio.sleep(1)
            status = await self.get_cluster_status()
            
            # Count states
            states = {"follower": 0, "candidate": 0, "leader": 0}
            term_info = {}
            
            for node, data in status.items():
                if "error" not in data:
                    state = data.get("state", "unknown")
                    states[state] = states.get(state, 0) + 1
                    term_info[node] = data.get("term", 0)
            
            print(f"T+{i+1}s: Followers={states['follower']}, "
                  f"Candidates={states['candidate']}, Leaders={states['leader']}")
            
            # Check if new leader emerged
            new_leader = await self.find_leader()
            if new_leader and new_leader != leader:
                print(f"🎉 New leader elected: {new_leader}")
                break
        
        print(f"\n📈 Final cluster status:")
        await self.print_cluster_status()
    
    async def test_network_partition(self):
        """Test behavior during network partition"""
        print("\n🌐 SCENARIO: Network Partition Simulation")
        print("="*50)
        print("Note: This is simulated through failure injection")
        
        # Simulate partition by failing multiple nodes
        nodes_to_fail = self.nodes[:2]  # Fail first 2 nodes
        
        for node in nodes_to_fail:
            try:
                await self.client.post(f"http://{node}/simulate_failure")
                print(f"🔌 Disconnected {node}")
            except:
                pass
        
        print(f"\n📊 Remaining cluster should maintain leadership...")
        await asyncio.sleep(3)
        await self.print_cluster_status()
    
    async def print_cluster_status(self):
        """Print detailed cluster status"""
        status = await self.get_cluster_status()
        
        print("\n📋 Cluster Status:")
        print("-" * 80)
        print(f"{'Node':<12} {'State':<12} {'Term':<6} {'Leader':<12} {'Elections':<10} {'Uptime':<8}")
        print("-" * 80)
        
        for node, data in status.items():
            if "error" in data:
                print(f"{node:<12} {'ERROR':<12} {'-':<6} {'-':<12} {'-':<10} {'-':<8}")
            else:
                state = data.get("state", "unknown").upper()
                term = data.get("term", 0)
                leader = data.get("leader_id", "None")
                elections = data.get("stats", {}).get("elections_participated", 0)
                uptime = f"{data.get('uptime', 0):.1f}s"
                
                print(f"{node:<12} {state:<12} {term:<6} {leader:<12} {elections:<10} {uptime:<8}")
    
    async def run_all_tests(self):
        """Run all test scenarios"""
        print("🧪 Leader Election Test Suite")
        print("=" * 60)
        
        # Initial status
        print("\n📊 Initial cluster status:")
        await self.print_cluster_status()
        
        # Wait for stabilization
        await asyncio.sleep(3)
        
        # Test scenarios
        await self.simulate_leader_failure()
        await asyncio.sleep(5)
        
        await self.test_network_partition()
        
        print("\n✅ All tests completed!")
    
    async def close(self):
        await self.client.aclose()

async def main():
    nodes = [f"localhost:800{i}" for i in range(1, 6)]
    tester = LeaderElectionTester(nodes)
    
    try:
        await tester.run_all_tests()
    finally:
        await tester.close()

if __name__ == "__main__":
    asyncio.run(main())
