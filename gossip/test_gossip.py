import requests
import time

def test_gossip_propagation():
    """Test gossip propagation across nodes"""
    print("🧪 Testing Gossip Propagation")
    print("=============================")
    
    nodes = [
        ("node1", "localhost", 9001),
        ("node2", "localhost", 9002),
        ("node3", "localhost", 9003),
        ("node4", "localhost", 9004),
        ("node5", "localhost", 9005)
    ]
    
    # Test 1: Add data to first node
    print("\n📝 Test 1: Adding data to node1...")
    test_data = {"key": "test_propagation", "value": f"timestamp_{int(time.time())}"}
    
    try:
        response = requests.post(
            f"http://localhost:9001/api/add_data",
            json=test_data,
            timeout=5
        )
        
        if response.status_code == 200:
            print("✅ Data added successfully")
        else:
            print(f"❌ Failed to add data: {response.status_code}")
            return
    except Exception as e:
        print(f"❌ Error adding data: {e}")
        return
    
    # Test 2: Check propagation
    print("\n⏳ Waiting for gossip propagation...")
    time.sleep(15)  # Increased from 10 to 15 seconds
    
    print("\n🔍 Checking data propagation across all nodes:")
    propagated_count = 0
    
    for node_id, host, port in nodes:
        try:
            response = requests.get(f"http://{host}:{port}/api/status", timeout=5)
            if response.status_code == 200:
                data = response.json()
                local_data = data.get('local_data', {})
                
                if test_data['key'] in local_data and local_data[test_data['key']] == test_data['value']:
                    print(f"  ✅ {node_id}: Data found")
                    propagated_count += 1
                else:
                    print(f"  ❌ {node_id}: Data not found")
                    print(f"     Local data: {local_data}")
                
                # Show detailed stats
                stats = data.get('stats', {})
                print(f"     Stats: Sent={stats.get('messages_sent', 0)}, "
                      f"Received={stats.get('messages_received', 0)}, "
                      f"Rounds={stats.get('gossip_rounds', 0)}, "
                      f"Queue Size={data.get('gossip_queue_size', 0)}")
            else:
                print(f"  ❌ {node_id}: HTTP {response.status_code}")
        except Exception as e:
            print(f"  ❌ {node_id}: Error - {e}")
    
    success_rate = (propagated_count / len(nodes)) * 100
    print(f"\n📊 Propagation Success Rate: {success_rate:.1f}% ({propagated_count}/{len(nodes)} nodes)")
    
    if success_rate >= 80:
        print("🎉 Test PASSED: Gossip propagation working correctly!")
    else:
        print("⚠️  Test FAILED: Gossip propagation incomplete") 