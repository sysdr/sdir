import asyncio
import subprocess
import time
import signal
import sys
import os
from typing import List

class ClusterManager:
    def __init__(self):
        self.processes: List[subprocess.Popen] = []
        self.running = False
    
    def start_cluster(self, num_nodes: int = 5):
        """Start a cluster of Raft nodes"""
        print(f"🚀 Starting {num_nodes}-node Raft cluster...")
        
        base_port = 8001
        ports = [base_port + i for i in range(num_nodes)]
        peer_list = ",".join(map(str, ports))
        
        for i in range(num_nodes):
            node_id = f"node{i+1}"
            port = ports[i]
            
            print(f"   Starting {node_id} on port {port}")
            
            process = subprocess.Popen([
                sys.executable, "node.py", 
                node_id, str(port), peer_list
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            self.processes.append(process)
            time.sleep(0.5)  # Stagger startup
        
        self.running = True
        print(f"\n✅ Cluster started successfully!")
        print(f"🌐 Web dashboards available at:")
        for i, port in enumerate(ports):
            print(f"   Node {i+1}: http://localhost:{port}")
        
        print(f"\n📊 Cluster status: http://localhost:{ports[0]}")
        print(f"💡 Press Ctrl+C to stop the cluster")
    
    def stop_cluster(self):
        """Stop all nodes in the cluster"""
        if not self.running:
            return
            
        print("\n🛑 Stopping cluster...")
        
        for i, process in enumerate(self.processes):
            try:
                process.terminate()
                process.wait(timeout=3)
                print(f"   Stopped node{i+1}")
            except subprocess.TimeoutExpired:
                process.kill()
                print(f"   Force killed node{i+1}")
            except Exception as e:
                print(f"   Error stopping node{i+1}: {e}")
        
        self.processes.clear()
        self.running = False
        print("✅ Cluster stopped")
    
    def wait_for_interrupt(self):
        """Wait for keyboard interrupt"""
        try:
            while self.running:
                time.sleep(1)
                # Check if any process died
                for i, process in enumerate(self.processes):
                    if process.poll() is not None:
                        print(f"⚠️  Node{i+1} process died unexpectedly")
        except KeyboardInterrupt:
            pass
        finally:
            self.stop_cluster()

def main():
    num_nodes = 5
    if len(sys.argv) > 1:
        try:
            num_nodes = int(sys.argv[1])
            if num_nodes < 3:
                print("❌ Minimum 3 nodes required for Raft consensus")
                sys.exit(1)
        except ValueError:
            print("❌ Invalid number of nodes")
            sys.exit(1)
    
    cluster = ClusterManager()
    
    # Setup signal handlers
    def signal_handler(signum, frame):
        cluster.stop_cluster()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        cluster.start_cluster(num_nodes)
        cluster.wait_for_interrupt()
    except Exception as e:
        print(f"❌ Error: {e}")
        cluster.stop_cluster()

if __name__ == "__main__":
    main()
