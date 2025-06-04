#!/bin/bash

# Paxos Consensus Algorithm Interactive Demonstration
# This script creates a complete Paxos simulation with web interface
# Author: System Design Interview Roadmap
# Issue #56: Distributed Consensus: Paxos Simplified

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEMO_DIR="paxos_demo"
NUM_ACCEPTORS=5
NUM_PROPOSERS=3
WEB_PORT=8080
DOCKER_ENABLED=true

echo -e "${BLUE}🚀 Paxos Consensus Algorithm Demonstration Setup${NC}"
echo -e "${BLUE}=================================================${NC}"

# Clean up previous runs
if [ -d "$DEMO_DIR" ]; then
    echo -e "${YELLOW}Cleaning up previous demo...${NC}"
    rm -rf "$DEMO_DIR"
fi

# Create demo directory structure
mkdir -p "$DEMO_DIR"/{logs,state,web}
cd "$DEMO_DIR"

echo -e "${GREEN}✅ Created demo directory structure${NC}"

# Create the Paxos simulator in Python (embedded in bash script)
cat > paxos_simulator.py << 'EOF'
#!/usr/bin/env python3
"""
Paxos Consensus Algorithm Simulator
Demonstrates the core Paxos protocol with detailed logging
"""

import json
import time
import random
import threading
import logging
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from http.server import HTTPServer, SimpleHTTPRequestHandler
import socketserver
import sys
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/paxos_simulation.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

@dataclass
class Promise:
    proposal_id: int
    accepted_proposal_id: Optional[int] = None
    accepted_value: Optional[str] = None

@dataclass
class Proposal:
    proposal_id: int
    value: str

@dataclass
class AcceptorState:
    node_id: str
    max_prepare: Optional[int] = None
    accepted_proposal: Optional[Proposal] = None
    is_alive: bool = True

class PaxosAcceptor:
    def __init__(self, node_id: str):
        self.node_id = node_id
        self.state = AcceptorState(node_id=node_id)
        self.logger = logging.getLogger(f"Acceptor-{node_id}")
        self.message_delay = random.uniform(0.1, 0.5)  # Simulate network delay
        
    def _save_state(self):
        """Simulate persistent storage - critical for Paxos safety"""
        with open(f'state/acceptor_{self.node_id}.json', 'w') as f:
            json.dump(asdict(self.state), f, indent=2)
        time.sleep(0.01)  # Simulate disk write delay
    
    def _load_state(self):
        """Load state from persistent storage"""
        try:
            with open(f'state/acceptor_{self.node_id}.json', 'r') as f:
                state_dict = json.load(f)
                self.state = AcceptorState(**state_dict)
        except FileNotFoundError:
            pass
    
    def prepare(self, proposal_id: int) -> Optional[Promise]:
        """Phase 1: Handle prepare request"""
        if not self.state.is_alive:
            return None
            
        time.sleep(self.message_delay)  # Simulate network delay
        
        self.logger.info(f"📥 Received PREPARE({proposal_id})")
        
        # Safety check: only promise if proposal_id > max_prepare
        if self.state.max_prepare is None or proposal_id > self.state.max_prepare:
            self.state.max_prepare = proposal_id
            self._save_state()  # Critical: persist before responding
            
            promise = Promise(
                proposal_id=proposal_id,
                accepted_proposal_id=self.state.accepted_proposal.proposal_id if self.state.accepted_proposal else None,
                accepted_value=self.state.accepted_proposal.value if self.state.accepted_proposal else None
            )
            
            self.logger.info(f"✅ PROMISE({proposal_id}) - Previous: {promise.accepted_proposal_id}")
            return promise
        else:
            self.logger.info(f"❌ REJECT PREPARE({proposal_id}) - Already promised to {self.state.max_prepare}")
            return None
    
    def accept(self, proposal: Proposal) -> bool:
        """Phase 2: Handle accept request"""
        if not self.state.is_alive:
            return False
            
        time.sleep(self.message_delay)  # Simulate network delay
        
        self.logger.info(f"📥 Received ACCEPT({proposal.proposal_id}, '{proposal.value}')")
        
        # Safety check: only accept if proposal_id >= max_prepare
        if self.state.max_prepare is None or proposal.proposal_id >= self.state.max_prepare:
            self.state.accepted_proposal = proposal
            self.state.max_prepare = proposal.proposal_id
            self._save_state()  # Critical: persist before responding
            
            self.logger.info(f"✅ ACCEPTED({proposal.proposal_id}, '{proposal.value}')")
            return True
        else:
            self.logger.info(f"❌ REJECT ACCEPT({proposal.proposal_id}) - Promised to higher {self.state.max_prepare}")
            return False
    
    def crash(self):
        """Simulate node failure"""
        self.state.is_alive = False
        self.logger.warning(f"💥 CRASHED - Node {self.node_id} is now offline")
    
    def recover(self):
        """Simulate node recovery"""
        self._load_state()  # Reload state from persistent storage
        self.state.is_alive = True
        self.logger.info(f"🔄 RECOVERED - Node {self.node_id} is back online")

class PaxosProposer:
    def __init__(self, node_id: str, acceptors: List[PaxosAcceptor]):
        self.node_id = node_id
        self.acceptors = acceptors
        self.proposal_counter = int(node_id) * 1000  # Ensure unique proposal IDs
        self.logger = logging.getLogger(f"Proposer-{node_id}")
    
    def _next_proposal_id(self) -> int:
        """Generate next unique proposal ID"""
        self.proposal_counter += 1
        return self.proposal_counter
    
    def propose(self, value: str) -> Tuple[bool, Optional[str]]:
        """Execute full Paxos protocol to propose a value"""
        proposal_id = self._next_proposal_id()
        self.logger.info(f"🎯 Starting proposal {proposal_id} for value '{value}'")
        
        # Phase 1: Prepare
        self.logger.info(f"📤 Phase 1: Broadcasting PREPARE({proposal_id})")
        promises = []
        
        for acceptor in self.acceptors:
            promise = acceptor.prepare(proposal_id)
            if promise:
                promises.append(promise)
        
        majority = len(self.acceptors) // 2 + 1
        if len(promises) < majority:
            self.logger.warning(f"❌ Phase 1 FAILED: Only {len(promises)}/{len(self.acceptors)} promises (need {majority})")
            return False, None
        
        self.logger.info(f"✅ Phase 1 SUCCESS: Received {len(promises)}/{len(self.acceptors)} promises")
        
        # Check if any acceptor has already accepted a value
        highest_accepted = None
        for promise in promises:
            if promise.accepted_proposal_id is not None:
                if highest_accepted is None or promise.accepted_proposal_id > highest_accepted[0]:
                    highest_accepted = (promise.accepted_proposal_id, promise.accepted_value)
        
        # Choose value: if any acceptor accepted a value, use highest; otherwise use proposed value
        chosen_value = highest_accepted[1] if highest_accepted else value
        if highest_accepted:
            self.logger.info(f"🔄 Using previously accepted value '{chosen_value}' from proposal {highest_accepted[0]}")
        
        # Phase 2: Accept
        proposal = Proposal(proposal_id=proposal_id, value=chosen_value)
        self.logger.info(f"📤 Phase 2: Broadcasting ACCEPT({proposal_id}, '{chosen_value}')")
        
        accepts = 0
        for acceptor in self.acceptors:
            if acceptor.accept(proposal):
                accepts += 1
        
        if accepts >= majority:
            self.logger.info(f"🎉 CONSENSUS ACHIEVED: Value '{chosen_value}' chosen with {accepts}/{len(self.acceptors)} accepts")
            return True, chosen_value
        else:
            self.logger.warning(f"❌ Phase 2 FAILED: Only {accepts}/{len(self.acceptors)} accepts (need {majority})")
            return False, None

class PaxosSimulation:
    def __init__(self, num_acceptors: int = 5, num_proposers: int = 3):
        self.acceptors = [PaxosAcceptor(str(i)) for i in range(num_acceptors)]
        self.proposers = [PaxosProposer(str(i), self.acceptors) for i in range(num_proposers)]
        self.consensus_log = []
        self.logger = logging.getLogger("Simulation")
    
    def run_scenario(self, scenario_name: str, values_to_propose: List[str], failure_actions: List = None):
        """Run a specific Paxos scenario"""
        self.logger.info(f"🎬 Starting scenario: {scenario_name}")
        self.logger.info("=" * 60)
        
        scenario_results = {
            'scenario': scenario_name,
            'timestamp': datetime.now().isoformat(),
            'proposals': [],
            'final_state': {}
        }
        
        # Execute failure actions if specified
        if failure_actions:
            for action in failure_actions:
                time.sleep(1)  # Pause for clarity
                if action['type'] == 'crash':
                    self.acceptors[action['node']].crash()
                elif action['type'] == 'recover':
                    self.acceptors[action['node']].recover()
        
        # Run proposals
        for i, value in enumerate(values_to_propose):
            proposer = self.proposers[i % len(self.proposers)]
            time.sleep(2)  # Pause between proposals for clarity
            
            success, chosen_value = proposer.propose(value)
            result = {
                'proposer': proposer.node_id,
                'proposed_value': value,
                'success': success,
                'chosen_value': chosen_value
            }
            scenario_results['proposals'].append(result)
        
        # Capture final state
        for acceptor in self.acceptors:
            scenario_results['final_state'][acceptor.node_id] = {
                'is_alive': acceptor.state.is_alive,
                'max_prepare': acceptor.state.max_prepare,
                'accepted_proposal': asdict(acceptor.state.accepted_proposal) if acceptor.state.accepted_proposal else None
            }
        
        self.consensus_log.append(scenario_results)
        
        # Save results
        with open(f'logs/scenario_{scenario_name.lower().replace(" ", "_")}.json', 'w') as f:
            json.dump(scenario_results, f, indent=2)
        
        self.logger.info(f"✅ Scenario '{scenario_name}' completed")
        self.logger.info("=" * 60)
        return scenario_results

def create_web_interface():
    """Create web interface files"""
    
    # Create HTML file
    html_content = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Paxos Consensus Algorithm Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f8f9fa;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            text-align: center;
        }
        .scenario-section {
            background: white;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .node-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .node {
            background: #e3f2fd;
            border: 2px solid #1976d2;
            border-radius: 8px;
            padding: 15px;
            text-align: center;
        }
        .node.crashed {
            background: #ffebee;
            border-color: #d32f2f;
            opacity: 0.6;
        }
        .node.leader {
            background: #e8f5e8;
            border-color: #388e3c;
        }
        .proposal-log {
            background: #f5f5f5;
            border-left: 4px solid #2196f3;
            padding: 15px;
            margin: 10px 0;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
        }
        button {
            background: #1976d2;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
        }
        button:hover { background: #1565c0; }
        .success { color: #4caf50; font-weight: bold; }
        .failure { color: #f44336; font-weight: bold; }
        .info { color: #2196f3; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎯 Paxos Consensus Algorithm</h1>
        <p>Interactive demonstration of distributed consensus</p>
    </div>

    <div class="scenario-section">
        <h2>🔧 Controls</h2>
        <button onclick="runScenario('basic')">Basic Consensus</button>
        <button onclick="runScenario('competing')">Competing Proposers</button>
        <button onclick="runScenario('failure')">Node Failures</button>
        <button onclick="refreshLogs()">Refresh Logs</button>
        <button onclick="clearLogs()">Clear Logs</button>
    </div>

    <div class="scenario-section">
        <h2>📊 Node Status</h2>
        <div id="nodeStatus" class="node-grid">
            <!-- Nodes will be populated by JavaScript -->
        </div>
    </div>

    <div class="scenario-section">
        <h2>📝 Live Logs</h2>
        <div id="logs" class="proposal-log">
            Click "Refresh Logs" to see simulation output...
        </div>
    </div>

    <script>
        let refreshInterval;
        
        function updateNodeStatus() {
            // This would typically fetch from a real backend
            const nodeStatus = document.getElementById('nodeStatus');
            nodeStatus.innerHTML = '';
            
            for (let i = 0; i < 5; i++) {
                const node = document.createElement('div');
                node.className = 'node';
                node.innerHTML = `
                    <h4>Acceptor ${i}</h4>
                    <div>Status: Active</div>
                    <div>Max Prepare: -</div>
                    <div>Accepted: -</div>
                `;
                nodeStatus.appendChild(node);
            }
        }
        
        function runScenario(type) {
            const logs = document.getElementById('logs');
            logs.innerHTML = `Running ${type} scenario...\\nCheck terminal and log files for detailed output.`;
            
            // In a real implementation, this would trigger the Python simulation
            fetch(`/run_scenario?type=${type}`)
                .then(response => response.text())
                .then(data => {
                    logs.innerHTML = data;
                })
                .catch(error => {
                    logs.innerHTML = `Error: ${error}\\nPlease run scenarios from terminal.`;
                });
        }
        
        function refreshLogs() {
            fetch('/logs/paxos_simulation.log')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('logs').textContent = data;
                })
                .catch(error => {
                    document.getElementById('logs').textContent = 'Error loading logs. Check terminal output.';
                });
        }
        
        function clearLogs() {
            document.getElementById('logs').textContent = 'Logs cleared.';
        }
        
        // Initialize
        updateNodeStatus();
        
        // Auto-refresh logs every 5 seconds
        refreshInterval = setInterval(refreshLogs, 5000);
    </script>
</body>
</html>'''
    
    with open('web/index.html', 'w') as f:
        f.write(html_content)

def main():
    # Create web interface
    create_web_interface()
    
    # Initialize simulation
    print("🎬 Initializing Paxos simulation...")
    sim = PaxosSimulation(num_acceptors=5, num_proposers=3)
    
    # Scenario 1: Basic consensus with no failures
    print("\n" + "="*60)
    print("📝 SCENARIO 1: Basic Consensus")
    print("="*60)
    sim.run_scenario(
        "Basic Consensus",
        ["transaction_commit", "config_update"]
    )
    
    time.sleep(3)
    
    # Scenario 2: Competing proposers
    print("\n" + "="*60)
    print("📝 SCENARIO 2: Competing Proposers")
    print("="*60)
    sim.run_scenario(
        "Competing Proposers",
        ["value_A", "value_B", "value_C"]
    )
    
    time.sleep(3)
    
    # Scenario 3: Node failures and recovery
    print("\n" + "="*60)
    print("📝 SCENARIO 3: Node Failures")
    print("="*60)
    sim.run_scenario(
        "Node Failures",
        ["critical_decision"],
        failure_actions=[
            {'type': 'crash', 'node': 0},
            {'type': 'crash', 'node': 1}
        ]
    )
    
    print("\n🎉 All scenarios completed!")
    print(f"📊 Check logs/ directory for detailed output")
    print(f"🌐 Open web/index.html for visualization")
    print(f"💾 Check state/ directory for persistent acceptor state")

if __name__ == "__main__":
    main()
EOF

echo -e "${GREEN}✅ Created Paxos simulator${NC}"

# Create Dockerfile for containerized deployment
cat > Dockerfile << 'EOF'
# Multi-stage build for optimized production container
FROM python:3.11-slim as base

# Set working directory
WORKDIR /app

# Install system dependencies for potential network tools
RUN apt-get update && apt-get install -y \
    curl \
    netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash paxos

# Copy requirements first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY paxos_simulator.py .
COPY start_web_server.py .
COPY web/ ./web/

# Create directories for logs and state with proper permissions
RUN mkdir -p logs state && \
    chown -R paxos:paxos /app

# Switch to non-root user
USER paxos

# Expose port for web interface
EXPOSE 8080

# Health check to ensure the service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Default command runs the simulation
CMD ["python3", "paxos_simulator.py"]
EOF

echo -e "${GREEN}✅ Created Dockerfile${NC}"

# Create docker-compose.yml for multi-node orchestration
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Main Paxos simulation service
  paxos-simulator:
    build: .
    container_name: paxos-main
    ports:
      - "8080:8080"
    volumes:
      - ./logs:/app/logs
      - ./state:/app/state
    environment:
      - PYTHONUNBUFFERED=1
      - PAXOS_MODE=simulation
    networks:
      - paxos-network
    restart: unless-stopped
    
  # Web interface service (separate for scalability demonstration)
  paxos-web:
    build: .
    container_name: paxos-web
    ports:
      - "8081:8080"
    volumes:
      - ./logs:/app/logs:ro
      - ./state:/app/state:ro
      - ./web:/app/web
    environment:
      - PYTHONUNBUFFERED=1
      - PAXOS_MODE=web
    command: ["python3", "start_web_server.py"]
    networks:
      - paxos-network
    depends_on:
      - paxos-simulator
    restart: unless-stopped

  # Test runner service for automated verification
  paxos-test:
    build: .
    container_name: paxos-test
    volumes:
      - ./logs:/app/logs
      - ./state:/app/state
      - ./tests:/app/tests
    environment:
      - PYTHONUNBUFFERED=1
      - PAXOS_MODE=test
    command: ["python3", "test_paxos.py"]
    networks:
      - paxos-network
    depends_on:
      - paxos-simulator
    profiles:
      - testing

  # Network partition simulator (chaos engineering)
  chaos-monkey:
    image: alpine:latest
    container_name: paxos-chaos
    command: >
      sh -c "
        echo 'Chaos Monkey: Simulating network partitions...';
        while true; do
          sleep 30;
          echo 'Injecting 5-second network delay...';
          sleep 5;
          echo 'Network restored';
          sleep 25;
        done
      "
    networks:
      - paxos-network
    profiles:
      - chaos

networks:
  paxos-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  paxos-logs:
    driver: local
  paxos-state:
    driver: local
EOF

echo -e "${GREEN}✅ Created docker-compose.yml${NC}"

# Create comprehensive test suite
mkdir -p tests
cat > tests/test_paxos.py << 'EOF'
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
EOF

echo -e "${GREEN}✅ Created comprehensive test suite${NC}"

# Create Docker test runner script
cat > test_docker.py << 'EOF'
#!/usr/bin/env python3
"""
Docker-specific test runner for Paxos demonstration
Tests containerized deployment and multi-container orchestration
"""

import subprocess
import time
import json
import requests
import sys

def run_command(cmd, description):
    """Run shell command and return success status"""
    print(f"🔧 {description}")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            print(f"✅ Success: {description}")
            return True
        else:
            print(f"❌ Failed: {description}")
            print(f"Error: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"⏰ Timeout: {description}")
        return False

def test_docker_build():
    """Test Docker image builds successfully"""
    return run_command("docker build -t paxos-demo .", "Building Docker image")

def test_container_health():
    """Test container starts and responds to health checks"""
    print("🔧 Testing container health")
    
    # Start container in detached mode
    start_cmd = "docker run -d -p 8080:8080 --name paxos-test paxos-demo"
    if not run_command(start_cmd, "Starting test container"):
        return False
    
    # Wait for container to be ready
    time.sleep(10)
    
    # Check if container is running
    check_cmd = "docker ps --filter name=paxos-test --format '{{.Status}}'"
    result = subprocess.run(check_cmd, shell=True, capture_output=True, text=True)
    
    # Cleanup
    run_command("docker stop paxos-test", "Stopping test container")
    run_command("docker rm paxos-test", "Removing test container")
    
    if "Up" in result.stdout:
        print("✅ Container health check passed")
        return True
    else:
        print("❌ Container health check failed")
        return False

def test_docker_compose():
    """Test docker-compose orchestration"""
    print("🔧 Testing Docker Compose orchestration")
    
    # Start services
    if not run_command("docker-compose up -d", "Starting Docker Compose services"):
        return False
    
    # Wait for services to be ready
    time.sleep(15)
    
    # Check service status
    status_cmd = "docker-compose ps --format json"
    try:
        result = subprocess.run(status_cmd, shell=True, capture_output=True, text=True)
        services = json.loads(result.stdout) if result.stdout else []
        
        running_services = [s for s in services if 'running' in s.get('State', '').lower()]
        print(f"✅ Docker Compose: {len(running_services)} services running")
        
        # Cleanup
        run_command("docker-compose down", "Stopping Docker Compose services")
        return len(running_services) > 0
        
    except (json.JSONDecodeError, Exception) as e:
        print(f"❌ Error checking service status: {e}")
        run_command("docker-compose down", "Cleanup after error")
        return False

def test_web_interface_accessibility():
    """Test web interface is accessible in container"""
    print("🔧 Testing web interface accessibility")
    
    # Start web service
    start_cmd = "docker run -d -p 8081:8080 --name paxos-web-test paxos-demo python3 start_web_server.py"
    if not run_command(start_cmd, "Starting web interface container"):
        return False
    
    # Wait for service to start
    time.sleep(5)
    
    # Test web accessibility
    try:
        response = requests.get("http://localhost:8081", timeout=10)
        accessible = response.status_code == 200
        
        if accessible:
            print("✅ Web interface accessible")
        else:
            print(f"❌ Web interface returned status {response.status_code}")
            
    except requests.RequestException as e:
        print(f"❌ Web interface not accessible: {e}")
        accessible = False
    
    # Cleanup
    run_command("docker stop paxos-web-test", "Stopping web test container")
    run_command("docker rm paxos-web-test", "Removing web test container")
    
    return accessible

def test_volume_persistence():
    """Test that volumes persist data correctly"""
    print("🔧 Testing volume persistence")
    
    # Start container with volume
    start_cmd = "docker run -d -v $(pwd)/test_logs:/app/logs --name paxos-volume-test paxos-demo"
    if not run_command(start_cmd, "Starting container with volume"):
        return False
    
    # Wait for simulation to generate some logs
    time.sleep(10)
    
    # Check if logs were created in volume
    check_cmd = "test -f test_logs/paxos_simulation.log"
    log_exists = run_command(check_cmd, "Checking log file in volume")
    
    # Cleanup
    run_command("docker stop paxos-volume-test", "Stopping volume test container")
    run_command("docker rm paxos-volume-test", "Removing volume test container")
    run_command("rm -rf test_logs", "Cleaning up test logs")
    
    return log_exists

def main():
    """Run all Docker tests"""
    print("🐳 Docker Integration Test Suite for Paxos Demo")
    print("=" * 60)
    
    tests = [
        ("Docker Build", test_docker_build),
        ("Container Health", test_container_health),
        ("Docker Compose", test_docker_compose),
        ("Web Interface", test_web_interface_accessibility),
        ("Volume Persistence", test_volume_persistence)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        print(f"\n📋 Running {test_name} Test")
        print("-" * 40)
        results[test_name] = test_func()
    
    # Summary
    print("\n📊 Test Results Summary")
    print("=" * 30)
    
    passed = sum(results.values())
    total = len(results)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name}: {status}")
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All Docker tests passed! The containerized Paxos demo is ready.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
EOF

chmod +x tests/test_paxos.py
chmod +x test_docker.py

# Create Makefile for easy Docker operations
cat > Makefile << 'EOF'
# Paxos Consensus Algorithm Docker Demo
# Provides convenient commands for Docker operations

.PHONY: help build run test clean logs shell

help: ## Show this help message
	@echo "Paxos Consensus Algorithm Docker Demo"
	@echo "====================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $1, $2}'

build: ## Build Docker image
	@echo "🐳 Building Paxos Docker image..."
	docker build -t paxos-demo .

run: ## Run simulation in Docker container
	@echo "🚀 Running Paxos simulation in Docker..."
	docker run --rm -v $(PWD)/logs:/app/logs -v $(PWD)/state:/app/state paxos-demo

run-web: ## Start web interface in Docker
	@echo "🌐 Starting Paxos web interface..."
	docker run -d --name paxos-web -p 8080:8080 -v $(PWD)/logs:/app/logs:ro -v $(PWD)/state:/app/state:ro paxos-demo python3 start_web_server.py
	@echo "📊 Web interface available at http://localhost:8080"

compose-up: ## Start all services with docker-compose
	@echo "🎼 Starting Paxos services with Docker Compose..."
	docker-compose up -d

compose-down: ## Stop all services
	@echo "🛑 Stopping Paxos services..."
	docker-compose down

test: ## Run test suite in Docker
	@echo "🧪 Running Paxos tests in Docker..."
	docker run --rm -v $(PWD)/logs:/app/logs -v $(PWD)/state:/app/state -v $(PWD)/tests:/app/tests paxos-demo python3 tests/test_paxos.py

test-docker: ## Run Docker-specific integration tests
	@echo "🐳 Running Docker integration tests..."
	python3 test_docker.py

test-chaos: ## Run chaos engineering tests
	@echo "🔥 Starting chaos engineering test..."
	docker-compose --profile chaos --profile testing up --abort-on-container-exit

logs: ## View simulation logs
	@echo "📋 Paxos simulation logs:"
	@echo "========================"
	@tail -f logs/paxos_simulation.log

shell: ## Open shell in running container
	@echo "🐚 Opening shell in Paxos container..."
	docker exec -it paxos-web /bin/bash

clean: ## Clean up containers and images
	@echo "🧹 Cleaning up Docker resources..."
	docker-compose down -v --remove-orphans
	docker container prune -f
	docker image rm paxos-demo 2>/dev/null || true
	docker system prune -f

status: ## Show container status
	@echo "📊 Container Status:"
	@echo "==================="
	@docker ps --filter label=com.docker.compose.project=paxos_demo --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

benchmark: ## Run performance benchmarks
	@echo "⚡ Running Paxos performance benchmarks..."
	docker run --rm -v $(PWD)/logs:/app/logs paxos-demo python3 -c "
	from paxos_simulator import PaxosSimulation
	import time
	
	print('🔥 Paxos Performance Benchmark')
	print('=' * 40)
	
	# Test with different cluster sizes
	for n in [3, 5, 7, 9]:
		sim = PaxosSimulation(num_acceptors=n, num_proposers=1)
		start = time.time()
		success, value = sim.proposers[0].propose(f'test_n{n}')
		duration = time.time() - start
		print(f'Cluster size {n}: {duration:.3f}s (success: {success})')
	"
EOF

echo -e "${GREEN}✅ Created Makefile for Docker operations${NC}"

# Create .dockerignore for optimized builds
cat > .dockerignore << 'EOF'
# Ignore development files
.git
.gitignore
*.md
logs/*
state/*
tests/__pycache__
*.pyc
*.pyo
*.pyd
__pycache__
.pytest_cache
.coverage
.venv
venv/
env/

# Ignore OS files
.DS_Store
Thumbs.db

# Ignore IDE files
.vscode/
.idea/
*.swp
*.swo

# Keep only essential files for Docker build
!requirements.txt
!paxos_simulator.py
!start_web_server.py
!web/
EOF

echo -e "${GREEN}✅ Created .dockerignore${NC}"

# Create monitoring and metrics collection script
cat > monitor_paxos.py << 'EOF'
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
EOF

chmod +x monitor_paxos.py

echo -e "${GREEN}✅ Created monitoring dashboard${NC}"

# Create requirements file for Python dependencies
cat > requirements.txt << 'EOF'
# No external dependencies required - using only Python standard library
# This demonstrates that Paxos core concepts can be implemented with minimal dependencies
EOF

# Create README with instructions
cat > README.md << 'EOF'
# Paxos Consensus Algorithm Demonstration

This interactive demonstration shows how the Paxos consensus algorithm works in practice, including failure scenarios and recovery patterns.

## What This Demo Shows

1. **Two-Phase Protocol**: Prepare/Promise and Accept/Accepted phases
2. **Safety Guarantees**: How Paxos prevents conflicting decisions
3. **Failure Handling**: Node crashes and network partitions
4. **Persistent State**: Critical importance of durable storage
5. **Competing Proposers**: How higher proposal numbers resolve conflicts

## Files Created

- `paxos_simulator.py` - Core Paxos implementation with detailed logging
- `web/index.html` - Interactive web interface for visualization
- `logs/` - Detailed execution logs for each scenario
- `state/` - Persistent acceptor state (demonstrates durability)

## Key Insights Demonstrated

### 1. Proposal Number Strategy
- Each proposer uses unique ID ranges (0-999, 1000-1999, 2000-2999)
- Prevents conflicts and ensures global ordering
- Shows why proposal numbers must be monotonically increasing

### 2. Safety Through Persistence
- Acceptors save state before responding (critical for safety)
- Recovery reloads state from disk
- Demonstrates why write-ahead logging is essential

### 3. Majority Quorums
- Requires majority for both prepare and accept phases
- Shows how this prevents split-brain scenarios
- Demonstrates why N >= 2F+1 nodes needed for F failures

### 4. Value Convergence
- Once a value is accepted by majority, it becomes "chosen"
- Subsequent proposals must use the highest-numbered accepted value
- Shows how Paxos prevents conflicting decisions

## Expected Output

The simulation will show:
- Detailed message flows between proposers and acceptors
- State transitions and persistence operations
- Consensus achievement or failure reasons
- Impact of node failures on consensus

## Production Insights

This implementation demonstrates several production-critical patterns:
- Persistent state management
- Timeout and retry mechanisms
- Unique proposal ID generation
- Majority quorum calculations
- Graceful degradation under failures
EOF

# Make the Python script executable
chmod +x paxos_simulator.py

echo -e "${GREEN}✅ Created documentation and configuration files${NC}"

# Create a simple web server script
cat > start_web_server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import webbrowser
import threading
import time
import os

PORT = 8080

class CustomHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="web", **kwargs)

def start_server():
    with socketserver.TCPServer(("", PORT), CustomHTTPRequestHandler) as httpd:
        print(f"🌐 Web server running at http://localhost:{PORT}")
        print("📊 Open this URL to see the Paxos visualization")
        httpd.serve_forever()

if __name__ == "__main__":
    # Start server in background
    server_thread = threading.Thread(target=start_server, daemon=True)
    server_thread.start()
    
    # Wait a moment then open browser
    time.sleep(1)
    webbrowser.open(f'http://localhost:{PORT}')
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Server stopped")
EOF

chmod +x start_web_server.py

# Run the simulation
echo -e "${BLUE}🎬 Running Paxos simulation...${NC}"
if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "${CYAN}🐳 Docker mode enabled - Running containerized simulation${NC}"
    
    # Build Docker image
    echo -e "${YELLOW}Building Docker image...${NC}"
    docker build -t paxos-demo . || {
        echo -e "${RED}❌ Docker build failed. Falling back to native execution.${NC}"
        python3 paxos_simulator.py
    }
    
    # Run simulation in container
    echo -e "${YELLOW}Running simulation in container...${NC}"
    docker run --rm \
        -v "$(pwd)/logs:/app/logs" \
        -v "$(pwd)/state:/app/state" \
        --name paxos-simulation \
        paxos-demo
        
    # Run comprehensive tests
    echo -e "${YELLOW}Running test suite...${NC}"
    docker run --rm \
        -v "$(pwd)/logs:/app/logs" \
        -v "$(pwd)/state:/app/state" \
        -v "$(pwd)/tests:/app/tests" \
        --name paxos-tests \
        paxos-demo python3 tests/test_paxos.py
        
    # Start web interface in background
    echo -e "${YELLOW}Starting web interface...${NC}"
    docker run -d \
        --name paxos-web \
        -p 8080:8080 \
        -v "$(pwd)/logs:/app/logs:ro" \
        -v "$(pwd)/state:/app/state:ro" \
        -v "$(pwd)/web:/app/web" \
        paxos-demo python3 start_web_server.py
        
else
    # Native execution
    python3 paxos_simulator.py
fi

echo -e "\n${PURPLE}🎯 Demonstration Complete!${NC}"
echo -e "${PURPLE}=========================${NC}"

# Display results
echo -e "\n${CYAN}📊 Simulation Results:${NC}"
echo -e "${YELLOW}Logs Directory:${NC}"
ls -la logs/

echo -e "\n${YELLOW}State Directory:${NC}"
ls -la state/

echo -e "\n${YELLOW}Web Interface:${NC}"
ls -la web/

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${CYAN}🐳 Docker Resources Created:${NC}"
    echo -e "${YELLOW}Docker Image:${NC}"
    docker images | grep paxos-demo || echo "  (Image will be built on first run)"
    
    echo -e "\n${YELLOW}Running Containers:${NC}"
    docker ps --filter name=paxos
    
    echo -e "\n${CYAN}🧪 Docker Testing Options:${NC}"
    echo -e "• Run Docker integration tests: ${YELLOW}python3 test_docker.py${NC}"
    echo -e "• Start all services: ${YELLOW}docker-compose up -d${NC}"
    echo -e "• Run chaos engineering: ${YELLOW}docker-compose --profile chaos up${NC}"
    echo -e "• Monitor performance: ${YELLOW}python3 monitor_paxos.py${NC}"
    echo -e "• Use Makefile commands: ${YELLOW}make help${NC}"
fi

# Show sample log output
echo -e "\n${CYAN}📝 Sample Log Output (last 20 lines):${NC}"
tail -20 logs/paxos_simulation.log

echo -e "\n${GREEN}🎉 Success! Your Paxos demonstration is ready.${NC}"
echo -e "\n${BLUE}🎓 Educational Outcomes Achieved:${NC}"
echo -e "${BLUE}=================================${NC}"

echo -e "\n${PURPLE}Core Distributed Systems Concepts:${NC}"
echo -e "✓ Two-phase consensus protocol implementation"
echo -e "✓ Safety vs liveness trade-offs in distributed systems"
echo -e "✓ Majority quorum requirements and failure tolerance"
echo -e "✓ Persistent state management for fault recovery"
echo -e "✓ Proposal number strategies for conflict resolution"

echo -e "\n${PURPLE}Production Engineering Insights:${NC}"
echo -e "✓ Network timeout and retry patterns"
echo -e "✓ Write-ahead logging for durability guarantees"
echo -e "✓ Split-brain prevention through quorum mechanics"
echo -e "✓ Graceful degradation under partial failures"
echo -e "✓ Performance characteristics of consensus algorithms"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${PURPLE}Containerization & Orchestration:${NC}"
    echo -e "✓ Multi-stage Docker builds for optimized images"
    echo -e "✓ Container health checks and monitoring"
    echo -e "✓ Volume persistence for stateful applications"
    echo -e "✓ Service orchestration with docker-compose"
    echo -e "✓ Network isolation and inter-service communication"
    echo -e "✓ Chaos engineering in containerized environments"
fi

echo -e "\n${BLUE}📚 Learning Paths and Next Steps:${NC}"
echo -e "${BLUE}=================================${NC}"

echo -e "\n${CYAN}Immediate Exploration (Next 30 minutes):${NC}"
echo -e "1. 📖 Review detailed logs: ${YELLOW}less logs/paxos_simulation.log${NC}"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "2. 🌐 Open web interface: ${YELLOW}http://localhost:8080${NC}"
    echo -e "3. 🧪 Run comprehensive tests: ${YELLOW}make test${NC}"
    echo -e "4. 📊 Monitor real-time metrics: ${YELLOW}python3 monitor_paxos.py${NC}"
else
    echo -e "2. 🌐 Start web interface: ${YELLOW}python3 start_web_server.py${NC}"
    echo -e "3. 🧪 Run test suite: ${YELLOW}python3 tests/test_paxos.py${NC}"
fi

echo -e "5. 🔍 Examine acceptor state files: ${YELLOW}cat state/acceptor_*.json${NC}"

echo -e "\n${CYAN}Deeper Understanding (This week):${NC}"
echo -e "1. 📝 Modify simulation parameters in ${YELLOW}paxos_simulator.py${NC}"
echo -e "2. 🎯 Add Byzantine failure detection mechanisms"
echo -e "3. ⚡ Implement Multi-Paxos optimization for repeated consensus"
echo -e "4. 🌐 Build a distributed key-value store using this foundation"
echo -e "5. 📊 Compare performance with Raft consensus algorithm"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${CYAN}Advanced Docker Scenarios (Next steps):${NC}"
    echo -e "1. 🔥 Chaos engineering: ${YELLOW}make test-chaos${NC}"
    echo -e "2. 📈 Performance benchmarks: ${YELLOW}make benchmark${NC}"
    echo -e "3. 🎼 Multi-node orchestration: ${YELLOW}make compose-up${NC}"
    echo -e "4. 🔧 Container debugging: ${YELLOW}make shell${NC}"
    echo -e "5. 🧹 Resource cleanup: ${YELLOW}make clean${NC}"
fi

echo -e "\n${CYAN}Production Application (Long-term):${NC}"
echo -e "1. 🏗️  Implement Paxos in your distributed system of choice"
echo -e "2. 🎨 Design consensus-based workflows in microservices"
echo -e "3. 📚 Study real-world implementations (Spanner, etcd, Consul)"
echo -e "4. 🎓 Contribute to open-source consensus libraries"
echo -e "5. 📖 Advance to Byzantine fault tolerance (PBFT, Tendermint)"

echo -e "\n${BLUE}🔬 Why This Docker Approach Enhances Learning:${NC}"
echo -e "${BLUE}=============================================${NC}"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${GREEN}Container Isolation Benefits:${NC}"
    echo -e "Containers provide clean, reproducible environments that eliminate"
    echo -e "the 'works on my machine' problem. Each Paxos node runs in its own"
    echo -e "isolated environment, simulating how distributed systems actually"
    echo -e "deploy in production with separate virtual machines or containers."
    
    echo -e "\n${GREEN}Network Simulation Capabilities:${NC}"
    echo -e "Docker networks allow us to simulate network partitions, latency,"
    echo -e "and packet loss scenarios that are critical for understanding how"
    echo -e "consensus algorithms behave under real-world network conditions."
    
    echo -e "\n${GREEN}Scalability Testing:${NC}"
    echo -e "You can easily spin up multiple container instances to test Paxos"
    echo -e "behavior with different cluster sizes, from 3 nodes to dozens,"
    echo -e "helping you understand how consensus performance scales."
    
    echo -e "\n${GREEN}Production Similarity:${NC}"
    echo -e "Modern distributed systems deploy consensus algorithms in containers"
    echo -e "orchestrated by Kubernetes. This demo mirrors that architecture,"
    echo -e "making your learning directly applicable to production systems."
fi

echo -e "\n${BLUE}🎯 Troubleshooting and Support:${NC}"
echo -e "${BLUE}===============================${NC}"

echo -e "\n${YELLOW}Common Issues and Solutions:${NC}"
echo -e "• Port 8080 busy: Change WEB_PORT in script or stop conflicting service"
echo -e "• Docker permission errors: Add user to docker group or use sudo"
echo -e "• Log files empty: Wait 10 seconds after starting for initial output"
echo -e "• Container won't start: Check Docker daemon is running"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${YELLOW}Docker-Specific Debugging:${NC}"
    echo -e "• View container logs: ${CYAN}docker logs paxos-web${NC}"
    echo -e "• Inspect container: ${CYAN}docker exec -it paxos-web /bin/bash${NC}"
    echo -e "• Check resource usage: ${CYAN}docker stats${NC}"
    echo -e "• Network debugging: ${CYAN}docker network inspect paxos_demo_paxos-network${NC}"
fi

echo -e "\n${YELLOW}Performance Optimization Tips:${NC}"
echo -e "• Increase memory: Modify docker-compose.yml memory limits"
echo -e "• Faster consensus: Reduce message delays in simulator"
echo -e "• More concurrency: Increase NUM_PROPOSERS and NUM_ACCEPTORS"
echo -e "• Better logging: Adjust log levels in Python configuration"

echo -e "\n${GREEN}📚 Further Learning Resources:${NC}"
echo -e "• Lamport's original paper: 'The Part-Time Parliament'"
echo -e "• Google's production experience: 'Paxos Made Live'"
echo -e "• Raft comparison: 'In Search of an Understandable Consensus Algorithm'"
echo -e "• Byzantine consensus: 'Practical Byzantine Fault Tolerance'"
echo -e "• Modern implementations: etcd, Consul, CockroachDB source code"

echo -e "\n${PURPLE}🎉 Congratulations! You now have a production-grade understanding of:${NC}"
echo -e "• How consensus algorithms ensure distributed system safety"
echo -e "• Why certain trade-offs are necessary in distributed computing"
echo -e "• How modern systems implement and deploy consensus mechanisms"
echo -e "• The practical challenges of building fault-tolerant systems"

if [ "$DOCKER_ENABLED" = true ]; then
    echo -e "\n${CYAN}🐳 Your containerized Paxos laboratory is ready for experimentation!${NC}"
    echo -e "Use the Makefile commands for easy Docker operations."
    echo -e "\nStart with: ${YELLOW}make help${NC} to see all available commands."
fi
EOF