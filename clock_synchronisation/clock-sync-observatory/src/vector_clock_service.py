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
        # Ensure all keys are integers
        self.clocks = {int(k): v for k, v in self.clocks.items()}
    
    def tick(self, node_id: int):
        """Increment clock for local event"""
        self.clocks[node_id] = self.clocks.get(node_id, 0) + 1
    
    def update(self, other_clock: 'VectorClock', node_id: int):
        """Update vector clock when receiving message"""
        # Take maximum of corresponding entries
        for other_node, other_time in other_clock.clocks.items():
            # Ensure other_node is an integer
            other_node = int(other_node)
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
    
    def to_json(self) -> Dict[str, int]:
        """Convert to JSON-serializable format with string keys"""
        return {str(k): v for k, v in self.clocks.items()}

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
                # Convert string keys to integers for JSON compatibility
                sender_clock_data = {int(k): v for k, v in sender_clock_data.items()}
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
                           vector_clock=event.vector_clock.to_json())
            
            return jsonify({
                'event_id': event.event_id,
                'vector_clock': event.vector_clock.to_json(),
                'node_id': node_id
            })
        
        @self.app.route('/events', methods=['GET'])
        def get_events():
            """Get all events with causality analysis"""
            result = []
            
            for event in self.events[-50:]:  # Last 50 events
                event_dict = {
                    'event_id': event.event_id,
                    'node_id': event.node_id,
                    'event_type': event.event_type,
                    'vector_clock': event.vector_clock.to_json(),
                    'data': event.data,
                    'timestamp': event.timestamp
                }
                
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
                'event1_clock': event1.vector_clock.to_json(),
                'event2_clock': event2.vector_clock.to_json()
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
