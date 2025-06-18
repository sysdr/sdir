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
