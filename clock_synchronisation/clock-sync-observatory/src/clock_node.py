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
