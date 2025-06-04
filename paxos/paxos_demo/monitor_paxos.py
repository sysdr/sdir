#!/usr/bin/env python3
"""
Real-time monitoring for Paxos consensus algorithm
Collects metrics on proposal success rate, latency, and failure patterns
"""

import json
import time
import threading
import subprocess
from datetime import datetime, timedelta
from collections import defaultdict, deque

class PaxosMonitor:
    def __init__(self, log_file='logs/paxos_simulation.log'):
        self.log_file = log_file
        self.metrics = {
            'proposals_total': 0,
            'proposals_successful': 0,
            'proposals_failed': 0,
            'consensus_time_history': deque(maxlen=100),
            'failure_patterns': defaultdict(int),
            'active_nodes': set(),
            'crashed_nodes': set()
        }
        self.monitoring = False
        
    def parse_log_line(self, line):
        """Parse log line and extract metrics"""
        if 'Starting proposal' in line:
            self.metrics['proposals_total'] += 1
            
        elif 'CONSENSUS ACHIEVED' in line:
            self.metrics['proposals_successful'] += 1
            
        elif 'FAILED' in line:
            self.metrics['proposals_failed'] += 1
            
        elif 'CRASHED' in line:
            if 'Node' in line:
                node_id = line.split('Node ')[1].split(' ')[0]
                self.metrics['crashed_nodes'].add(node_id)
                self.metrics['active_nodes'].discard(node_id)
                
        elif 'RECOVERED' in line:
            if 'Node' in line:
                node_id = line.split('Node ')[1].split(' ')[0]
                self.metrics['active_nodes'].add(node_id)
                self.metrics['crashed_nodes'].discard(node_id)
    
    def monitor_logs(self):
        """Monitor log file for new entries"""
        try:
            with open(self.log_file, 'r') as f:
                # Seek to end of file
                f.seek(0, 2)
                
                while self.monitoring:
                    line = f.readline()
                    if line:
                        self.parse_log_line(line.strip())
                    else:
                        time.sleep(0.1)
                        
        except FileNotFoundError:
            print(f"⚠️  Log file {self.log_file} not found")
            
    def start_monitoring(self):
        """Start monitoring in background thread"""
        self.monitoring = True
        self.monitor_thread = threading.Thread(target=self.monitor_logs)
        self.monitor_thread.daemon = True
        self.monitor_thread.start()
        
    def stop_monitoring(self):
        """Stop monitoring"""
        self.monitoring = False
        if hasattr(self, 'monitor_thread'):
            self.monitor_thread.join(timeout=1)
    
    def get_success_rate(self):
        """Calculate proposal success rate"""
        total = self.metrics['proposals_total']
        if total == 0:
            return 0.0
        return (self.metrics['proposals_successful'] / total) * 100
    
    def get_availability(self):
        """Calculate system availability based on active nodes"""
        total_nodes = len(self.metrics['active_nodes']) + len(self.metrics['crashed_nodes'])
        if total_nodes == 0:
            return 100.0
        return (len(self.metrics['active_nodes']) / total_nodes) * 100
    
    def display_dashboard(self):
        """Display real-time metrics dashboard"""
        while self.monitoring:
            # Clear screen (works on most terminals)
            print('\033[2J\033[H')
            
            print("🎯 Paxos Consensus Monitoring Dashboard")
            print("=" * 50)
            print(f"📊 Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print()
            
            # Proposal metrics
            print("📈 Proposal Metrics")
            print("-" * 20)
            print(f"Total Proposals: {self.metrics['proposals_total']}")
            print(f"Successful: {self.metrics['proposals_successful']}")
            print(f"Failed: {self.metrics['proposals_failed']}")
            print(f"Success Rate: {self.get_success_rate():.1f}%")
            print()
            
            # Node status
            print("🖥️  Node Status")
            print("-" * 15)
            print(f"Active Nodes: {len(self.metrics['active_nodes'])}")
            print(f"Crashed Nodes: {len(self.metrics['crashed_nodes'])}")
            print(f"System Availability: {self.get_availability():.1f}%")
            print()
            
            # Recent activity
            print("🔄 Recent Activity")
            print("-" * 18)
            if self.metrics['active_nodes']:
                print(f"Active: {', '.join(sorted(self.metrics['active_nodes']))}")
            if self.metrics['crashed_nodes']:
                print(f"Crashed: {', '.join(sorted(self.metrics['crashed_nodes']))}")
            print()
            
            print("Press Ctrl+C to stop monitoring")
            time.sleep(2)

def main():
    """Main monitoring function"""
    monitor = PaxosMonitor()
    
    try:
        print("🚀 Starting Paxos monitoring...")
        monitor.start_monitoring()
        monitor.display_dashboard()
        
    except KeyboardInterrupt:
        print("\n🛑 Stopping monitor...")
        monitor.stop_monitoring()
        
        # Final summary
        print("\n📊 Final Metrics Summary")
        print("=" * 30)
        print(f"Total Proposals: {monitor.metrics['proposals_total']}")
        print(f"Success Rate: {monitor.get_success_rate():.1f}%")
        print(f"System Availability: {monitor.get_availability():.1f}%")

if __name__ == "__main__":
    main()
