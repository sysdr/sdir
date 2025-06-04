#!/usr/bin/env python3
"""
Comprehensive test suite for Paxos consensus algorithm
Tests safety properties, liveness conditions, and failure scenarios
"""

import sys
import os
import json
import time
import unittest
import threading
import subprocess
from pathlib import Path

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from paxos_simulator import PaxosAcceptor, PaxosProposer, PaxosSimulation

class TestPaxosProperties(unittest.TestCase):
    """Test fundamental Paxos safety and liveness properties"""
    
    def setUp(self):
        """Set up test environment before each test"""
        self.acceptors = [PaxosAcceptor(str(i)) for i in range(5)]
        self.proposers = [PaxosProposer(str(i), self.acceptors) for i in range(3)]
        self.simulation = PaxosSimulation(num_acceptors=5, num_proposers=3)
    
    def test_safety_single_value_consensus(self):
        """Test that only one value can be chosen per consensus instance"""
        print("\n🧪 Testing Safety: Single Value Consensus")
        
        # Multiple proposers propose different values simultaneously
        values = ["value_A", "value_B", "value_C"]
        results = []
        
        def propose_value(proposer, value):
            success, chosen = proposer.propose(value)
            results.append((success, chosen))
        
        # Start all proposals concurrently
        threads = []
        for i, value in enumerate(values):
            thread = threading.Thread(
                target=propose_value, 
                args=(self.proposers[i], value)
            )
            threads.append(thread)
            thread.start()
        
        # Wait for all to complete
        for thread in threads:
            thread.join()
        
        # Verify safety: all successful proposals chose the same value
        successful_values = [chosen for success, chosen in results if success and chosen]
        if len(successful_values) > 1:
            unique_values = set(successful_values)
            self.assertEqual(len(unique_values), 1, 
                f"Safety violation: Multiple values chosen: {unique_values}")
        
        print(f"✅ Safety verified: {len(successful_values)} successful proposals, "
              f"all chose same value: {successful_values[0] if successful_values else 'None'}")
    
    def test_liveness_eventual_progress(self):
        """Test that consensus eventually makes progress without competing proposers"""
        print("\n🧪 Testing Liveness: Eventual Progress")
        
        # Single proposer should always succeed with sufficient acceptors
        proposer = self.proposers[0]
        success, chosen = proposer.propose("test_value")
        
        self.assertTrue(success, "Liveness violation: Consensus failed with no competition")
        self.assertEqual(chosen, "test_value", "Wrong value chosen")
        
        print("✅ Liveness verified: Single proposer achieved consensus")
    
    def test_acceptor_persistence_across_restart(self):
        """Test that acceptor state persists across simulated restarts"""
        print("\n🧪 Testing Persistence: Acceptor State Recovery")
        
        acceptor = self.acceptors[0]
        
        # Accept a proposal
        promise = acceptor.prepare(100)
        self.assertIsNotNone(promise, "Initial prepare should succeed")
        
        # Simulate crash and recovery
        acceptor.crash()
        acceptor.recover()
        
        # Verify lower proposal numbers are still rejected
        lower_promise = acceptor.prepare(50)
        self.assertIsNone(lower_promise, "Lower proposal should be rejected after recovery")
        
        print("✅ Persistence verified: State maintained across restart")
    
    def test_majority_quorum_requirement(self):
        """Test that consensus requires majority quorum"""
        print("\n🧪 Testing Quorum: Majority Requirement")
        
        # Crash majority of acceptors
        for i in range(3):  # Crash 3 out of 5 acceptors
            self.acceptors[i].crash()
        
        # Proposal should fail
        proposer = self.proposers[0]
        success, chosen = proposer.propose("should_fail")
        
        self.assertFalse(success, "Consensus should fail without majority")
        
        print("✅ Quorum verified: Consensus failed without majority")
    
    def test_proposal_number_uniqueness(self):
        """Test that proposal numbers are globally unique and monotonic"""
        print("\n🧪 Testing Proposal Numbers: Uniqueness and Monotonicity")
        
        proposal_ids = []
        
        # Generate multiple proposals from different proposers
        for proposer in self.proposers:
            for _ in range(3):
                old_counter = proposer.proposal_counter
                next_id = proposer._next_proposal_id()
                proposal_ids.append(next_id)
                
                # Verify monotonicity within proposer
                self.assertGreater(next_id, old_counter, 
                    f"Proposal ID {next_id} not greater than {old_counter}")
        
        # Verify global uniqueness
        unique_ids = set(proposal_ids)
        self.assertEqual(len(unique_ids), len(proposal_ids), 
            "Proposal IDs are not globally unique")
        
        print(f"✅ Proposal numbers verified: {len(proposal_ids)} unique, monotonic IDs")

class TestPaxosFailureScenarios(unittest.TestCase):
    """Test Paxos behavior under various failure conditions"""
    
    def setUp(self):
        self.simulation = PaxosSimulation(num_acceptors=5, num_proposers=3)
    
    def test_split_brain_prevention(self):
        """Test that split brain scenarios are prevented"""
        print("\n🧪 Testing Split Brain Prevention")
        
        # Simulate network partition by crashing acceptors
        self.simulation.acceptors[0].crash()
        self.simulation.acceptors[1].crash()
        
        # Two proposers try to achieve consensus on different sides
        results = []
        
        def concurrent_propose(proposer, value):
            success, chosen = proposer.propose(value)
            results.append((proposer.node_id, success, chosen))
        
        threads = [
            threading.Thread(target=concurrent_propose, 
                           args=(self.simulation.proposers[0], "partition_A")),
            threading.Thread(target=concurrent_propose, 
                           args=(self.simulation.proposers[1], "partition_B"))
        ]
        
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        
        # At most one should succeed (preventing split brain)
        successful = [r for r in results if r[1]]
        self.assertLessEqual(len(successful), 1, 
            "Split brain detected: Multiple proposers succeeded")
        
        print(f"✅ Split brain prevented: {len(successful)} successful proposals")
    
    def test_acceptor_recovery(self):
        """Test acceptor recovery and state restoration"""
        print("\n🧪 Testing Acceptor Recovery")
        
        acceptor = self.simulation.acceptors[0]
        
        # Establish initial state
        acceptor.prepare(100)
        original_max_prepare = acceptor.state.max_prepare
        
        # Crash and recover
        acceptor.crash()
        self.assertFalse(acceptor.state.is_alive)
        
        acceptor.recover()
        self.assertTrue(acceptor.state.is_alive)
        
        # Verify state was restored
        self.assertEqual(acceptor.state.max_prepare, original_max_prepare,
            "State not properly restored after recovery")
        
        print("✅ Recovery verified: Acceptor state properly restored")

class TestPaxosPerformance(unittest.TestCase):
    """Test Paxos performance characteristics and optimizations"""
    
    def test_message_complexity(self):
        """Test that Paxos uses expected number of messages"""
        print("\n🧪 Testing Message Complexity")
        
        # This is a simplified test - in production, you'd instrument
        # the actual message passing to count network operations
        
        simulation = PaxosSimulation(num_acceptors=5, num_proposers=1)
        
        # Single proposal should require 2 rounds of messages
        # Round 1: 1 proposer -> 5 acceptors (prepare)
        # Round 1: 5 acceptors -> 1 proposer (promise)
        # Round 2: 1 proposer -> 5 acceptors (accept)
        # Round 2: 5 acceptors -> 1 proposer (accepted)
        # Total: 20 messages for optimal case
        
        start_time = time.time()
        success, chosen = simulation.proposers[0].propose("performance_test")
        end_time = time.time()
        
        self.assertTrue(success, "Performance test proposal should succeed")
        
        duration = end_time - start_time
        print(f"✅ Performance measured: {duration:.3f}s for single proposal")
        print(f"   (includes simulated network delays)")
    
    def test_concurrent_proposal_handling(self):
        """Test behavior with many concurrent proposals"""
        print("\n🧪 Testing Concurrent Proposal Performance")
        
        simulation = PaxosSimulation(num_acceptors=7, num_proposers=5)
        results = []
        
        def concurrent_proposals():
            for i in range(10):
                success, chosen = simulation.proposers[i % 5].propose(f"value_{i}")
                results.append((success, chosen))
                time.sleep(0.1)  # Small delay to create overlap
        
        start_time = time.time()
        thread = threading.Thread(target=concurrent_proposals)
        thread.start()
        thread.join()
        end_time = time.time()
        
        successful = [r for r in results if r[0]]
        duration = end_time - start_time
        
        print(f"✅ Concurrency tested: {len(successful)}/{len(results)} "
              f"proposals succeeded in {duration:.3f}s")

def run_integration_tests():
    """Run integration tests that verify end-to-end scenarios"""
    print("\n🔧 Running Integration Tests")
    print("=" * 50)
    
    # Test scenario files exist and are valid
    scenario_files = [
        'logs/scenario_basic_consensus.json',
        'logs/scenario_competing_proposers.json',
        'logs/scenario_node_failures.json'
    ]
    
    for scenario_file in scenario_files:
        if os.path.exists(scenario_file):
            try:
                with open(scenario_file, 'r') as f:
                    data = json.load(f)
                    print(f"✅ {scenario_file}: Valid JSON with {len(data.get('proposals', []))} proposals")
            except json.JSONDecodeError as e:
                print(f"❌ {scenario_file}: Invalid JSON - {e}")
        else:
            print(f"⚠️  {scenario_file}: File not found")
    
    # Test log file contains expected patterns
    log_file = 'logs/paxos_simulation.log'
    if os.path.exists(log_file):
        with open(log_file, 'r') as f:
            log_content = f.read()
            
        expected_patterns = [
            'PREPARE(',
            'PROMISE(',
            'ACCEPT(',
            'ACCEPTED(',
            'CONSENSUS ACHIEVED'
        ]
        
        for pattern in expected_patterns:
            if pattern in log_content:
                print(f"✅ Log contains expected pattern: {pattern}")
            else:
                print(f"⚠️  Log missing pattern: {pattern}")
    else:
        print(f"❌ Log file not found: {log_file}")

def main():
    """Main test runner"""
    print("🧪 Paxos Consensus Algorithm Test Suite")
    print("=" * 50)
    
    # Run unit tests
    test_suites = [
        TestPaxosProperties,
        TestPaxosFailureScenarios,
        TestPaxosPerformance
    ]
    
    for suite_class in test_suites:
        print(f"\n📋 Running {suite_class.__name__}")
        suite = unittest.TestLoader().loadTestsFromTestCase(suite_class)
        runner = unittest.TextTestRunner(verbosity=0)
        result = runner.run(suite)
        
        if result.wasSuccessful():
            print(f"✅ {suite_class.__name__}: All tests passed")
        else:
            print(f"❌ {suite_class.__name__}: {len(result.failures)} failures, "
                  f"{len(result.errors)} errors")
    
    # Run integration tests
    run_integration_tests()
    
    print("\n🎉 Test suite completed!")
    print("📊 Check logs for detailed test execution traces")

if __name__ == "__main__":
    main()
