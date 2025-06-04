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
