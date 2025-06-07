#!/usr/bin/env python3

import requests
import json
import time
from typing import Dict, List, Tuple
import threading

class GossipConfigTuner:
    """Dynamic configuration tuner for gossip protocol parameters"""
    
    def __init__(self, nodes: List[Tuple[str, str, int]]):
        self.nodes = nodes
        self.current_config = self.get_default_config()
        self.performance_history = []
        
    def get_default_config(self) -> Dict:
        """Get default gossip configuration"""
        return {
            'gossip_interval': 2.0,
            'fanout': 3,
            'max_excitement': 10,
            'excitement_threshold': 2,
            'ping_timeout': 1.0,
            'ping_interval': 5.0,
            'suspect_timeout': 10.0
        }
    
    def interactive_tuning_session(self):
        """Run interactive configuration tuning session"""
        print("🎛️  Gossip Protocol Configuration Tuner")
        print("=======================================")
        print("Adjust parameters in real-time and observe performance impact")
        
        while True:
            self.display_current_config()
            self.display_current_performance()
            
            print("\nAvailable commands:")
            print("  1. Adjust gossip interval")
            print("  2. Adjust fanout")
            print("  3. Adjust excitement parameters")
            print("  4. Adjust SWIM parameters")
            print("  5. Run performance test")
            print("  6. Auto-optimize configuration")
            print("  7. Reset to defaults")
            print("  8. Export configuration")
            print("  9. Exit")
            
            choice = input("\nEnter command (1-9): ").strip()
            
            if choice == '1':
                self.adjust_gossip_interval()
            elif choice == '2':
                self.adjust_fanout()
            elif choice == '3':
                self.adjust_excitement_params()
            elif choice == '4':
                self.adjust_swim_params()
            elif choice == '5':
                self.run_performance_test()
            elif choice == '6':
                self.auto_optimize()
            elif choice == '7':
                self.reset_to_defaults()
            elif choice == '8':
                self.export_configuration()
            elif choice == '9':
                print("Exiting configuration tuner...")
                break
            else:
                print("Invalid choice. Please try again.")
    
    def display_current_config(self):
        """Display current configuration"""
        print("\n📋 Current Configuration:")
        print("-" * 25)
        for key, value in self.current_config.items():
            unit = self.get_parameter_unit(key)
            print(f"  {key:20}: {value:>8}{unit}")
    
    def get_parameter_unit(self, param: str) -> str:
        """Get unit for parameter display"""
        time_params = ['gossip_interval', 'ping_timeout', 'ping_interval', 'suspect_timeout']
        if param in time_params:
            return 's'
        return ''
    
    def display_current_performance(self):
        """Display current performance metrics"""
        print("\n📊 Current Performance:")
        print("-" * 23)
        
        try:
            total_sent = 0
            total_received = 0
            total_rounds = 0
            active_nodes = 0
            
            for node_id, host, port in self.nodes:
                try:
                    response = requests.get(f"http://{host}:{port}/api/status", timeout=2)
                    if response.status_code == 200:
                        data = response.json()
                        stats = data.get('stats', {})
                        
                        total_sent += stats.get('messages_sent', 0)
                        total_received += stats.get('messages_received', 0)
                        total_rounds += stats.get('gossip_rounds', 0)
                        active_nodes += 1
                        
                except:
                    pass
            
            if active_nodes > 0:
                avg_sent = total_sent / active_nodes
                avg_received = total_received / active_nodes
                avg_rounds = total_rounds / active_nodes
                
                print(f"  Active nodes:      {active_nodes:>8}")
                print(f"  Avg msgs sent:     {avg_sent:>8.1f}")
                print(f"  Avg msgs received: {avg_received:>8.1f}")
                print(f"  Avg gossip rounds: {avg_rounds:>8.1f}")
                
                # Calculate efficiency
                if total_sent > 0:
                    efficiency = (total_received / total_sent) * 100
                    print(f"  Message efficiency:{efficiency:>8.1f}%")
            else:
                print("  No active nodes detected")
                
        except Exception as e:
            print(f"  Error collecting metrics: {e}")
    
    def adjust_gossip_interval(self):
        """Adjust gossip interval parameter"""
        current = self.current_config['gossip_interval']
        print(f"\nCurrent gossip interval: {current}s")
        print("Recommended range: 0.1s - 10.0s")
        print("  • Lower values: Faster propagation, higher load")
        print("  • Higher values: Slower propagation, lower load")
        
        try:
            new_value = float(input("Enter new gossip interval (seconds): "))
            if 0.1 <= new_value <= 10.0:
                self.current_config['gossip_interval'] = new_value
                self.apply_configuration()
                print(f"✅ Gossip interval updated to {new_value}s")
            else:
                print("❌ Value out of recommended range")
        except ValueError:
            print("❌ Invalid number format")
    
    def adjust_fanout(self):
        """Adjust fanout parameter"""
        current = self.current_config['fanout']
        cluster_size = len(self.nodes)
        optimal_fanout = max(2, int(1.5 * (cluster_size ** 0.5)))
        
        print(f"\nCurrent fanout: {current}")
        print(f"Cluster size: {cluster_size}")
        print(f"Recommended range: 2 - {cluster_size}")
        print(f"Optimal fanout: ~{optimal_fanout}")
        print("  • Lower values: Less network load, slower convergence")
        print("  • Higher values: More network load, faster convergence")
        
        try:
            new_value = int(input("Enter new fanout: "))
            if 1 <= new_value <= cluster_size:
                self.current_config['fanout'] = new_value
                self.apply_configuration()
                print(f"✅ Fanout updated to {new_value}")
            else:
                print("❌ Value out of valid range")
        except ValueError:
            print("❌ Invalid number format")
    
    def adjust_excitement_params(self):
        """Adjust excitement-related parameters"""
        print(f"\nCurrent excitement parameters:")
        print(f"  Max excitement: {self.current_config['max_excitement']}")
        print(f"  Excitement threshold: {self.current_config['excitement_threshold']}")
        
        print("\nExcitement controls rumor mongering:")
        print("  • Max excitement: Initial enthusiasm for new information")
        print("  • Threshold: Minimum excitement before stopping gossip")
        
        try:
            max_excitement = int(input("Enter new max excitement (1-20): "))
            threshold = int(input("Enter new excitement threshold (0-10): "))
            
            if 1 <= max_excitement <= 20 and 0 <= threshold <= 10 and threshold < max_excitement:
                self.current_config['max_excitement'] = max_excitement
                self.current_config['excitement_threshold'] = threshold
                self.apply_configuration()
                print("✅ Excitement parameters updated")
            else:
                print("❌ Invalid parameter values")
        except ValueError:
            print("❌ Invalid number format")
    
    def adjust_swim_params(self):
        """Adjust SWIM failure detection parameters"""
        print(f"\nCurrent SWIM parameters:")
        print(f"  Ping timeout: {self.current_config['ping_timeout']}s")
        print(f"  Ping interval: {self.current_config['ping_interval']}s")
        print(f"  Suspect timeout: {self.current_config['suspect_timeout']}s")
        
        print("\nSWIM parameters control failure detection:")
        print("  • Ping timeout: How long to wait for ping response")
        print("  • Ping interval: How often to ping other nodes")
        print("  • Suspect timeout: How long to wait before declaring failure")
        
        try:
            ping_timeout = float(input("Enter new ping timeout (seconds): "))
            ping_interval = float(input("Enter new ping interval (seconds): "))
            suspect_timeout = float(input("Enter new suspect timeout (seconds): "))
            
            if (0.1 <= ping_timeout <= 5.0 and 
                1.0 <= ping_interval <= 30.0 and 
                5.0 <= suspect_timeout <= 60.0 and
                suspect_timeout > ping_interval > ping_timeout):
                
                self.current_config['ping_timeout'] = ping_timeout
                self.current_config['ping_interval'] = ping_interval
                self.current_config['suspect_timeout'] = suspect_timeout
                self.apply_configuration()
                print("✅ SWIM parameters updated")
            else:
                print("❌ Invalid parameter relationships or ranges")
        except ValueError:
            print("❌ Invalid number format")
    
    def run_performance_test(self):
        """Run quick performance test with current configuration"""
        print("\n🧪 Running performance test...")
        
        # Send test messages and measure propagation time
        test_data = {
            'key': f'perf_test_{int(time.time())}',
            'value': f'test_value_{time.time()}',
            'timestamp': time.time()
        }
        
        start_time = time.time()
        
        try:
            # Send to first node
            response = requests.post(
                f"http://{self.nodes[0][1]}:{self.nodes[0][2]}/api/add_data",
                json=test_data,
                timeout=5
            )
            
            if response.status_code == 200:
                # Wait for propagation to other nodes
                max_wait = 30
                propagation_times = []
                
                for node_id, host, port in self.nodes[1:]:  # Skip sender
                    node_start = time.time()
                    
                    for attempt in range(max_wait * 10):  # Check every 100ms
                        try:
                            response = requests.get(f"http://{host}:{port}/api/status", timeout=1)
                            if response.status_code == 200:
                                data = response.json()
                                local_data = data.get('local_data', {})
                                
                                if test_data['key'] in local_data:
                                    propagation_time = time.time() - start_time
                                    propagation_times.append(propagation_time)
                                    print(f"  ✅ {node_id}: {propagation_time:.2f}s")
                                    break
                        except:
                            pass
                        
                        time.sleep(0.1)
                    else:
                        print(f"  ❌ {node_id}: timeout")
                
                if propagation_times:
                    avg_propagation = sum(propagation_times) / len(propagation_times)
                    max_propagation = max(propagation_times)
                    
                    performance_score = {
                        'config': self.current_config.copy(),
                        'avg_propagation': avg_propagation,
                        'max_propagation': max_propagation,
                        'success_rate': len(propagation_times) / (len(self.nodes) - 1),
                        'timestamp': time.time()
                    }
                    
                    self.performance_history.append(performance_score)
                    
                    print(f"\n📊 Performance Results:")
                    print(f"  Average propagation: {avg_propagation:.2f}s")
                    print(f"  Maximum propagation: {max_propagation:.2f}s")
                    print(f"  Success rate: {performance_score['success_rate']:.1%}")
                else:
                    print("❌ No successful propagations measured")
            else:
                print("❌ Failed to send test message")
                
        except Exception as e:
            print(f"❌ Performance test failed: {e}")
    
    def auto_optimize(self):
        """Automatically optimize configuration based on cluster characteristics"""
        print("\n🤖 Auto-optimizing configuration...")
        
        cluster_size = len(self.nodes)
        
        # Calculate optimal parameters based on cluster size and network conditions
        optimal_config = {
            'gossip_interval': max(0.5, min(5.0, 2.0 / (cluster_size ** 0.3))),
            'fanout': max(2, min(cluster_size, int(1.5 * (cluster_size ** 0.5)))),
            'max_excitement': min(15, max(5, cluster_size // 2)),
            'excitement_threshold': 2,
            'ping_timeout': 1.0,
            'ping_interval': max(2.0, min(10.0, cluster_size * 0.5)),
            'suspect_timeout': max(5.0, min(30.0, cluster_size * 1.0))
        }
        
        print("Calculated optimal configuration:")
        for key, value in optimal_config.items():
            current = self.current_config[key]
            unit = self.get_parameter_unit(key)
            change = "→" if abs(current - value) > 0.001 else "="
            print(f"  {key:20}: {current:>6.1f}{unit} {change} {value:>6.1f}{unit}")
        
        apply = input("\nApply optimized configuration? (y/n): ").strip().lower()
        if apply == 'y':
            self.current_config = optimal_config
            self.apply_configuration()
            print("✅ Optimized configuration applied")
            
            # Run performance test with new config
            print("\nTesting optimized configuration...")
            time.sleep(2)  # Give nodes time to adjust
            self.run_performance_test()
        else:
            print("Configuration unchanged")
    
    def reset_to_defaults(self):
        """Reset configuration to default values"""
        confirm = input("Reset all parameters to defaults? (y/n): ").strip().lower()
        if confirm == 'y':
            self.current_config = self.get_default_config()
            self.apply_configuration()
            print("✅ Configuration reset to defaults")
        else:
            print("Configuration unchanged")
    
    def export_configuration(self):
        """Export current configuration to file"""
        config_export = {
            'gossip_config': self.current_config,
            'performance_history': self.performance_history,
            'export_timestamp': time.time(),
            'cluster_size': len(self.nodes)
        }
        
        filename = f"gossip_config_{int(time.time())}.json"
        with open(filename, 'w') as f:
            json.dump(config_export, f, indent=2)
        
        print(f"✅ Configuration exported to {filename}")
    
    def apply_configuration(self):
        """Apply current configuration to all nodes"""
        # In a real implementation, you would send the new configuration
        # to each node via an API endpoint. For this demo, we just simulate it.
        print("🔄 Applying configuration to all nodes...")
        
        success_count = 0
        for node_id, host, port in self.nodes:
            try:
                # Simulate configuration update
                # In reality: requests.post(f"http://{host}:{port}/api/update_config", json=self.current_config)
                success_count += 1
            except Exception as e:
                print(f"  ❌ Failed to update {node_id}: {e}")
        
        if success_count == len(self.nodes):
            print(f"✅ Configuration applied to all {success_count} nodes")
        else:
            print(f"⚠️  Configuration applied to {success_count}/{len(self.nodes)} nodes")

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
    
    tuner = GossipConfigTuner(nodes)
    tuner.interactive_tuning_session()
