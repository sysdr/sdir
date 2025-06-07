#!/usr/bin/env python3

import subprocess
import time
import signal
import sys
import threading
import requests
from typing import List

class GossipNetwork:
    """Manages a network of gossip nodes"""
    
    def __init__(self):
        self.processes: List[subprocess.Popen] = []
        self.nodes = [
            ("node1", "localhost", 9001),
            ("node2", "localhost", 9002),
            ("node3", "localhost", 9003),
            ("node4", "localhost", 9004),
            ("node5", "localhost", 9005)
        ]
    
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
        
        # Run demonstration
        self.run_demo()
        
        # Keep running
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            self.shutdown()
    
    def run_demo(self):
        """Run automated demonstration"""
        print("\n🎬 Running Automated Demo...")
        
        # Add initial data to first node
        try:
            response = requests.post(
                "http://localhost:9001/api/add_data",
                json={"key": "demo_key_1", "value": "Hello Gossip!"},
                timeout=5
            )
            if response.status_code == 200:
                print("✅ Added demo data to node1")
        except Exception as e:
            print(f"❌ Failed to add demo data: {e}")
        
        # Wait and add more data
        time.sleep(5)
        
        try:
            response = requests.post(
                "http://localhost:9003/api/add_data",
                json={"key": "demo_key_2", "value": "Gossip Protocol Demo"},
                timeout=5
            )
            if response.status_code == 200:
                print("✅ Added demo data to node3")
        except Exception as e:
            print(f"❌ Failed to add demo data: {e}")
        
        print("📈 Watch the data propagate across all nodes!")
    
    def shutdown(self):
        """Shutdown all nodes"""
        print("\n🛑 Shutting down gossip network...")
        for process in self.processes:
            process.terminate()
        
        # Wait for processes to terminate
        for process in self.processes:
            process.wait()
        
        print("✅ All nodes stopped")

if __name__ == "__main__":
    network = GossipNetwork()
    
    # Handle Ctrl+C gracefully
    def signal_handler(sig, frame):
        network.shutdown()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    
    network.start_network()
