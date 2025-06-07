#!/usr/bin/env python3

import requests
import time
import json
import threading
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from collections import deque, defaultdict
import numpy as np

class GossipMonitoringDashboard:
    """Real-time monitoring dashboard for gossip protocol"""
    
    def __init__(self, nodes):
        self.nodes = nodes
        self.running = True
        
        # Data storage for real-time plotting
        self.timestamps = deque(maxlen=100)
        self.metrics_history = {
            'messages_sent': deque(maxlen=100),
            'messages_received': deque(maxlen=100),
            'gossip_rounds': deque(maxlen=100),
            'failed_pings': deque(maxlen=100),
            'active_nodes': deque(maxlen=100),
            'queue_sizes': deque(maxlen=100),
            'convergence_time': deque(maxlen=100),
            'message_efficiency': deque(maxlen=100)
        }
        
        # Per-node metrics
        self.node_metrics = {node[0]: defaultdict(deque) for node in nodes}
        
        # Alerts and thresholds
        self.alert_thresholds = {
            'max_convergence_time': 10.0,  # seconds
            'min_message_efficiency': 0.8,  # 80%
            'max_failed_ping_ratio': 0.1,   # 10%
            'min_active_nodes': len(nodes) * 0.8  # 80% of nodes
        }
        
        self.active_alerts = []
    
    def start_monitoring(self):
        """Start the monitoring dashboard"""
        print("📊 Starting Gossip Protocol Monitoring Dashboard")
        print("================================================")
        
        # Start data collection thread
        collection_thread = threading.Thread(target=self.collect_metrics_loop, daemon=True)
        collection_thread.start()
        
        # Start alert monitoring thread
        alert_thread = threading.Thread(target=self.monitor_alerts_loop, daemon=True)
        alert_thread.start()
        
        # Start real-time plotting
        self.start_real_time_plots()
    
    def collect_metrics_loop(self):
        """Continuously collect metrics from all nodes"""
        while self.running:
            try:
                self.collect_cluster_metrics()
                time.sleep(2)  # Collect every 2 seconds
            except Exception as e:
                print(f"Error collecting metrics: {e}")
                time.sleep(5)
    
    def collect_cluster_metrics(self):
        """Collect metrics from all nodes in the cluster"""
        timestamp = datetime.now()
        
        total_sent = 0
        total_received = 0
        total_rounds = 0
        total_failed_pings = 0
        total_queue_size = 0
        active_node_count = 0
        
        # Collect from each node
        for node_id, host, port in self.nodes:
            try:
                response = requests.get(f"http://{host}:{port}/api/status", timeout=2)
                if response.status_code == 200:
                    data = response.json()
                    stats = data.get('stats', {})
                    
                    # Aggregate cluster metrics
                    sent = stats.get('messages_sent', 0)
                    received = stats.get('messages_received', 0)
                    rounds = stats.get('gossip_rounds', 0)
                    failed_pings = stats.get('failed_pings', 0)
                    queue_size = data.get('gossip_queue_size', 0)
                    
                    total_sent += sent
                    total_received += received
                    total_rounds += rounds
                    total_failed_pings += failed_pings
                    total_queue_size += queue_size
                    active_node_count += 1
                    
                    # Store per-node metrics
                    self.node_metrics[node_id]['messages_sent'].append(sent)
                    self.node_metrics[node_id]['messages_received'].append(received)
                    self.node_metrics[node_id]['gossip_rounds'].append(rounds)
                    self.node_metrics[node_id]['failed_pings'].append(failed_pings)
                    self.node_metrics[node_id]['queue_size'].append(queue_size)
                    
                    # Keep only last 100 points per node
                    for metric in self.node_metrics[node_id].values():
                        if len(metric) > 100:
                            metric.popleft()
                
            except Exception as e:
                print(f"Failed to collect from {node_id}: {e}")
        
        # Calculate derived metrics
        message_efficiency = (total_received / max(total_sent, 1)) * 100
        failed_ping_ratio = total_failed_pings / max(total_rounds, 1)
        
        # Store cluster-wide metrics
        self.timestamps.append(timestamp)
        self.metrics_history['messages_sent'].append(total_sent)
        self.metrics_history['messages_received'].append(total_received)
        self.metrics_history['gossip_rounds'].append(total_rounds)
        self.metrics_history['failed_pings'].append(total_failed_pings)
        self.metrics_history['active_nodes'].append(active_node_count)
        self.metrics_history['queue_sizes'].append(total_queue_size)
        self.metrics_history['message_efficiency'].append(message_efficiency)
        
        # Print current status
        self.print_current_status(timestamp, active_node_count, total_sent, 
                                 total_received, message_efficiency, failed_ping_ratio)
    
    def print_current_status(self, timestamp, active_nodes, total_sent, 
                           total_received, efficiency, failed_ratio):
        """Print current cluster status"""
        print(f"\r[{timestamp.strftime('%H:%M:%S')}] "
              f"Nodes: {active_nodes}/{len(self.nodes)} | "
              f"Sent: {total_sent} | "
              f"Received: {total_received} | "
              f"Efficiency: {efficiency:.1f}% | "
              f"Failed Ping Ratio: {failed_ratio:.3f}", end="")
    
    def monitor_alerts_loop(self):
        """Monitor for alert conditions"""
        while self.running:
            try:
                self.check_alert_conditions()
                time.sleep(5)  # Check every 5 seconds
            except Exception as e:
                print(f"Error in alert monitoring: {e}")
                time.sleep(10)
    
    def check_alert_conditions(self):
        """Check for various alert conditions"""
        if len(self.metrics_history['active_nodes']) == 0:
            return
        
        current_time = datetime.now()
        new_alerts = []
        
        # Check active nodes
        active_nodes = self.metrics_history['active_nodes'][-1]
        if active_nodes < self.alert_thresholds['min_active_nodes']:
            new_alerts.append({
                'type': 'NODE_FAILURE',
                'message': f"Only {active_nodes}/{len(self.nodes)} nodes active",
                'severity': 'HIGH',
                'timestamp': current_time
            })
        
        # Check message efficiency
        if len(self.metrics_history['message_efficiency']) > 0:
            efficiency = self.metrics_history['message_efficiency'][-1] / 100
            if efficiency < self.alert_thresholds['min_message_efficiency']:
                new_alerts.append({
                    'type': 'LOW_EFFICIENCY',
                    'message': f"Message efficiency {efficiency:.1%} below threshold",
                    'severity': 'MEDIUM',
                    'timestamp': current_time
                })
        
        # Check failed ping ratio
        if (len(self.metrics_history['failed_pings']) > 0 and 
            len(self.metrics_history['gossip_rounds']) > 0):
            failed_pings = self.metrics_history['failed_pings'][-1]
            rounds = self.metrics_history['gossip_rounds'][-1]
            if rounds > 0:
                failed_ratio = failed_pings / rounds
                if failed_ratio > self.alert_thresholds['max_failed_ping_ratio']:
                    new_alerts.append({
                        'type': 'HIGH_FAILURE_RATE',
                        'message': f"Failed ping ratio {failed_ratio:.1%} above threshold",
                        'severity': 'MEDIUM',
                        'timestamp': current_time
                    })
        
        # Add new alerts and remove old ones
        self.active_alerts.extend(new_alerts)
        
        # Remove alerts older than 5 minutes
        cutoff_time = current_time - timedelta(minutes=5)
        self.active_alerts = [alert for alert in self.active_alerts 
                             if alert['timestamp'] > cutoff_time]
        
        # Print new alerts
        for alert in new_alerts:
            print(f"\n🚨 ALERT [{alert['severity']}] {alert['type']}: {alert['message']}")
    
    def start_real_time_plots(self):
        """Start real-time plotting dashboard"""
        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        fig.suptitle('Gossip Protocol Real-Time Monitoring Dashboard', fontsize=16)
        
        # Flatten axes for easier indexing
        axes = axes.flatten()
        
        def update_plots(frame):
            if len(self.timestamps) == 0:
                return
            
            # Convert timestamps to relative seconds for plotting
            base_time = self.timestamps[0]
            time_points = [(t - base_time).total_seconds() for t in self.timestamps]
            
            # Clear all axes
            for ax in axes:
                ax.clear()
            
            # Plot 1: Messages Sent/Received
            if len(self.metrics_history['messages_sent']) > 0:
                axes[0].plot(time_points, list(self.metrics_history['messages_sent']), 
                           'b-', label='Sent', linewidth=2)
                axes[0].plot(time_points, list(self.metrics_history['messages_received']), 
                           'r-', label='Received', linewidth=2)
                axes[0].set_title('Message Flow')
                axes[0].set_ylabel('Message Count')
                axes[0].legend()
                axes[0].grid(True, alpha=0.3)
            
            # Plot 2: Message Efficiency
            if len(self.metrics_history['message_efficiency']) > 0:
                axes[1].plot(time_points, list(self.metrics_history['message_efficiency']), 
                           'g-', linewidth=2)
                axes[1].axhline(y=self.alert_thresholds['min_message_efficiency'] * 100, 
                               color='r', linestyle='--', alpha=0.7, label='Threshold')
                axes[1].set_title('Message Efficiency')
                axes[1].set_ylabel('Efficiency (%)')
                axes[1].set_ylim(0, 100)
                axes[1].legend()
                axes[1].grid(True, alpha=0.3)
            
            # Plot 3: Active Nodes
            if len(self.metrics_history['active_nodes']) > 0:
                axes[2].plot(time_points, list(self.metrics_history['active_nodes']), 
                           'purple', linewidth=2, marker='o', markersize=4)
                axes[2].axhline(y=self.alert_thresholds['min_active_nodes'], 
                               color='r', linestyle='--', alpha=0.7, label='Threshold')
                axes[2].set_title('Active Nodes')
                axes[2].set_ylabel('Node Count')
                axes[2].set_ylim(0, len(self.nodes) + 1)
                axes[2].legend()
                axes[2].grid(True, alpha=0.3)
            
            # Plot 4: Gossip Queue Sizes
            if len(self.metrics_history['queue_sizes']) > 0:
                axes[3].plot(time_points, list(self.metrics_history['queue_sizes']), 
                           'orange', linewidth=2)
                axes[3].set_title('Total Queue Size')
                axes[3].set_ylabel('Queue Entries')
                axes[3].grid(True, alpha=0.3)
            
            # Plot 5: Failed Pings
            if len(self.metrics_history['failed_pings']) > 0:
                axes[4].plot(time_points, list(self.metrics_history['failed_pings']), 
                           'red', linewidth=2)
                axes[4].set_title('Failed Pings')
                axes[4].set_ylabel('Failure Count')
                axes[4].grid(True, alpha=0.3)
            
            # Plot 6: Per-Node Message Distribution
            if self.node_metrics:
                node_names = []
                current_sent = []
                current_received = []
                
                for node_id in self.node_metrics:
                    if (len(self.node_metrics[node_id]['messages_sent']) > 0 and
                        len(self.node_metrics[node_id]['messages_received']) > 0):
                        node_names.append(node_id)
                        current_sent.append(self.node_metrics[node_id]['messages_sent'][-1])
                        current_received.append(self.node_metrics[node_id]['messages_received'][-1])
                
                if node_names:
                    x_pos = np.arange(len(node_names))
                    width = 0.35
                    
                    axes[5].bar(x_pos - width/2, current_sent, width, 
                               label='Sent', alpha=0.8, color='blue')
                    axes[5].bar(x_pos + width/2, current_received, width, 
                               label='Received', alpha=0.8, color='red')
                    
                    axes[5].set_title('Per-Node Message Distribution')
                    axes[5].set_ylabel('Message Count')
                    axes[5].set_xticks(x_pos)
                    axes[5].set_xticklabels(node_names, rotation=45)
                    axes[5].legend()
                    axes[5].grid(True, alpha=0.3)
            
            # Set common x-label for time-series plots
            for i in range(5):  # Skip the bar chart
                axes[i].set_xlabel('Time (seconds)')
            
            plt.tight_layout()
        
        # Start animation
        ani = animation.FuncAnimation(fig, update_plots, interval=2000, cache_frame_data=False)
        
        try:
            plt.show()
        except KeyboardInterrupt:
            print("\nMonitoring dashboard stopped")
        finally:
            self.running = False
    
    def generate_monitoring_report(self):
        """Generate comprehensive monitoring report"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'cluster_size': len(self.nodes),
            'monitoring_duration': len(self.timestamps) * 2,  # seconds
            'metrics_summary': {},
            'alerts': self.active_alerts,
            'node_health': {}
        }
        
        # Calculate summary statistics
        if len(self.metrics_history['messages_sent']) > 0:
            report['metrics_summary'] = {
                'total_messages_sent': sum(self.metrics_history['messages_sent']),
                'total_messages_received': sum(self.metrics_history['messages_received']),
                'avg_message_efficiency': np.mean(list(self.metrics_history['message_efficiency'])),
                'avg_active_nodes': np.mean(list(self.metrics_history['active_nodes'])),
                'total_failed_pings': sum(self.metrics_history['failed_pings']),
                'avg_queue_size': np.mean(list(self.metrics_history['queue_sizes']))
            }
        
        # Per-node health summary
        for node_id in self.node_metrics:
            if len(self.node_metrics[node_id]['messages_sent']) > 0:
                report['node_health'][node_id] = {
                    'total_sent': sum(self.node_metrics[node_id]['messages_sent']),
                    'total_received': sum(self.node_metrics[node_id]['messages_received']),
                    'avg_queue_size': np.mean(list(self.node_metrics[node_id]['queue_size'])),
                    'total_failed_pings': sum(self.node_metrics[node_id]['failed_pings'])
                }
        
        # Save report
        filename = f"gossip_monitoring_report_{int(time.time())}.json"
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        print(f"\n📄 Monitoring report saved to: {filename}")
        return report

class SimpleMonitoringDashboard:
    """Simplified monitoring dashboard for systems without matplotlib"""
    
    def __init__(self, nodes):
        self.nodes = nodes
        self.running = True
        self.metrics_history = []
        
    def start_monitoring(self):
        """Start simple text-based monitoring"""
        print("📊 Starting Simple Gossip Protocol Monitoring")
        print("==============================================")
        print("Press Ctrl+C to stop monitoring")
        
        try:
            while self.running:
                self.collect_and_display_metrics()
                time.sleep(5)
        except KeyboardInterrupt:
            print("\n\nMonitoring stopped by user")
            self.generate_simple_report()
    
    def collect_and_display_metrics(self):
        """Collect and display metrics in text format"""
        timestamp = datetime.now()
        
        print(f"\n[{timestamp.strftime('%H:%M:%S')}] Cluster Status:")
        print("-" * 50)
        
        total_sent = 0
        total_received = 0
        active_nodes = 0
        
        for node_id, host, port in self.nodes:
            try:
                response = requests.get(f"http://{host}:{port}/api/status", timeout=2)
                if response.status_code == 200:
                    data = response.json()
                    stats = data.get('stats', {})
                    
                    sent = stats.get('messages_sent', 0)
                    received = stats.get('messages_received', 0)
                    rounds = stats.get('gossip_rounds', 0)
                    queue_size = data.get('gossip_queue_size', 0)
                    
                    print(f"  {node_id:>6}: Sent: {sent:>4} | Received: {received:>4} | "
                          f"Rounds: {rounds:>3} | Queue: {queue_size:>2}")
                    
                    total_sent += sent
                    total_received += received
                    active_nodes += 1
                else:
                    print(f"  {node_id:>6}: ❌ HTTP {response.status_code}")
            except Exception as e:
                print(f"  {node_id:>6}: ❌ {str(e)[:30]}")
        
        # Calculate and display summary
        efficiency = (total_received / max(total_sent, 1)) * 100
        
        print(f"\nCluster Summary:")
        print(f"  Active Nodes: {active_nodes}/{len(self.nodes)}")
        print(f"  Total Sent: {total_sent}")
        print(f"  Total Received: {total_received}")
        print(f"  Efficiency: {efficiency:.1f}%")
        
        # Store metrics for report
        self.metrics_history.append({
            'timestamp': timestamp,
            'active_nodes': active_nodes,
            'total_sent': total_sent,
            'total_received': total_received,
            'efficiency': efficiency
        })
    
    def generate_simple_report(self):
        """Generate simple text report"""
        if not self.metrics_history:
            print("No metrics collected")
            return
        
        print("\n📊 Monitoring Summary Report")
        print("============================")
        
        # Calculate averages
        avg_active = np.mean([m['active_nodes'] for m in self.metrics_history])
        avg_efficiency = np.mean([m['efficiency'] for m in self.metrics_history])
        total_messages = sum([m['total_sent'] for m in self.metrics_history])
        
        print(f"Monitoring Duration: {len(self.metrics_history) * 5} seconds")
        print(f"Average Active Nodes: {avg_active:.1f}/{len(self.nodes)}")
        print(f"Average Efficiency: {avg_efficiency:.1f}%")
        print(f"Total Messages Sent: {total_messages}")
        
        # Save simple report
        filename = f"simple_monitoring_report_{int(time.time())}.json"
        with open(filename, 'w') as f:
            json.dump(self.metrics_history, f, indent=2, default=str)
        
        print(f"\nDetailed report saved to: {filename}")

if __name__ == "__main__":
    nodes = [
        ("node1", "localhost", 9001),
        ("node2", "localhost", 9002),
        ("node3", "localhost", 9003),
        ("node4", "localhost", 9004),
        ("node5", "localhost", 9005)
    ]
    
    # Check if network is running
    try:
        response = requests.get("http://localhost:9001/api/status", timeout=2)
        if response.status_code != 200:
            print("❌ Gossip network not responding. Start with: python start_network.py")
            exit(1)
    except:
        print("❌ Gossip network not running. Start with: python start_network.py")
        exit(1)
    
    # Try to use full dashboard with matplotlib, fallback to simple version
    try:
        import matplotlib.pyplot as plt
        import matplotlib.animation as animation
        dashboard = GossipMonitoringDashboard(nodes)
        
        print("🎨 Using full monitoring dashboard with real-time plots")
        dashboard.start_monitoring()
        
    except ImportError:
        print("📊 matplotlib not available, using simple text-based monitoring")
        print("   Install matplotlib for full graphical dashboard: pip install matplotlib")
        
        dashboard = SimpleMonitoringDashboard(nodes)
        dashboard.start_monitoring()
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Monitoring stopped by user")
        if hasattr(dashboard, 'generate_monitoring_report'):
            dashboard.generate_monitoring_report()
        elif hasattr(dashboard, 'generate_simple_report'):
            dashboard.generate_simple_report()
    except Exception as e:
        print(f"\n❌ Error in monitoring: {e}")
        if hasattr(dashboard, 'generate_monitoring_report'):
            dashboard.generate_monitoring_report()
        elif hasattr(dashboard, 'generate_simple_report'):
            dashboard.generate_simple_report()