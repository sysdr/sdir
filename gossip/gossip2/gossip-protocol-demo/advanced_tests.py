#!/usr/bin/env python3

import requests
import time
import json
import threading
import random
import statistics
import subprocess
import signal
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Tuple
import matplotlib.pyplot as plt
import numpy as np

class GossipBenchmark:
    """Advanced benchmarking and testing suite for gossip protocols"""
    
    def __init__(self):
        self.nodes = [
            ("node1", "localhost", 9001),
            ("node2", "localhost", 9002),
            ("node3", "localhost", 9003),
            ("node4", "localhost", 9004),
            ("node5", "localhost", 9005)
        ]
        self.results = {}
        
    def run_all_tests(self):
        """Run comprehensive test suite"""
        print("🚀 Advanced Gossip Protocol Test Suite")
        print("=====================================")
        
        self.test_propagation_latency()
        self.test_convergence_time()
        self.test_byzantine_tolerance()
        self.test_network_partition_recovery()
        self.test_load_performance()
        self.test_failure_detection_accuracy()
        self.generate_performance_report()
    
    def test_propagation_latency(self):
        """Test gossip propagation latency across different data sizes"""
        print("\n📊 Testing Propagation Latency")
        print("==============================")
        
        data_sizes = [100, 1000, 5000, 10000]  # bytes
        latencies = []
        
        for size in data_sizes:
            print(f"Testing with {size} byte payload...")
            
            # Generate test data
            test_data = {
                "key": f"latency_test_{size}",
                "value": "x" * size,
                "timestamp": time.time()
            }
            
            # Start timer and send to first node
            start_time = time.time()
            
            try:
                response = requests.post(
                    "http://localhost:9001/api/add_data",
                    json=test_data,
                    timeout=5
                )
                
                if response.status_code != 200:
                    print(f"❌ Failed to send data: {response.status_code}")
                    continue
                    
                # Poll other nodes until they have the data
                target_node = random.choice(self.nodes[1:])  # Skip sender
                max_wait = 30  # seconds
                poll_interval = 0.1
                
                for attempt in range(int(max_wait / poll_interval)):
                    try:
                        response = requests.get(
                            f"http://{target_node[1]}:{target_node[2]}/api/status",
                            timeout=2
                        )
                        
                        if response.status_code == 200:
                            data = response.json()
                            local_data = data.get('local_data', {})
                            
                            if test_data['key'] in local_data:
                                end_time = time.time()
                                latency = (end_time - start_time) * 1000  # ms
                                latencies.append(latency)
                                print(f"  ✅ Propagated in {latency:.2f}ms")
                                break
                    except:
                        pass
                    
                    time.sleep(poll_interval)
                else:
                    print(f"  ❌ Timeout waiting for propagation")
                    
            except Exception as e:
                print(f"  ❌ Error: {e}")
        
        if latencies:
            avg_latency = statistics.mean(latencies)
            max_latency = max(latencies)
            min_latency = min(latencies)
            
            print(f"\n📈 Latency Results:")
            print(f"  Average: {avg_latency:.2f}ms")
            print(f"  Min: {min_latency:.2f}ms")
            print(f"  Max: {max_latency:.2f}ms")
            
            self.results['propagation_latency'] = {
                'avg': avg_latency,
                'min': min_latency,
                'max': max_latency,
                'samples': latencies
            }
    
    def test_convergence_time(self):
        """Test time for all nodes to reach consistency"""
        print("\n⏱️  Testing Convergence Time")
        print("============================")
        
        convergence_times = []
        num_tests = 5
        
        for test_num in range(num_tests):
            print(f"Convergence test {test_num + 1}/{num_tests}")
            
            # Send unique data
            test_data = {
                "key": f"convergence_test_{test_num}_{int(time.time())}",
                "value": f"test_value_{random.randint(1000, 9999)}",
                "timestamp": time.time()
            }
            
            start_time = time.time()
            
            # Send to random node
            sender = random.choice(self.nodes)
            try:
                response = requests.post(
                    f"http://{sender[1]}:{sender[2]}/api/add_data",
                    json=test_data,
                    timeout=5
                )
                
                if response.status_code != 200:
                    print(f"  ❌ Failed to send data")
                    continue
                
                # Wait for all nodes to have the data
                max_wait = 60
                poll_interval = 0.5
                
                for attempt in range(int(max_wait / poll_interval)):
                    converged_count = 0
                    
                    for node in self.nodes:
                        try:
                            response = requests.get(
                                f"http://{node[1]}:{node[2]}/api/status",
                                timeout=2
                            )
                            
                            if response.status_code == 200:
                                data = response.json()
                                local_data = data.get('local_data', {})
                                
                                if (test_data['key'] in local_data and 
                                    local_data[test_data['key']] == test_data['value']):
                                    converged_count += 1
                        except:
                            pass
                    
                    if converged_count == len(self.nodes):
                        convergence_time = time.time() - start_time
                        convergence_times.append(convergence_time)
                        print(f"  ✅ Converged in {convergence_time:.2f}s")
                        break
                    
                    time.sleep(poll_interval)
                else:
                    print(f"  ❌ Failed to converge within {max_wait}s")
                    
            except Exception as e:
                print(f"  ❌ Error: {e}")
        
        if convergence_times:
            avg_convergence = statistics.mean(convergence_times)
            max_convergence = max(convergence_times)
            min_convergence = min(convergence_times)
            
            print(f"\n📈 Convergence Results:")
            print(f"  Average: {avg_convergence:.2f}s")
            print(f"  Min: {min_convergence:.2f}s")
            print(f"  Max: {max_convergence:.2f}s")
            
            self.results['convergence_time'] = {
                'avg': avg_convergence,
                'min': min_convergence,
                'max': max_convergence,
                'samples': convergence_times
            }
    
    def test_byzantine_tolerance(self):
        """Test resilience against Byzantine behaviors"""
        print("\n🛡️  Testing Byzantine Tolerance")
        print("===============================")
        
        # This is a simplified test - in production you'd need actual Byzantine nodes
        print("Simulating Byzantine behavior patterns...")
        
        # Test 1: Message dropping simulation
        print("\n1. Testing message drop tolerance")
        
        # Send multiple messages rapidly
        messages_sent = 0
        messages_received = {}
        
        for i in range(10):
            test_data = {
                "key": f"byzantine_test_{i}",
                "value": f"value_{i}",
                "timestamp": time.time()
            }
            
            try:
                response = requests.post(
                    "http://localhost:9001/api/add_data",
                    json=test_data,
                    timeout=2
                )
                
                if response.status_code == 200:
                    messages_sent += 1
                    
            except Exception as e:
                print(f"  Warning: Failed to send message {i}: {e}")
        
        time.sleep(10)  # Wait for propagation
        
        # Check how many messages reached all nodes
        for node in self.nodes:
            try:
                response = requests.get(
                    f"http://{node[1]}:{node[2]}/api/status",
                    timeout=2
                )
                
                if response.status_code == 200:
                    data = response.json()
                    local_data = data.get('local_data', {})
                    
                    received_count = sum(1 for key in local_data.keys() 
                                       if key.startswith('byzantine_test_'))
                    messages_received[node[0]] = received_count
                    
            except Exception as e:
                print(f"  Error checking {node[0]}: {e}")
        
        print(f"Messages sent: {messages_sent}")
        for node, count in messages_received.items():
            delivery_rate = (count / messages_sent) * 100 if messages_sent > 0 else 0
            print(f"  {node}: {count}/{messages_sent} ({delivery_rate:.1f}%)")
        
        self.results['byzantine_tolerance'] = {
            'messages_sent': messages_sent,
            'messages_received': messages_received
        }
    
    def test_network_partition_recovery(self):
        """Test recovery from simulated network partitions"""
        print("\n🔌 Testing Network Partition Recovery")
        print("====================================")
        
        print("This test requires manual network partition simulation.")
        print("In production, you would use tools like:")
        print("  - tc (traffic control) to add latency/drops")
        print("  - iptables to block specific connections")
        print("  - Docker network manipulation")
        print("  - Chaos engineering tools (Chaos Monkey, etc.)")
        
        # For this demo, we'll just verify the nodes can detect failures
        print("\nTesting failure detection capabilities...")
        
        failure_detection_scores = {}
        
        for node in self.nodes:
            try:
                response = requests.get(
                    f"http://{node[1]}:{node[2]}/api/status",
                    timeout=5
                )
                
                if response.status_code == 200:
                    data = response.json()
                    members = data.get('members', {})
                    stats = data.get('stats', {})
                    
                    alive_members = sum(1 for m in members.values() 
                                      if m.get('is_alive', False))
                    failed_pings = stats.get('failed_pings', 0)
                    gossip_rounds = stats.get('gossip_rounds', 1)
                    
                    # Calculate failure detection score
                    detection_ratio = failed_pings / max(gossip_rounds, 1)
                    failure_detection_scores[node[0]] = {
                        'alive_members': alive_members,
                        'failed_pings': failed_pings,
                        'detection_ratio': detection_ratio
                    }
                    
                    print(f"  {node[0]}: {alive_members} alive members, "
                          f"{failed_pings} failed pings, "
                          f"{detection_ratio:.3f} failure ratio")
                    
            except Exception as e:
                print(f"  ❌ {node[0]}: Error - {e}")
        
        self.results['partition_recovery'] = failure_detection_scores
    
    def test_load_performance(self):
        """Test performance under various load conditions"""
        print("\n⚡ Testing Load Performance")
        print("==========================")
        
        load_levels = [1, 5, 10, 20]  # messages per second
        performance_results = {}
        
        for load in load_levels:
            print(f"\nTesting {load} messages/second load...")
            
            messages_sent = 0
            errors = 0
            latencies = []
            
            # Run load test for 30 seconds
            test_duration = 30
            interval = 1.0 / load
            
            start_time = time.time()
            next_send_time = start_time
            
            while time.time() - start_time < test_duration:
                current_time = time.time()
                
                if current_time >= next_send_time:
                    # Send message
                    test_data = {
                        "key": f"load_test_{messages_sent}",
                        "value": f"load_value_{int(current_time)}",
                        "timestamp": current_time
                    }
                    
                    send_start = time.time()
                    try:
                        node = random.choice(self.nodes)
                        response = requests.post(
                            f"http://{node[1]}:{node[2]}/api/add_data",
                            json=test_data,
                            timeout=1
                        )
                        
                        if response.status_code == 200:
                            latency = (time.time() - send_start) * 1000
                            latencies.append(latency)
                            messages_sent += 1
                        else:
                            errors += 1
                            
                    except Exception:
                        errors += 1
                    
                    next_send_time += interval
                
                time.sleep(0.001)  # Small sleep to prevent busy waiting
            
            # Calculate performance metrics
            if latencies:
                avg_latency = statistics.mean(latencies)
                p95_latency = np.percentile(latencies, 95)
                p99_latency = np.percentile(latencies, 99)
                
                success_rate = (messages_sent / (messages_sent + errors)) * 100
                
                performance_results[load] = {
                    'messages_sent': messages_sent,
                    'errors': errors,
                    'success_rate': success_rate,
                    'avg_latency': avg_latency,
                    'p95_latency': p95_latency,
                    'p99_latency': p99_latency
                }
                
                print(f"  Messages sent: {messages_sent}")
                print(f"  Errors: {errors}")
                print(f"  Success rate: {success_rate:.1f}%")
                print(f"  Avg latency: {avg_latency:.2f}ms")
                print(f"  P95 latency: {p95_latency:.2f}ms")
                print(f"  P99 latency: {p99_latency:.2f}ms")
        
        self.results['load_performance'] = performance_results
    
    def test_failure_detection_accuracy(self):
        """Test SWIM failure detection accuracy"""
        print("\n🎯 Testing Failure Detection Accuracy")
        print("=====================================")
        
        # Get current member states from all nodes
        member_states = {}
        
        for node in self.nodes:
            try:
                response = requests.get(
                    f"http://{node[1]}:{node[2]}/api/status",
                    timeout=5
                )
                
                if response.status_code == 200:
                    data = response.json()
                    members = data.get('members', {})
                    
                    member_states[node[0]] = {}
                    for member_id, member_data in members.items():
                        member_states[node[0]][member_id] = member_data.get('is_alive', False)
                        
            except Exception as e:
                print(f"  Error checking {node[0]}: {e}")
        
        # Check consistency of member states across nodes
        print("Checking member state consistency...")
        
        all_members = set()
        for states in member_states.values():
            all_members.update(states.keys())
        
        consistency_score = 0
        total_checks = 0
        
        for member in all_members:
            member_states_list = []
            for node_states in member_states.values():
                if member in node_states:
                    member_states_list.append(node_states[member])
            
            if len(member_states_list) > 1:
                # Check if all nodes agree on this member's state
                if all(state == member_states_list[0] for state in member_states_list):
                    consistency_score += 1
                total_checks += 1
                
                print(f"  {member}: {member_states_list} {'✅' if len(set(member_states_list)) == 1 else '❌'}")
        
        consistency_percentage = (consistency_score / total_checks) * 100 if total_checks > 0 else 0
        print(f"\nConsistency score: {consistency_score}/{total_checks} ({consistency_percentage:.1f}%)")
        
        self.results['failure_detection'] = {
            'consistency_score': consistency_score,
            'total_checks': total_checks,
            'consistency_percentage': consistency_percentage
        }
    
    def generate_performance_report(self):
        """Generate comprehensive performance report"""
        print("\n📊 Performance Report")
        print("====================")
        
        # Create performance visualization
        self.create_performance_plots()
        
        # Generate summary report
        report = {
            'timestamp': time.time(),
            'test_results': self.results
        }
        
        with open('gossip_performance_report.json', 'w') as f:
            json.dump(report, f, indent=2)
        
        print("\n📄 Summary:")
        
        if 'propagation_latency' in self.results:
            latency = self.results['propagation_latency']
            print(f"  • Average propagation latency: {latency['avg']:.2f}ms")
        
        if 'convergence_time' in self.results:
            convergence = self.results['convergence_time']
            print(f"  • Average convergence time: {convergence['avg']:.2f}s")
        
        if 'failure_detection' in self.results:
            fd = self.results['failure_detection']
            print(f"  • Failure detection consistency: {fd['consistency_percentage']:.1f}%")
        
        if 'load_performance' in self.results:
            max_load = max(self.results['load_performance'].keys())
            max_perf = self.results['load_performance'][max_load]
            print(f"  • Max sustained load: {max_load} msg/s at {max_perf['success_rate']:.1f}% success")
        
        print(f"\n📁 Detailed report saved to: gossip_performance_report.json")
        print(f"📈 Performance plots saved to: gossip_performance_plots.png")
    
    def create_performance_plots(self):
        """Create performance visualization plots"""
        try:
            fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
            fig.suptitle('Gossip Protocol Performance Analysis', fontsize=16)
            
            # Plot 1: Propagation Latency
            if 'propagation_latency' in self.results:
                latencies = self.results['propagation_latency']['samples']
                ax1.hist(latencies, bins=20, alpha=0.7, color='blue')
                ax1.set_xlabel('Latency (ms)')
                ax1.set_ylabel('Frequency')
                ax1.set_title('Propagation Latency Distribution')
                ax1.axvline(statistics.mean(latencies), color='red', linestyle='--', 
                           label=f'Mean: {statistics.mean(latencies):.1f}ms')
                ax1.legend()
            
            # Plot 2: Convergence Time
            if 'convergence_time' in self.results:
                convergence_times = self.results['convergence_time']['samples']
                ax2.plot(range(len(convergence_times)), convergence_times, 'o-', color='green')
                ax2.set_xlabel('Test Number')
                ax2.set_ylabel('Convergence Time (s)')
                ax2.set_title('Convergence Time per Test')
                ax2.axhline(statistics.mean(convergence_times), color='red', linestyle='--',
                           label=f'Mean: {statistics.mean(convergence_times):.1f}s')
                ax2.legend()
            
            # Plot 3: Load Performance
            if 'load_performance' in self.results:
                loads = list(self.results['load_performance'].keys())
                success_rates = [self.results['load_performance'][load]['success_rate'] 
                               for load in loads]
                avg_latencies = [self.results['load_performance'][load]['avg_latency'] 
                               for load in loads]
                
                ax3_twin = ax3.twinx()
                line1 = ax3.plot(loads, success_rates, 'o-', color='blue', label='Success Rate')
                line2 = ax3_twin.plot(loads, avg_latencies, 's--', color='orange', label='Avg Latency')
                
                ax3.set_xlabel('Load (messages/second)')
                ax3.set_ylabel('Success Rate (%)', color='blue')
                ax3_twin.set_ylabel('Average Latency (ms)', color='orange')
                ax3.set_title('Load vs Performance')
                
                lines = line1 + line2
                labels = [l.get_label() for l in lines]
                ax3.legend(lines, labels, loc='upper left')
            
            # Plot 4: Network Consistency
            if 'failure_detection' in self.results:
                fd_data = self.results['failure_detection']
                consistency = fd_data['consistency_percentage']
                
                # Simple bar chart showing consistency
                ax4.bar(['Consistency'], [consistency], color='purple', alpha=0.7)
                ax4.set_ylabel('Consistency (%)')
                ax4.set_title('Failure Detection Consistency')
                ax4.set_ylim(0, 100)
                ax4.axhline(90, color='red', linestyle='--', label='Target: 90%')
                ax4.legend()
            
            plt.tight_layout()
            plt.savefig('gossip_performance_plots.png', dpi=300, bbox_inches='tight')
            plt.close()
            
        except Exception as e:
            print(f"Warning: Could not generate plots: {e}")

if __name__ == "__main__":
    print("🧪 Advanced Gossip Protocol Test Suite")
    print("======================================")
    
    # Check if network is running
    try:
        response = requests.get("http://localhost:9001/api/status", timeout=2)
        if response.status_code != 200:
            print("❌ Gossip network not responding. Start with: python start_network.py")
            exit(1)
    except:
        print("❌ Gossip network not running. Start with: python start_network.py")
        exit(1)
    
    benchmark = GossipBenchmark()
    
    try:
        benchmark.run_all_tests()
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted by user")
    except Exception as e:
        print(f"\n❌ Error during testing: {e}")
    
    print("\n✅ Advanced testing complete!")
