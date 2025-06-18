#!/bin/bash
# Clock Synchronization Observatory - Complete Setup Script
# Creates a hands-on learning environment for distributed time concepts

set -euo pipefail

echo "🕰️  Setting up Clock Synchronization Observatory..."
echo "=================================================="

# Create project structure
mkdir -p clock-sync-observatory/{src,web,tests,config,logs,data}
cd clock-sync-observatory

# Create requirements file with latest stable versions
cat > requirements.txt << 'EOF'
flask==3.0.0
websockets==12.0
numpy==1.26.2
asyncio==3.4.3
psutil==5.9.6
requests==2.31.0
plotly==5.18.0
dash==2.16.1
pandas==2.1.4
datetime==5.4
aiofiles==23.2.0
structlog==23.2.0
EOF

# Create Docker Compose configuration
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  clock-node-1:
    build: .
    command: python src/clock_node.py --node-id=1 --port=8001 --drift-rate=0.001
    ports:
      - "8001:8001"
    environment:
      - NODE_ID=1
      - DRIFT_RATE=0.001
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config

  clock-node-2:
    build: .
    command: python src/clock_node.py --node-id=2 --port=8002 --drift-rate=-0.0005
    ports:
      - "8002:8002"
    environment:
      - NODE_ID=2
      - DRIFT_RATE=-0.0005
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config

  clock-node-3:
    build: .
    command: python src/clock_node.py --node-id=3 --port=8003 --drift-rate=0.0015
    ports:
      - "8003:8003"
    environment:
      - NODE_ID=3
      - DRIFT_RATE=0.0015
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config

  vector-clock-service:
    build: .
    command: python src/vector_clock_service.py
    ports:
      - "8004:8004"
    depends_on:
      - clock-node-1
      - clock-node-2
      - clock-node-3
    volumes:
      - ./logs:/app/logs

  truetime-simulator:
    build: .
    command: python src/truetime_simulator.py
    ports:
      - "8005:8005"
    volumes:
      - ./logs:/app/logs

  web-dashboard:
    build: .
    command: python src/web_dashboard.py
    ports:
      - "3000:3000"
    depends_on:
      - clock-node-1
      - clock-node-2
      - clock-node-3
      - vector-clock-service
      - truetime-simulator
    volumes:
      - ./web:/app/web
      - ./logs:/app/logs

volumes:
  logs_data:
  config_data:
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs config data web

# Set Python path
ENV PYTHONPATH=/app/src

EXPOSE 3000 8001 8002 8003 8004 8005

CMD ["python", "src/web_dashboard.py"]
EOF

# Generate Clock Node Implementation
cat > src/clock_node.py << 'EOF'
"""
Clock Node Implementation
Simulates a distributed system node with configurable clock drift,
NTP synchronization, and network delays.
"""

import asyncio
import time
import json
import argparse
import logging
import random
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
import numpy as np
from flask import Flask, jsonify, request
import threading
import structlog

@dataclass
class ClockReading:
    """Represents a clock reading with metadata"""
    node_id: int
    logical_time: float
    physical_time: float
    drift_offset: float
    sync_quality: float
    uncertainty_bound: float
    timestamp: float

@dataclass
class SyncEvent:
    """Represents a clock synchronization event"""
    node_id: int
    sync_source: str
    offset_correction: float
    rtt_ms: float
    accuracy_estimate: float
    timestamp: float

class ClockNode:
    """
    Simulates a distributed system node with realistic clock behavior:
    - Configurable drift rates
    - NTP-style synchronization with network delays
    - Uncertainty estimation
    - Health monitoring
    """
    
    def __init__(self, node_id: int, port: int, drift_rate: float = 0.001):
        self.node_id = node_id
        self.port = port
        self.drift_rate = drift_rate  # ppm (parts per million)
        
        # Clock state
        self.start_time = time.time()
        self.accumulated_drift = 0.0
        self.last_sync_time = time.time()
        self.sync_quality = 1.0
        self.uncertainty_bound = 0.001  # 1ms default uncertainty
        
        # Synchronization state
        self.sync_history: List[SyncEvent] = []
        self.peer_nodes: List[str] = []
        
        # Monitoring
        self.readings_history: List[ClockReading] = []
        
        # Setup logging
        self.logger = structlog.get_logger("clock_node").bind(node_id=node_id)
        
        # Flask app for HTTP API
        self.app = Flask(f"clock_node_{node_id}")
        self.setup_routes()
        
        # Background tasks
        self.running = True
        self.drift_task = None
        self.sync_task = None
        
    def setup_routes(self):
        """Setup HTTP API routes"""
        
        @self.app.route('/time', methods=['GET'])
        def get_time():
            """Get current time reading with metadata"""
            reading = self.get_clock_reading()
            return jsonify(asdict(reading))
        
        @self.app.route('/sync', methods=['POST'])
        def sync_with_source():
            """Simulate NTP synchronization with external source"""
            data = request.get_json() or {}
            source_time = data.get('source_time', time.time())
            rtt_ms = data.get('rtt_ms', random.uniform(1, 50))
            
            sync_event = self.synchronize_clock(source_time, rtt_ms)
            return jsonify(asdict(sync_event))
        
        @self.app.route('/health', methods=['GET'])
        def health_check():
            """Get node health and synchronization status"""
            return jsonify({
                'node_id': self.node_id,
                'status': 'healthy',
                'drift_rate': self.drift_rate,
                'sync_quality': self.sync_quality,
                'uncertainty_bound': self.uncertainty_bound,
                'last_sync': self.last_sync_time,
                'readings_count': len(self.readings_history)
            })
        
        @self.app.route('/history', methods=['GET'])
        def get_history():
            """Get historical clock readings and sync events"""
            return jsonify({
                'readings': [asdict(r) for r in self.readings_history[-100:]],
                'sync_events': [asdict(s) for s in self.sync_history[-50:]]
            })
    
    def get_clock_reading(self) -> ClockReading:
        """Get current clock reading with all metadata"""
        current_time = time.time()
        elapsed = current_time - self.start_time
        
        # Apply drift (simulates oscillator drift)
        drift_offset = elapsed * self.drift_rate
        
        # Add some random jitter (simulates measurement noise)
        jitter = random.gauss(0, 0.0001)  # 0.1ms standard deviation
        
        physical_time = current_time + drift_offset + jitter
        logical_time = physical_time  # For now, same as physical
        
        reading = ClockReading(
            node_id=self.node_id,
            logical_time=logical_time,
            physical_time=physical_time,
            drift_offset=drift_offset,
            sync_quality=self.sync_quality,
            uncertainty_bound=self.uncertainty_bound,
            timestamp=current_time
        )
        
        # Store reading for history
        self.readings_history.append(reading)
        if len(self.readings_history) > 1000:
            self.readings_history = self.readings_history[-500:]
        
        return reading
    
    def synchronize_clock(self, source_time: float, rtt_ms: float) -> SyncEvent:
        """
        Simulate NTP-style clock synchronization
        
        Args:
            source_time: Authoritative time from sync source
            rtt_ms: Round-trip time to sync source in milliseconds
        """
        current_reading = self.get_clock_reading()
        
        # Estimate network delay (assume symmetric)
        network_delay = rtt_ms / 2000.0  # Convert to seconds
        
        # Calculate offset (difference between our clock and source)
        estimated_source_time = source_time + network_delay
        offset_correction = estimated_source_time - current_reading.physical_time
        
        # Apply correction (in real NTP, this would be gradual)
        self.accumulated_drift += offset_correction
        
        # Update synchronization quality based on RTT
        if rtt_ms < 10:
            self.sync_quality = 0.95
        elif rtt_ms < 50:
            self.sync_quality = 0.80
        else:
            self.sync_quality = 0.60
        
        # Update uncertainty bound
        self.uncertainty_bound = max(rtt_ms / 1000.0, 0.001)
        
        self.last_sync_time = time.time()
        
        sync_event = SyncEvent(
            node_id=self.node_id,
            sync_source="external_ntp",
            offset_correction=offset_correction,
            rtt_ms=rtt_ms,
            accuracy_estimate=self.sync_quality,
            timestamp=self.last_sync_time
        )
        
        self.sync_history.append(sync_event)
        if len(self.sync_history) > 100:
            self.sync_history = self.sync_history[-50:]
        
        self.logger.info("Clock synchronized", 
                        offset_ms=offset_correction * 1000,
                        rtt_ms=rtt_ms,
                        quality=self.sync_quality)
        
        return sync_event
    
    async def run_periodic_sync(self):
        """Simulate periodic NTP synchronization"""
        while self.running:
            try:
                # Simulate sync with external source
                # Add realistic network conditions
                rtt_ms = random.uniform(5, 100)
                source_time = time.time()  # Assume perfect external source
                
                self.synchronize_clock(source_time, rtt_ms)
                
                # Wait 30-60 seconds for next sync (with jitter)
                await asyncio.sleep(random.uniform(30, 60))
                
            except Exception as e:
                self.logger.error("Sync failed", error=str(e))
                await asyncio.sleep(10)
    
    def start_background_tasks(self):
        """Start background tasks for drift and synchronization"""
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
        async def run_tasks():
            await self.run_periodic_sync()
        
        loop.run_until_complete(run_tasks())
    
    def run(self):
        """Run the clock node"""
        # Start background tasks in separate thread
        sync_thread = threading.Thread(target=self.start_background_tasks, daemon=True)
        sync_thread.start()
        
        self.logger.info("Clock node starting", 
                        node_id=self.node_id, 
                        port=self.port,
                        drift_rate=self.drift_rate)
        
        # Run Flask app
        self.app.run(host='0.0.0.0', port=self.port, debug=False)

def main():
    parser = argparse.ArgumentParser(description='Run a Clock Node')
    parser.add_argument('--node-id', type=int, required=True, help='Node ID')
    parser.add_argument('--port', type=int, required=True, help='HTTP port')
    parser.add_argument('--drift-rate', type=float, default=0.001, help='Clock drift rate (ppm)')
    
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(level=logging.INFO)
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer()
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    
    node = ClockNode(args.node_id, args.port, args.drift_rate)
    node.run()

if __name__ == '__main__':
    main()
EOF

# Generate Vector Clock Service
cat > src/vector_clock_service.py << 'EOF'
"""
Vector Clock Service Implementation
Demonstrates logical clock behavior with causality tracking
across distributed events.
"""

import asyncio
import time
import json
import logging
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from flask import Flask, jsonify, request
import threading
import structlog

@dataclass
class VectorClock:
    """Vector clock implementation"""
    clocks: Dict[int, int]
    
    def __post_init__(self):
        if not isinstance(self.clocks, dict):
            self.clocks = {}
    
    def tick(self, node_id: int):
        """Increment clock for local event"""
        self.clocks[node_id] = self.clocks.get(node_id, 0) + 1
    
    def update(self, other_clock: 'VectorClock', node_id: int):
        """Update vector clock when receiving message"""
        # Take maximum of corresponding entries
        for other_node, other_time in other_clock.clocks.items():
            self.clocks[other_node] = max(
                self.clocks.get(other_node, 0), 
                other_time
            )
        # Increment own clock
        self.tick(node_id)
    
    def happens_before(self, other: 'VectorClock') -> bool:
        """Check if this clock happens before another"""
        if not other.clocks:
            return False
        
        all_less_or_equal = True
        at_least_one_less = False
        
        for node_id in set(self.clocks.keys()) | set(other.clocks.keys()):
            self_time = self.clocks.get(node_id, 0)
            other_time = other.clocks.get(node_id, 0)
            
            if self_time > other_time:
                all_less_or_equal = False
                break
            elif self_time < other_time:
                at_least_one_less = True
        
        return all_less_or_equal and at_least_one_less
    
    def concurrent_with(self, other: 'VectorClock') -> bool:
        """Check if events are concurrent"""
        return not self.happens_before(other) and not other.happens_before(self)
    
    def copy(self) -> 'VectorClock':
        """Create a copy of this vector clock"""
        return VectorClock(self.clocks.copy())

@dataclass
class Event:
    """Represents a distributed system event"""
    event_id: str
    node_id: int
    event_type: str
    vector_clock: VectorClock
    data: Dict
    timestamp: float

class VectorClockService:
    """
    Service for managing vector clocks across distributed events.
    Provides APIs for event creation, causality analysis, and visualization.
    """
    
    def __init__(self, port: int = 8004):
        self.port = port
        self.events: List[Event] = []
        self.node_clocks: Dict[int, VectorClock] = {}
        self.event_counter = 0
        
        # Setup logging
        self.logger = structlog.get_logger("vector_clock_service")
        
        # Flask app
        self.app = Flask("vector_clock_service")
        self.setup_routes()
    
    def setup_routes(self):
        """Setup HTTP API routes"""
        
        @self.app.route('/event', methods=['POST'])
        def create_event():
            """Create a new event with vector clock"""
            data = request.get_json()
            
            node_id = data.get('node_id')
            event_type = data.get('event_type', 'local')
            event_data = data.get('data', {})
            
            if node_id is None:
                return jsonify({'error': 'node_id required'}), 400
            
            # Get or create node's vector clock
            if node_id not in self.node_clocks:
                self.node_clocks[node_id] = VectorClock({})
            
            node_clock = self.node_clocks[node_id]
            
            # Handle message reception (update with sender's clock)
            if event_type == 'message_received':
                sender_clock_data = data.get('sender_clock', {})
                sender_clock = VectorClock(sender_clock_data)
                node_clock.update(sender_clock, node_id)
            else:
                # Local event - just tick own clock
                node_clock.tick(node_id)
            
            # Create event
            self.event_counter += 1
            event = Event(
                event_id=f"event_{self.event_counter}",
                node_id=node_id,
                event_type=event_type,
                vector_clock=node_clock.copy(),
                data=event_data,
                timestamp=time.time()
            )
            
            self.events.append(event)
            
            self.logger.info("Event created",
                           event_id=event.event_id,
                           node_id=node_id,
                           vector_clock=event.vector_clock.clocks)
            
            return jsonify({
                'event_id': event.event_id,
                'vector_clock': event.vector_clock.clocks,
                'node_id': node_id
            })
        
        @self.app.route('/events', methods=['GET'])
        def get_events():
            """Get all events with causality analysis"""
            result = []
            
            for event in self.events[-50:]:  # Last 50 events
                event_dict = asdict(event)
                event_dict['vector_clock'] = event.vector_clock.clocks
                
                # Add causality relationships
                causality = []
                for other_event in self.events:
                    if other_event.event_id != event.event_id:
                        if other_event.vector_clock.happens_before(event.vector_clock):
                            causality.append({
                                'type': 'happens_before',
                                'event_id': other_event.event_id
                            })
                        elif event.vector_clock.concurrent_with(other_event.vector_clock):
                            causality.append({
                                'type': 'concurrent',
                                'event_id': other_event.event_id
                            })
                
                event_dict['causality'] = causality
                result.append(event_dict)
            
            return jsonify(result)
        
        @self.app.route('/causality/<event_id1>/<event_id2>', methods=['GET'])
        def check_causality(event_id1: str, event_id2: str):
            """Check causality relationship between two events"""
            event1 = next((e for e in self.events if e.event_id == event_id1), None)
            event2 = next((e for e in self.events if e.event_id == event_id2), None)
            
            if not event1 or not event2:
                return jsonify({'error': 'Event not found'}), 404
            
            relationship = 'concurrent'
            if event1.vector_clock.happens_before(event2.vector_clock):
                relationship = 'event1_before_event2'
            elif event2.vector_clock.happens_before(event1.vector_clock):
                relationship = 'event2_before_event1'
            
            return jsonify({
                'event1': event_id1,
                'event2': event_id2,
                'relationship': relationship,
                'event1_clock': event1.vector_clock.clocks,
                'event2_clock': event2.vector_clock.clocks
            })
        
        @self.app.route('/simulate', methods=['POST'])
        def simulate_scenario():
            """Simulate a predefined causality scenario"""
            scenario = request.get_json().get('scenario', 'basic')
            
            if scenario == 'basic':
                self._simulate_basic_scenario()
            elif scenario == 'concurrent':
                self._simulate_concurrent_scenario()
            elif scenario == 'complex':
                self._simulate_complex_scenario()
            
            return jsonify({'status': 'simulation_complete', 'scenario': scenario})
        
        @self.app.route('/reset', methods=['POST'])
        def reset_state():
            """Reset all events and clocks"""
            self.events = []
            self.node_clocks = {}
            self.event_counter = 0
            return jsonify({'status': 'reset_complete'})
    
    def _simulate_basic_scenario(self):
        """Simulate basic causality scenario"""
        # Node 1 creates event A
        self.node_clocks[1] = VectorClock({})
        self.node_clocks[1].tick(1)
        event_a = Event("A", 1, "local", self.node_clocks[1].copy(), {"msg": "Event A"}, time.time())
        self.events.append(event_a)
        
        # Node 1 sends message to Node 2
        self.node_clocks[2] = VectorClock({})
        self.node_clocks[2].update(self.node_clocks[1], 2)
        event_b = Event("B", 2, "message_received", self.node_clocks[2].copy(), {"msg": "Received from 1"}, time.time())
        self.events.append(event_b)
        
        # Node 2 creates local event
        self.node_clocks[2].tick(2)
        event_c = Event("C", 2, "local", self.node_clocks[2].copy(), {"msg": "Event C"}, time.time())
        self.events.append(event_c)
    
    def _simulate_concurrent_scenario(self):
        """Simulate concurrent events scenario"""
        # Two nodes create concurrent events
        self.node_clocks[1] = VectorClock({})
        self.node_clocks[2] = VectorClock({})
        
        self.node_clocks[1].tick(1)
        event_a = Event("A", 1, "local", self.node_clocks[1].copy(), {"msg": "Concurrent A"}, time.time())
        self.events.append(event_a)
        
        self.node_clocks[2].tick(2)
        event_b = Event("B", 2, "local", self.node_clocks[2].copy(), {"msg": "Concurrent B"}, time.time())
        self.events.append(event_b)
    
    def _simulate_complex_scenario(self):
        """Simulate complex multi-node scenario"""
        # Initialize 3 nodes
        for i in range(1, 4):
            self.node_clocks[i] = VectorClock({})
        
        # Node 1 events
        self.node_clocks[1].tick(1)
        self.events.append(Event("1a", 1, "local", self.node_clocks[1].copy(), {"msg": "1a"}, time.time()))
        
        self.node_clocks[1].tick(1)
        self.events.append(Event("1b", 1, "local", self.node_clocks[1].copy(), {"msg": "1b"}, time.time()))
        
        # Node 1 -> Node 2
        self.node_clocks[2].update(self.node_clocks[1], 2)
        self.events.append(Event("2a", 2, "message_received", self.node_clocks[2].copy(), {"msg": "from 1"}, time.time()))
        
        # Node 2 -> Node 3
        self.node_clocks[3].update(self.node_clocks[2], 3)
        self.events.append(Event("3a", 3, "message_received", self.node_clocks[3].copy(), {"msg": "from 2"}, time.time()))
        
        # Node 3 -> Node 1
        self.node_clocks[1].update(self.node_clocks[3], 1)
        self.events.append(Event("1c", 1, "message_received", self.node_clocks[1].copy(), {"msg": "from 3"}, time.time()))
    
    def run(self):
        """Run the vector clock service"""
        self.logger.info("Vector Clock Service starting", port=self.port)
        self.app.run(host='0.0.0.0', port=self.port, debug=False)

def main():
    service = VectorClockService()
    service.run()

if __name__ == '__main__':
    main()
EOF

# Generate TrueTime Simulator
cat > src/truetime_simulator.py << 'EOF'
"""
TrueTime Simulator Implementation
Demonstrates uncertainty intervals and commit wait protocols
similar to Google Spanner's TrueTime system.
"""

import time
import random
import json
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from flask import Flask, jsonify, request
import structlog

@dataclass
class TrueTimeReading:
    """Represents a TrueTime reading with uncertainty bounds"""
    earliest: float
    latest: float
    now_estimate: float
    uncertainty_ms: float
    confidence: float
    sources: List[str]
    timestamp: float

@dataclass
class CommitWaitEvent:
    """Represents a commit wait operation"""
    transaction_id: str
    commit_timestamp: float
    wait_duration_ms: float
    uncertainty_at_commit: float
    status: str  # 'waiting', 'committed', 'aborted'
    timestamp: float

class TrueTimeSimulator:
    """
    Simulates Google's TrueTime API with uncertainty intervals,
    multiple time sources, and commit wait protocols.
    """
    
    def __init__(self, port: int = 8005):
        self.port = port
        
        # Time sources with different characteristics
        self.time_sources = {
            'gps': {'uncertainty_ms': 0.1, 'reliability': 0.99},
            'atomic': {'uncertainty_ms': 1.0, 'reliability': 0.999},
            'ntp': {'uncertainty_ms': 5.0, 'reliability': 0.95}
        }
        
        # Active transactions in commit wait
        self.active_commits: Dict[str, CommitWaitEvent] = {}
        self.commit_history: List[CommitWaitEvent] = []
        
        # Setup logging
        self.logger = structlog.get_logger("truetime_simulator")
        
        # Flask app
        self.app = Flask("truetime_simulator")
        self.setup_routes()
    
    def setup_routes(self):
        """Setup HTTP API routes"""
        
        @self.app.route('/now', methods=['GET'])
        def truetime_now():
            """Get current TrueTime reading with uncertainty bounds"""
            reading = self.get_truetime_reading()
            return jsonify(asdict(reading))
        
        @self.app.route('/commit', methods=['POST'])
        def commit_transaction():
            """Start commit wait for a transaction"""
            data = request.get_json()
            
            transaction_id = data.get('transaction_id')
            if not transaction_id:
                return jsonify({'error': 'transaction_id required'}), 400
            
            # Get current TrueTime
            tt_reading = self.get_truetime_reading()
            
            # Calculate commit timestamp (latest possible time)
            commit_timestamp = tt_reading.latest
            
            # Calculate required wait duration
            wait_duration_ms = max(0, (commit_timestamp - time.time()) * 1000)
            
            commit_event = CommitWaitEvent(
                transaction_id=transaction_id,
                commit_timestamp=commit_timestamp,
                wait_duration_ms=wait_duration_ms,
                uncertainty_at_commit=tt_reading.uncertainty_ms,
                status='waiting' if wait_duration_ms > 0 else 'committed',
                timestamp=time.time()
            )
            
            if wait_duration_ms > 0:
                self.active_commits[transaction_id] = commit_event
            else:
                self.commit_history.append(commit_event)
            
            self.logger.info("Transaction commit initiated",
                           transaction_id=transaction_id,
                           wait_duration_ms=wait_duration_ms,
                           commit_timestamp=commit_timestamp)
            
            return jsonify(asdict(commit_event))
        
        @self.app.route('/commit/<transaction_id>', methods=['GET'])
        def check_commit_status(transaction_id: str):
            """Check commit status of a transaction"""
            # Check if still waiting
            if transaction_id in self.active_commits:
                commit_event = self.active_commits[transaction_id]
                current_time = time.time()
                
                if current_time >= commit_event.commit_timestamp:
                    # Commit wait period has passed
                    commit_event.status = 'committed'
                    self.commit_history.append(commit_event)
                    del self.active_commits[transaction_id]
                
                return jsonify(asdict(commit_event))
            
            # Check commit history
            for event in self.commit_history:
                if event.transaction_id == transaction_id:
                    return jsonify(asdict(event))
            
            return jsonify({'error': 'Transaction not found'}), 404
        
        @self.app.route('/ordering', methods=['POST'])
        def check_ordering():
            """Check if two transactions can be safely ordered"""
            data = request.get_json()
            
            tx1_time = data.get('tx1_commit_time')
            tx2_time = data.get('tx2_commit_time')
            
            if tx1_time is None or tx2_time is None:
                return jsonify({'error': 'Both transaction times required'}), 400
            
            # Get uncertainty bounds for both times
            uncertainty1 = self._estimate_uncertainty_at_time(tx1_time)
            uncertainty2 = self._estimate_uncertainty_at_time(tx2_time)
            
            # Check if uncertainty intervals overlap
            tx1_earliest = tx1_time - uncertainty1
            tx1_latest = tx1_time + uncertainty1
            tx2_earliest = tx2_time - uncertainty2
            tx2_latest = tx2_time + uncertainty2
            
            can_order = tx1_latest < tx2_earliest or tx2_latest < tx1_earliest
            
            return jsonify({
                'can_safely_order': can_order,
                'tx1_bounds': {'earliest': tx1_earliest, 'latest': tx1_latest},
                'tx2_bounds': {'earliest': tx2_earliest, 'latest': tx2_latest},
                'overlap': not can_order
            })
        
        @self.app.route('/stats', methods=['GET'])
        def get_stats():
            """Get TrueTime system statistics"""
            current_time = time.time()
            
            # Calculate average commit wait time
            recent_commits = [c for c in self.commit_history if current_time - c.timestamp < 300]
            avg_wait_ms = sum(c.wait_duration_ms for c in recent_commits) / max(len(recent_commits), 1)
            
            # Current active commits
            active_count = len(self.active_commits)
            
            # Current uncertainty
            current_reading = self.get_truetime_reading()
            
            return jsonify({
                'current_uncertainty_ms': current_reading.uncertainty_ms,
                'confidence': current_reading.confidence,
                'active_commits': active_count,
                'recent_commits': len(recent_commits),
                'avg_commit_wait_ms': avg_wait_ms,
                'time_sources': list(self.time_sources.keys())
            })
        
        @self.app.route('/simulate_failure', methods=['POST'])
        def simulate_failure():
            """Simulate time source failures"""
            data = request.get_json()
            source = data.get('source')
            
            if source not in self.time_sources:
                return jsonify({'error': 'Invalid time source'}), 400
            
            # Temporarily reduce reliability
            original_reliability = self.time_sources[source]['reliability']
            self.time_sources[source]['reliability'] = 0.1
            
            # Will restore after 30 seconds (in real implementation)
            return jsonify({
                'status': 'failure_simulated',
                'source': source,
                'original_reliability': original_reliability,
                'new_reliability': 0.1
            })
    
    def get_truetime_reading(self) -> TrueTimeReading:
        """
        Generate a TrueTime reading with uncertainty bounds
        based on available time sources and their reliability.
        """
        current_time = time.time()
        
        # Simulate time source readings
        source_readings = []
        active_sources = []
        
        for source, config in self.time_sources.items():
            # Check if source is available (simulate failures)
            if random.random() < config['reliability']:
                # Add noise to time reading
                noise = random.gauss(0, config['uncertainty_ms'] / 1000.0)
                reading_time = current_time + noise
                
                source_readings.append({
                    'source': source,
                    'time': reading_time,
                    'uncertainty': config['uncertainty_ms']
                })
                active_sources.append(source)
        
        if not source_readings:
            # Fallback case - use system time with high uncertainty
            uncertainty_ms = 100.0
            confidence = 0.1
            now_estimate = current_time
        else:
            # Calculate weighted average and uncertainty
            total_weight = sum(1.0 / r['uncertainty'] for r in source_readings)
            
            now_estimate = sum(
                r['time'] * (1.0 / r['uncertainty']) for r in source_readings
            ) / total_weight
            
            # Calculate combined uncertainty (simplified)
            min_uncertainty = min(r['uncertainty'] for r in source_readings)
            uncertainty_ms = min_uncertainty + random.uniform(0, 2)
            
            confidence = min(len(active_sources) / len(self.time_sources), 0.99)
        
        # Convert uncertainty to time bounds
        uncertainty_seconds = uncertainty_ms / 1000.0
        earliest = now_estimate - uncertainty_seconds
        latest = now_estimate + uncertainty_seconds
        
        return TrueTimeReading(
            earliest=earliest,
            latest=latest,
            now_estimate=now_estimate,
            uncertainty_ms=uncertainty_ms,
            confidence=confidence,
            sources=active_sources,
            timestamp=current_time
        )
    
    def _estimate_uncertainty_at_time(self, target_time: float) -> float:
        """Estimate uncertainty that would have existed at a given time"""
        # Simplified: assume uncertainty grows with time difference
        time_diff = abs(time.time() - target_time)
        base_uncertainty = 1.0  # 1ms base
        drift_factor = time_diff * 0.001  # Additional uncertainty due to drift
        
        return base_uncertainty + drift_factor
    
    def run(self):
        """Run the TrueTime simulator"""
        self.logger.info("TrueTime Simulator starting", port=self.port)
        self.app.run(host='0.0.0.0', port=self.port, debug=False)

def main():
    simulator = TrueTimeSimulator()
    simulator.run()

if __name__ == '__main__':
    main()
EOF

# Generate Web Dashboard
cat > src/web_dashboard.py << 'EOF'
"""
Web Dashboard for Clock Synchronization Observatory
Provides real-time visualization of clock synchronization,
vector clocks, and TrueTime uncertainty intervals.
"""

import asyncio
import json
import time
import requests
from typing import Dict, List, Optional
from flask import Flask, render_template, jsonify
import plotly.graph_objs as go
import plotly.utils
import structlog

class ClockSyncDashboard:
    """
    Main dashboard application for visualizing clock synchronization
    behavior across distributed systems.
    """
    
    def __init__(self, port: int = 3000):
        self.port = port
        self.app = Flask(__name__, template_folder='../web')
        
        # Service endpoints
        self.clock_nodes = [
            {'id': 1, 'url': 'http://clock-node-1:8001'},
            {'id': 2, 'url': 'http://clock-node-2:8002'},
            {'id': 3, 'url': 'http://clock-node-3:8003'}
        ]
        self.vector_service_url = 'http://vector-clock-service:8004'
        self.truetime_service_url = 'http://truetime-simulator:8005'
        
        # Setup logging
        self.logger = structlog.get_logger("dashboard")
        
        self.setup_routes()
    
    def setup_routes(self):
        """Setup web routes"""
        
        @self.app.route('/')
        def index():
            """Main dashboard page"""
            return render_template('index.html')
        
        @self.app.route('/api/clock-readings')
        def get_clock_readings():
            """Get current readings from all clock nodes"""
            readings = []
            
            for node in self.clock_nodes:
                try:
                    response = requests.get(f"{node['url']}/time", timeout=2)
                    if response.status_code == 200:
                        reading = response.json()
                        reading['status'] = 'healthy'
                        readings.append(reading)
                    else:
                        readings.append({
                            'node_id': node['id'],
                            'status': 'error',
                            'error': f"HTTP {response.status_code}"
                        })
                except Exception as e:
                    readings.append({
                        'node_id': node['id'],
                        'status': 'error',
                        'error': str(e)
                    })
            
            return jsonify(readings)
        
        @self.app.route('/api/clock-drift-chart')
        def get_clock_drift_chart():
            """Generate clock drift visualization"""
            try:
                # Collect historical data from all nodes
                all_history = []
                
                for node in self.clock_nodes:
                    try:
                        response = requests.get(f"{node['url']}/history", timeout=5)
                        if response.status_code == 200:
                            history = response.json()
                            all_history.append({
                                'node_id': node['id'],
                                'readings': history.get('readings', [])
                            })
                    except Exception as e:
                        self.logger.warning("Failed to get history", node_id=node['id'], error=str(e))
                
                # Create Plotly chart
                fig = go.Figure()
                
                colors = ['#3b82f6', '#22c55e', '#ef4444']
                
                for i, node_data in enumerate(all_history):
                    readings = node_data['readings'][-50:]  # Last 50 readings
                    
                    if readings:
                        timestamps = [r['timestamp'] for r in readings]
                        drift_offsets = [r.get('drift_offset', 0) * 1000 for r in readings]  # Convert to ms
                        
                        fig.add_trace(go.Scatter(
                            x=timestamps,
                            y=drift_offsets,
                            mode='lines+markers',
                            name=f"Node {node_data['node_id']}",
                            line=dict(color=colors[i % len(colors)])
                        ))
                
                fig.update_layout(
                    title="Clock Drift Over Time",
                    xaxis_title="Time",
                    yaxis_title="Drift Offset (ms)",
                    height=400,
                    showlegend=True
                )
                
                return json.dumps(fig, cls=plotly.utils.PlotlyJSONEncoder)
                
            except Exception as e:
                self.logger.error("Chart generation failed", error=str(e))
                return jsonify({'error': str(e)})
        
        @self.app.route('/api/vector-events')
        def get_vector_events():
            """Get vector clock events"""
            try:
                response = requests.get(f"{self.vector_service_url}/events", timeout=5)
                if response.status_code == 200:
                    return response.json()
                else:
                    return jsonify({'error': 'Vector service unavailable'})
            except Exception as e:
                return jsonify({'error': str(e)})
        
        @self.app.route('/api/vector-simulate/<scenario>')
        def simulate_vector_scenario(scenario: str):
            """Trigger vector clock simulation"""
            try:
                response = requests.post(
                    f"{self.vector_service_url}/simulate",
                    json={'scenario': scenario},
                    timeout=5
                )
                return response.json()
            except Exception as e:
                return jsonify({'error': str(e)})
        
        @self.app.route('/api/truetime-reading')
        def get_truetime_reading():
            """Get current TrueTime reading"""
            try:
                response = requests.get(f"{self.truetime_service_url}/now", timeout=5)
                return response.json()
            except Exception as e:
                return jsonify({'error': str(e)})
        
        @self.app.route('/api/truetime-commit/<transaction_id>')
        def commit_transaction(transaction_id: str):
            """Start commit wait for transaction"""
            try:
                response = requests.post(
                    f"{self.truetime_service_url}/commit",
                    json={'transaction_id': transaction_id},
                    timeout=5
                )
                return response.json()
            except Exception as e:
                return jsonify({'error': str(e)})
        
        @self.app.route('/api/truetime-stats')
        def get_truetime_stats():
            """Get TrueTime statistics"""
            try:
                response = requests.get(f"{self.truetime_service_url}/stats", timeout=5)
                return response.json()
            except Exception as e:
                return jsonify({'error': str(e)})
    
    def run(self):
        """Run the dashboard application"""
        self.logger.info("Clock Sync Dashboard starting", port=self.port)
        self.app.run(host='0.0.0.0', port=self.port, debug=False)

def main():
    dashboard = ClockSyncDashboard()
    dashboard.run()

if __name__ == '__main__':
    main()
EOF

# Create web template
mkdir -p web
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Clock Synchronization Observatory</title>
    <script src="https://cdn.plot.ly/plotly-2.26.0.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            padding: 1rem 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        
        .header h1 {
            color: #2563eb;
            font-size: 1.8rem;
            margin-bottom: 0.5rem;
        }
        
        .header p {
            color: #6b7280;
            font-size: 0.95rem;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 2rem;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 2rem;
            margin-bottom: 2rem;
        }
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.2);
        }
        
        .card h2 {
            color: #1f2937;
            margin-bottom: 1rem;
            font-size: 1.2rem;
            border-bottom: 2px solid #e5e7eb;
            padding-bottom: 0.5rem;
        }
        
        .node-status {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.75rem;
            margin: 0.5rem 0;
            border-radius: 8px;
            border-left: 4px solid #22c55e;
        }
        
        .node-status.error {
            border-left-color: #ef4444;
            background-color: #fef2f2;
        }
        
        .node-status.healthy {
            border-left-color: #22c55e;
            background-color: #f0fdf4;
        }
        
        .status-indicator {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background-color: #22c55e;
        }
        
        .status-indicator.error {
            background-color: #ef4444;
        }
        
        .btn {
            background: #3b82f6;
            color: white;
            border: none;
            padding: 0.5rem 1rem;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.9rem;
            margin: 0.25rem;
            transition: background-color 0.2s;
        }
        
        .btn:hover {
            background: #2563eb;
        }
        
        .btn.secondary {
            background: #6b7280;
        }
        
        .btn.secondary:hover {
            background: #4b5563;
        }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 1rem;
            margin: 1rem 0;
        }
        
        .metric {
            text-align: center;
            padding: 1rem;
            background: #f8fafc;
            border-radius: 8px;
        }
        
        .metric-value {
            font-size: 1.5rem;
            font-weight: bold;
            color: #1f2937;
        }
        
        .metric-label {
            font-size: 0.8rem;
            color: #6b7280;
            margin-top: 0.25rem;
        }
        
        .event-list {
            max-height: 300px;
            overflow-y: auto;
            border: 1px solid #e5e7eb;
            border-radius: 6px;
            padding: 0.5rem;
        }
        
        .event-item {
            padding: 0.5rem;
            margin: 0.25rem 0;
            background: #f9fafb;
            border-radius: 4px;
            font-size: 0.85rem;
        }
        
        .event-item.concurrent {
            border-left: 3px solid #f59e0b;
        }
        
        .event-item.causal {
            border-left: 3px solid #3b82f6;
        }
        
        .loading {
            text-align: center;
            padding: 2rem;
            color: #6b7280;
        }
        
        .full-width {
            grid-column: 1 / -1;
        }
        
        .chart-container {
            height: 400px;
            margin-top: 1rem;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🕰️ Clock Synchronization Observatory</h1>
        <p>Explore distributed time, causality, and consensus in real-time</p>
    </div>
    
    <div class="container">
        <div class="grid">
            <!-- Clock Node Status -->
            <div class="card">
                <h2>Clock Node Status</h2>
                <div id="clock-status">
                    <div class="loading">Loading clock nodes...</div>
                </div>
                <div class="metrics" id="clock-metrics">
                    <!-- Metrics will be populated by JavaScript -->
                </div>
            </div>
            
            <!-- Vector Clock Events -->
            <div class="card">
                <h2>Vector Clock Events</h2>
                <div style="margin-bottom: 1rem;">
                    <button class="btn" onclick="simulateScenario('basic')">Basic Scenario</button>
                    <button class="btn" onclick="simulateScenario('concurrent')">Concurrent Events</button>
                    <button class="btn" onclick="simulateScenario('complex')">Complex Flow</button>
                    <button class="btn secondary" onclick="resetVectorClocks()">Reset</button>
                </div>
                <div class="event-list" id="vector-events">
                    <div class="loading">No events yet</div>
                </div>
            </div>
            
            <!-- TrueTime Uncertainty -->
            <div class="card">
                <h2>TrueTime Uncertainty</h2>
                <div id="truetime-status">
                    <div class="loading">Loading TrueTime data...</div>
                </div>
                <div style="margin-top: 1rem;">
                    <button class="btn" onclick="commitTransaction()">Start Transaction</button>
                    <button class="btn secondary" onclick="simulateFailure()">Simulate Failure</button>
                </div>
            </div>
            
            <!-- Clock Drift Visualization -->
            <div class="card full-width">
                <h2>Clock Drift Analysis</h2>
                <div class="chart-container" id="drift-chart">
                    <div class="loading">Loading drift analysis...</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let transactionCounter = 1;
        
        // Update clock status every 2 seconds
        setInterval(updateClockStatus, 2000);
        setInterval(updateVectorEvents, 3000);
        setInterval(updateTrueTimeStatus, 2000);
        setInterval(updateDriftChart, 5000);
        
        // Initial load
        updateClockStatus();
        updateVectorEvents();
        updateTrueTimeStatus();
        updateDriftChart();
        
        async function updateClockStatus() {
            try {
                const response = await fetch('/api/clock-readings');
                const readings = await response.json();
                
                const statusDiv = document.getElementById('clock-status');
                const metricsDiv = document.getElementById('clock-metrics');
                
                // Update status display
                statusDiv.innerHTML = readings.map(reading => {
                    if (reading.status === 'healthy') {
                        const driftMs = (reading.drift_offset * 1000).toFixed(2);
                        const uncertainty = (reading.uncertainty_bound * 1000).toFixed(1);
                        
                        return `
                            <div class="node-status healthy">
                                <div>
                                    <strong>Node ${reading.node_id}</strong><br>
                                    <small>Drift: ${driftMs}ms | Uncertainty: ±${uncertainty}ms</small>
                                </div>
                                <div class="status-indicator healthy"></div>
                            </div>
                        `;
                    } else {
                        return `
                            <div class="node-status error">
                                <div>
                                    <strong>Node ${reading.node_id}</strong><br>
                                    <small>Error: ${reading.error}</small>
                                </div>
                                <div class="status-indicator error"></div>
                            </div>
                        `;
                    }
                }).join('');
                
                // Update metrics
                const healthyNodes = readings.filter(r => r.status === 'healthy');
                const avgDrift = healthyNodes.length > 0
                    ? (healthyNodes.reduce((sum, r) => sum + Math.abs(r.drift_offset), 0) / healthyNodes.length * 1000).toFixed(2)
                    : '0.00';
                
                const maxUncertainty = healthyNodes.length > 0
                    ? Math.max(...healthyNodes.map(r => r.uncertainty_bound * 1000)).toFixed(1)
                    : '0.0';
                
                metricsDiv.innerHTML = `
                    <div class="metric">
                        <div class="metric-value">${healthyNodes.length}</div>
                        <div class="metric-label">Healthy Nodes</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value">${avgDrift}ms</div>
                        <div class="metric-label">Avg Drift</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value">±${maxUncertainty}ms</div>
                        <div class="metric-label">Max Uncertainty</div>
                    </div>
                `;
                
            } catch (error) {
                console.error('Failed to update clock status:', error);
            }
        }
        
        async function updateVectorEvents() {
            try {
                const response = await fetch('/api/vector-events');
                const events = await response.json();
                
                const eventsDiv = document.getElementById('vector-events');
                
                if (events.length === 0) {
                    eventsDiv.innerHTML = '<div class="loading">No events yet - try a simulation</div>';
                    return;
                }
                
                eventsDiv.innerHTML = events.slice(-10).reverse().map(event => {
                    const clockStr = JSON.stringify(event.vector_clock);
                    const hasCausality = event.causality && event.causality.length > 0;
                    const concurrentCount = event.causality ? event.causality.filter(c => c.type === 'concurrent').length : 0;
                    
                    const cssClass = concurrentCount > 0 ? 'concurrent' : 'causal';
                    
                    return `
                        <div class="event-item ${cssClass}">
                            <strong>${event.event_id}</strong> (Node ${event.node_id})<br>
                            <small>Vector: ${clockStr}</small><br>
                            <small>Type: ${event.event_type} | ${concurrentCount} concurrent events</small>
                        </div>
                    `;
                }).join('');
                
            } catch (error) {
                console.error('Failed to update vector events:', error);
            }
        }
        
        async function updateTrueTimeStatus() {
            try {
                const [readingResponse, statsResponse] = await Promise.all([
                    fetch('/api/truetime-reading'),
                    fetch('/api/truetime-stats')
                ]);
                
                const reading = await readingResponse.json();
                const stats = await statsResponse.json();
                
                const statusDiv = document.getElementById('truetime-status');
                
                const uncertaintyMs = reading.uncertainty_ms?.toFixed(2) || 'N/A';
                const confidence = ((reading.confidence || 0) * 100).toFixed(1);
                const activeSources = reading.sources?.join(', ') || 'None';
                const activeCommits = stats.active_commits || 0;
                const avgWait = stats.avg_commit_wait_ms?.toFixed(1) || '0.0';
                
                statusDiv.innerHTML = `
                    <div class="metrics">
                        <div class="metric">
                            <div class="metric-value">±${uncertaintyMs}ms</div>
                            <div class="metric-label">Uncertainty</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${confidence}%</div>
                            <div class="metric-label">Confidence</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${activeCommits}</div>
                            <div class="metric-label">Active Commits</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${avgWait}ms</div>
                            <div class="metric-label">Avg Wait</div>
                        </div>
                    </div>
                    <div style="margin-top: 1rem; padding: 0.75rem; background: #f8fafc; border-radius: 6px;">
                        <small><strong>Active Sources:</strong> ${activeSources}</small>
                    </div>
                `;
                
            } catch (error) {
                console.error('Failed to update TrueTime status:', error);
            }
        }
        
        async function updateDriftChart() {
            try {
                const response = await fetch('/api/clock-drift-chart');
                const chartData = await response.json();
                
                if (chartData.error) {
                    document.getElementById('drift-chart').innerHTML = 
                        `<div class="loading">Chart error: ${chartData.error}</div>`;
                    return;
                }
                
                Plotly.newPlot('drift-chart', chartData.data, chartData.layout, {
                    responsive: true,
                    displayModeBar: false
                });
                
            } catch (error) {
                console.error('Failed to update drift chart:', error);
                document.getElementById('drift-chart').innerHTML = 
                    '<div class="loading">Failed to load chart</div>';
            }
        }
        
        async function simulateScenario(scenario) {
            try {
                const response = await fetch(`/api/vector-simulate/${scenario}`, {
                    method: 'POST'
                });
                const result = await response.json();
                
                if (result.status === 'simulation_complete') {
                    // Immediately update events display
                    setTimeout(updateVectorEvents, 500);
                }
            } catch (error) {
                console.error('Failed to simulate scenario:', error);
            }
        }
        
        async function resetVectorClocks() {
            try {
                // Note: This would need to be implemented in the vector clock service
                await simulateScenario('reset');
                setTimeout(updateVectorEvents, 500);
            } catch (error) {
                console.error('Failed to reset vector clocks:', error);
            }
        }
        
        async function commitTransaction() {
            try {
                const transactionId = `tx_${transactionCounter++}`;
                const response = await fetch(`/api/truetime-commit/${transactionId}`, {
                    method: 'POST'
                });
                const result = await response.json();
                
                console.log('Transaction committed:', result);
                
                // Update TrueTime display immediately
                setTimeout(updateTrueTimeStatus, 500);
                
            } catch (error) {
                console.error('Failed to commit transaction:', error);
            }
        }
        
        async function simulateFailure() {
            try {
                // This would simulate a time source failure
                console.log('Simulating time source failure...');
                // Implementation would depend on TrueTime service API
            } catch (error) {
                console.error('Failed to simulate failure:', error);
            }
        }
    </script>
</body>
</html>
EOF

# Create test suite
cat > tests/test_observatory.py << 'EOF'
"""
Test suite for Clock Synchronization Observatory
Validates all components work correctly together.
"""

import time
import requests
import pytest
import subprocess
import json
from typing import Dict, List

class TestClockSyncObservatory:
    """Comprehensive test suite for the observatory system"""
    
    @classmethod
    def setup_class(cls):
        """Setup test environment"""
        cls.base_url = "http://localhost"
        cls.services = {
            'clock_node_1': 8001,
            'clock_node_2': 8002,
            'clock_node_3': 8003,
            'vector_service': 8004,
            'truetime_service': 8005,
            'dashboard': 3000
        }
        
        # Wait for services to be ready
        cls._wait_for_services()
    
    @classmethod
    def _wait_for_services(cls, timeout: int = 60):
        """Wait for all services to be ready"""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            all_ready = True
            
            for service, port in cls.services.items():
                try:
                    if 'clock_node' in service:
                        response = requests.get(f"{cls.base_url}:{port}/health", timeout=2)
                    elif service == 'dashboard':
                        response = requests.get(f"{cls.base_url}:{port}/", timeout=2)
                    else:
                        response = requests.get(f"{cls.base_url}:{port}/", timeout=2)
                    
                    if response.status_code not in [200, 404]:  # 404 is OK for some endpoints
                        all_ready = False
                        break
                        
                except requests.exceptions.RequestException:
                    all_ready = False
                    break
            
            if all_ready:
                print("All services are ready!")
                return
            
            time.sleep(2)
        
        raise TimeoutError("Services did not become ready within timeout period")
    
    def test_clock_nodes_running(self):
        """Test that all clock nodes are running and healthy"""
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/health")
            assert response.status_code == 200
            
            health_data = response.json()
            assert health_data['status'] == 'healthy'
            assert health_data['node_id'] == i
            assert 'drift_rate' in health_data
    
    def test_clock_readings(self):
        """Test clock reading functionality"""
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/time")
            assert response.status_code == 200
            
            reading = response.json()
            assert 'node_id' in reading
            assert 'physical_time' in reading
            assert 'logical_time' in reading
            assert 'drift_offset' in reading
            assert 'uncertainty_bound' in reading
    
    def test_clock_synchronization(self):
        """Test NTP-style synchronization"""
        node_url = f"{self.base_url}:8001"
        
        # Trigger synchronization
        sync_data = {
            'source_time': time.time(),
            'rtt_ms': 10.0
        }
        
        response = requests.post(f"{node_url}/sync", json=sync_data)
        assert response.status_code == 200
        
        sync_result = response.json()
        assert 'node_id' in sync_result
        assert 'offset_correction' in sync_result
        assert 'rtt_ms' in sync_result
    
    def test_vector_clock_service(self):
        """Test vector clock event creation and causality"""
        vector_url = f"{self.base_url}:8004"
        
        # Reset state first
        requests.post(f"{vector_url}/reset")
        
        # Create events on different nodes
        event1_data = {
            'node_id': 1,
            'event_type': 'local',
            'data': {'message': 'First event'}
        }
        
        response1 = requests.post(f"{vector_url}/event", json=event1_data)
        assert response1.status_code == 200
        result1 = response1.json()
        
        # Create second event that receives message from first
        event2_data = {
            'node_id': 2,
            'event_type': 'message_received',
            'sender_clock': result1['vector_clock'],
            'data': {'message': 'Received from node 1'}
        }
        
        response2 = requests.post(f"{vector_url}/event", json=event2_data)
        assert response2.status_code == 200
        result2 = response2.json()
        
        # Verify causality
        causality_response = requests.get(
            f"{vector_url}/causality/{result1['event_id']}/{result2['event_id']}"
        )
        assert causality_response.status_code == 200
        
        causality_data = causality_response.json()
        assert causality_data['relationship'] == 'event1_before_event2'
    
    def test_vector_clock_scenarios(self):
        """Test predefined vector clock scenarios"""
        vector_url = f"{self.base_url}:8004"
        
        scenarios = ['basic', 'concurrent', 'complex']
        
        for scenario in scenarios:
            response = requests.post(f"{vector_url}/simulate", json={'scenario': scenario})
            assert response.status_code == 200
            
            result = response.json()
            assert result['status'] == 'simulation_complete'
            assert result['scenario'] == scenario
    
    def test_truetime_service(self):
        """Test TrueTime uncertainty intervals"""
        truetime_url = f"{self.base_url}:8005"
        
        # Get TrueTime reading
        response = requests.get(f"{truetime_url}/now")
        assert response.status_code == 200
        
        reading = response.json()
        assert 'earliest' in reading
        assert 'latest' in reading
        assert 'uncertainty_ms' in reading
        assert 'confidence' in reading
        assert reading['earliest'] <= reading['latest']
    
    def test_truetime_commit_wait(self):
        """Test commit wait protocol"""
        truetime_url = f"{self.base_url}:8005"
        
        # Start transaction commit
        commit_data = {'transaction_id': 'test_tx_001'}
        response = requests.post(f"{truetime_url}/commit", json=commit_data)
        assert response.status_code == 200
        
        commit_result = response.json()
        assert 'transaction_id' in commit_result
        assert 'commit_timestamp' in commit_result
        assert 'wait_duration_ms' in commit_result
        assert 'status' in commit_result
        
        # Check commit status
        status_response = requests.get(f"{truetime_url}/commit/test_tx_001")
        assert status_response.status_code == 200
    
    def test_truetime_ordering(self):
        """Test transaction ordering logic"""
        truetime_url = f"{self.base_url}:8005"
        
        current_time = time.time()
        ordering_data = {
            'tx1_commit_time': current_time,
            'tx2_commit_time': current_time + 0.1  # 100ms later
        }
        
        response = requests.post(f"{truetime_url}/ordering", json=ordering_data)
        assert response.status_code == 200
        
        ordering_result = response.json()
        assert 'can_safely_order' in ordering_result
        assert 'tx1_bounds' in ordering_result
        assert 'tx2_bounds' in ordering_result
    
    def test_dashboard_endpoints(self):
        """Test dashboard API endpoints"""
        dashboard_url = f"{self.base_url}:3000"
        
        # Test main page
        response = requests.get(f"{dashboard_url}/")
        assert response.status_code == 200
        assert 'Clock Synchronization Observatory' in response.text
        
        # Test API endpoints
        api_endpoints = [
            '/api/clock-readings',
            '/api/vector-events',
            '/api/truetime-reading',
            '/api/truetime-stats'
        ]
        
        for endpoint in api_endpoints:
            response = requests.get(f"{dashboard_url}{endpoint}")
            assert response.status_code == 200
            
            # Should return valid JSON
            data = response.json()
            assert isinstance(data, (dict, list))
    
    def test_clock_drift_analysis(self):
        """Test clock drift visualization"""
        dashboard_url = f"{self.base_url}:3000"
        
        # Wait a bit for some drift data to accumulate
        time.sleep(5)
        
        response = requests.get(f"{dashboard_url}/api/clock-drift-chart")
        assert response.status_code == 200
        
        # Should return Plotly chart data
        chart_data = response.json()
        assert 'data' in chart_data or 'error' in chart_data
    
    def test_integration_workflow(self):
        """Test complete integration workflow"""
        # 1. Check all clock nodes are synchronized
        readings = []
        for i in range(1, 4):
            response = requests.get(f"{self.base_url}:800{i}/time")
            reading = response.json()
            readings.append(reading)
        
        # All nodes should have similar physical times (within reasonable bounds)
        times = [r['physical_time'] for r in readings]
        time_spread = max(times) - min(times)
        assert time_spread < 1.0  # Within 1 second
        
        # 2. Create vector clock events and verify causality
        vector_url = f"{self.base_url}:8004"
        requests.post(f"{vector_url}/simulate", json={'scenario': 'basic'})
        
        events_response = requests.get(f"{vector_url}/events")
        events = events_response.json()
        assert len(events) > 0
        
        # 3. Test TrueTime commit with uncertainty
        truetime_url = f"{self.base_url}:8005"
        commit_response = requests.post(
            f"{truetime_url}/commit",
            json={'transaction_id': 'integration_test_tx'}
        )
        commit_result = commit_response.json()
        assert 'wait_duration_ms' in commit_result
        
        # 4. Verify dashboard reflects all the above
        dashboard_url = f"{self.base_url}:3000"
        
        clock_readings = requests.get(f"{dashboard_url}/api/clock-readings").json()
        assert len(clock_readings) == 3
        
        vector_events = requests.get(f"{dashboard_url}/api/vector-events").json()
        assert len(vector_events) > 0
        
        truetime_stats = requests.get(f"{dashboard_url}/api/truetime-stats").json()
        assert 'current_uncertainty_ms' in truetime_stats

def main():
    """Run tests with proper error handling"""
    pytest_args = [
        __file__,
        '-v',
        '--tb=short',
        '--color=yes'
    ]
    
    exit_code = pytest.main(pytest_args)
    return exit_code

if __name__ == '__main__':
    exit(main())
EOF

echo "✅ Project structure created successfully"
echo ""

# Build and start the services
echo "🐳 Building Docker containers..."
docker-compose build --parallel

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi

echo "🚀 Starting services..."
docker-compose up -d

if [ $? -ne 0 ]; then
    echo "❌ Failed to start services"
    exit 1
fi

echo "⏳ Waiting for services to be ready..."
sleep 10

# Run health checks
echo "🔍 Running health checks..."

check_service() {
    local name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo "✅ $name is healthy"
            return 0
        fi
        echo "⏳ Waiting for $name (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ $name failed to start"
    return 1
}

# Check all services
check_service "Clock Node 1" "http://localhost:8001/health"
check_service "Clock Node 2" "http://localhost:8002/health"
check_service "Clock Node 3" "http://localhost:8003/health"
check_service "Vector Clock Service" "http://localhost:8004/events"
check_service "TrueTime Simulator" "http://localhost:8005/now"
check_service "Web Dashboard" "http://localhost:3000/"

echo ""
echo "🎉 Clock Synchronization Observatory is ready!"
echo "================================================"
echo ""
echo "🌐 Access Points:"
echo "  • Web Dashboard:     http://localhost:3000"
echo "  • Clock Node 1:      http://localhost:8001"
echo "  • Clock Node 2:      http://localhost:8002"
echo "  • Clock Node 3:      http://localhost:8003"
echo "  • Vector Clocks:     http://localhost:8004"
echo "  • TrueTime Sim:      http://localhost:8005"
echo ""
echo "🧪 Quick Tests:"
echo "  • Clock readings:    curl http://localhost:8001/time"
echo "  • Vector events:     curl http://localhost:8004/events"
echo "  • TrueTime reading:  curl http://localhost:8005/now"
echo ""
echo "🔬 Learning Experiments:"
echo ""
echo "1. 📊 Clock Drift Observation:"
echo "   Open the dashboard and watch the drift chart update in real-time"
echo "   Notice how each node's clock drifts at different rates"
echo ""
echo "2. 🔗 Vector Clock Causality:"
echo "   Click 'Basic Scenario' in the Vector Clock section"
echo "   Observe how events are ordered by causality, not time"
echo ""
echo "3. ⏱️  TrueTime Uncertainty:"
echo "   Click 'Start Transaction' in TrueTime section"
echo "   Watch how uncertainty bounds affect commit wait times"
echo ""
echo "4. 🧪 Run Comprehensive Tests:"
echo "   docker-compose exec web-dashboard python /app/tests/test_observatory.py"
echo ""
echo "📚 Explore the concepts:"
echo "  • Physical clock drift and NTP synchronization"
echo "  • Logical clocks and happens-before relationships"
echo "  • Uncertainty intervals and commit wait protocols"
echo "  • Distributed consensus and time-based ordering"
echo ""
echo "🛑 To stop: docker-compose down"
echo "🗂️  Logs: docker-compose logs [service-name]"
echo ""
echo "Happy exploring! 🕰️"