import subprocess
import sys
import time
import requests

class Network:
    def __init__(self, nodes):
        self.nodes = nodes
        self.processes = []

    def start_network(self):
        """Start all gossip nodes"""
        print("🚀 Starting Gossip Protocol Network")
        print("===================================")
        
        # Start each node
        for node_id, host, port in self.nodes:
            print(f"Starting {node_id} on {host}:{port}")
            process = subprocess.Popen([
                sys.executable, "gossip_node.py", node_id, host, str(port)
            ])
            self.processes.append(process)
            time.sleep(2)  # Stagger startup
        
        print("\n✅ All nodes started!")
        print("\n🌐 Web Interfaces:")
        for node_id, host, port in self.nodes:
            print(f"  {node_id}: http://{host}:{port}")
        
        print("\n📊 Demo Instructions:")
        print("1. Open the web interfaces in your browser")
        print("2. Add data in any node using the web interface")
        print("3. Watch the gossip propagation in real-time")
        print("4. Monitor the logs and statistics")
        print("5. Try stopping a node to see failure detection")
        
        # Wait for nodes to start
        time.sleep(5)
        
        # Second join round: have each node join all others
        print("\n🔄 Performing second join round for full cluster discovery...")
        for node_id, host, port in self.nodes:
            for other_id, other_host, other_port in self.nodes:
                if node_id != other_id:
                    try:
                        response = requests.post(
                            f"http://{host}:{port}/api/join",
                            json={
                                'node_id': other_id,
                                'host': other_host,
                                'port': other_port
                            },
                            timeout=2.0
                        )
                        if response.status_code == 200:
                            print(f"  {node_id} joined {other_id}")
                    except Exception as e:
                        print(f"  {node_id} failed to join {other_id}: {e}")
        print("🔄 Second join round complete.")
        
        # Run demonstration
        self.run_demo()
        
        # Keep running
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            self.shutdown() 