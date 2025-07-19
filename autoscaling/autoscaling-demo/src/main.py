#!/usr/bin/env python3
"""
Autoscaling Demo Application
Demonstrates three different autoscaling strategies:
1. Reactive (threshold-based)
2. Predictive (ML-based)
3. Hybrid (combined approach)
"""

import time
import random
import logging
import threading
import os
import numpy as np
from dataclasses import dataclass
from collections import deque
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
import redis
import json

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'autoscaling-demo-secret'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

@dataclass
class SystemMetrics:
    timestamp: float
    cpu_percent: float
    memory_percent: float
    active_connections: int
    request_rate: float
    response_time: float
    queue_depth: int

@dataclass
class ScalingDecision:
    timestamp: float
    algorithm: str
    action: str  # 'scale_out', 'scale_in', 'no_action'
    trigger_metric: str
    current_instances: int
    target_instances: int
    reason: str

class LoadSimulator:
    """Simulates various load patterns for testing autoscaling"""
    
    def __init__(self):
        self.base_load = 30.0
        self.current_load = self.base_load
        self.pattern = 'steady'  # steady, spike, gradual, oscillating, chaos
        self.start_time = time.time()
        
    def get_current_load(self) -> float:
        elapsed = time.time() - self.start_time
        
        if self.pattern == 'steady':
            return self.base_load + random.uniform(-5, 5)
        elif self.pattern == 'spike':
            # Sudden spike pattern
            if 30 < elapsed < 90:
                return self.base_load + 50 + random.uniform(-10, 10)
            return self.base_load + random.uniform(-5, 5)
        elif self.pattern == 'gradual':
            # Gradual increase
            return self.base_load + (elapsed / 10) + random.uniform(-5, 5)
        elif self.pattern == 'oscillating':
            # Sine wave pattern
            return self.base_load + 20 * np.sin(elapsed / 20) + random.uniform(-5, 5)
        elif self.pattern == 'chaos':
            # Random spikes and drops
            if random.random() < 0.05:  # 5% chance of chaos event
                return random.uniform(10, 90)
            return self.current_load + random.uniform(-15, 15)
        
        return self.base_load

class ReactiveAutoscaler:
    """Traditional threshold-based autoscaling"""
    
    def __init__(self):
        self.scale_out_threshold = 70.0
        self.scale_in_threshold = 30.0
        self.cooldown_period = 30  # seconds
        self.last_scaling_time = 0
        
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        now = time.time()
        
        # Check cooldown
        if now - self.last_scaling_time < self.cooldown_period:
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='no_action',
                trigger_metric='cooldown',
                current_instances=current_instances,
                target_instances=current_instances,
                reason='Cooldown period active'
            )
        
        # Scale out decision
        if metrics.cpu_percent > self.scale_out_threshold:
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='scale_out',
                trigger_metric='cpu_percent',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason=f'CPU {metrics.cpu_percent:.1f}% > {self.scale_out_threshold}%'
            )
        
        # Scale in decision
        if metrics.cpu_percent < self.scale_in_threshold and current_instances > 1:
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='scale_in',
                trigger_metric='cpu_percent',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason=f'CPU {metrics.cpu_percent:.1f}% < {self.scale_in_threshold}%'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='reactive',
            action='no_action',
            trigger_metric='cpu_percent',
            current_instances=current_instances,
            target_instances=current_instances,
            reason='Within thresholds'
        )

class PredictiveAutoscaler:
    """ML-based predictive autoscaling"""
    
    def __init__(self):
        self.history = deque(maxlen=100)  # Store last 100 metrics
        self.prediction_window = 60  # Predict 60 seconds ahead
        
    def add_metrics(self, metrics: SystemMetrics):
        self.history.append(metrics)
    
    def predict_future_load(self) -> float:
        if len(self.history) < 10:
            return 50.0  # Default prediction
        
        # Simple moving average prediction with trend analysis
        recent_cpu = [m.cpu_percent for m in list(self.history)[-20:]]
        if len(recent_cpu) < 5:
            return recent_cpu[-1] if recent_cpu else 50.0
        
        # Calculate trend
        times = list(range(len(recent_cpu)))
        trend = np.polyfit(times, recent_cpu, 1)[0]  # Linear trend
        
        # Project forward
        prediction = recent_cpu[-1] + (trend * self.prediction_window / 10)
        return max(0, min(100, prediction))
    
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        self.add_metrics(metrics)
        predicted_cpu = self.predict_future_load()
        now = time.time()
        
        # Proactive scaling based on prediction
        if predicted_cpu > 75.0:
            return ScalingDecision(
                timestamp=now,
                algorithm='predictive',
                action='scale_out',
                trigger_metric='predicted_cpu',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason=f'Predicted CPU {predicted_cpu:.1f}% > 75%'
            )
        
        if predicted_cpu < 25.0 and current_instances > 1:
            return ScalingDecision(
                timestamp=now,
                algorithm='predictive',
                action='scale_in',
                trigger_metric='predicted_cpu',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason=f'Predicted CPU {predicted_cpu:.1f}% < 25%'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='predictive',
            action='no_action',
            trigger_metric='predicted_cpu',
            current_instances=current_instances,
            target_instances=current_instances,
            reason=f'Predicted CPU {predicted_cpu:.1f}% within range'
        )

class HybridAutoscaler:
    """Combines reactive and predictive approaches"""
    
    def __init__(self):
        self.reactive = ReactiveAutoscaler()
        self.predictive = PredictiveAutoscaler()
        self.last_scaling_time = 0
        self.adaptive_cooldown = 30
        
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        # Get recommendations from both approaches
        reactive_decision = self.reactive.should_scale(metrics, current_instances)
        predictive_decision = self.predictive.should_scale(metrics, current_instances)
        
        now = time.time()
        
        # Check cooldown
        if now - self.last_scaling_time < self.adaptive_cooldown:
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='no_action',
                trigger_metric='cooldown',
                current_instances=current_instances,
                target_instances=current_instances,
                reason='Hybrid cooldown active'
            )
        
        # If both recommend scaling out, do it immediately
        if (reactive_decision.action == 'scale_out' and 
            predictive_decision.action == 'scale_out'):
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_out',
                trigger_metric='both',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason='Both algorithms recommend scale out'
            )
        
        # If both recommend scaling in, do it immediately
        if (reactive_decision.action == 'scale_in' and 
            predictive_decision.action == 'scale_in'):
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_in',
                trigger_metric='both',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason='Both algorithms recommend scale in'
            )
        
        # If predictive suggests scaling out and reactive is neutral, scale out
        if (predictive_decision.action == 'scale_out' and 
            reactive_decision.action == 'no_action'):
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_out',
                trigger_metric='predictive',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason='Predictive scaling out (reactive neutral)'
            )
        
        # If reactive suggests scaling in and predictive is neutral, scale in
        if (reactive_decision.action == 'scale_in' and 
            predictive_decision.action == 'no_action'):
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_in',
                trigger_metric='reactive',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason='Reactive scaling in (predictive neutral)'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='hybrid',
            action='no_action',
            trigger_metric='hybrid',
            current_instances=current_instances,
            target_instances=current_instances,
            reason='Hybrid decision: no action needed'
        )

class AutoscalingEngine:
    """Main autoscaling engine that coordinates all algorithms"""
    
    def __init__(self):
        self.reactive_autoscaler = ReactiveAutoscaler()
        self.predictive_autoscaler = PredictiveAutoscaler()
        self.hybrid_autoscaler = HybridAutoscaler()
        self.load_simulator = LoadSimulator()
        
        self.instances = {
            'reactive': 1,
            'predictive': 1,
            'hybrid': 1
        }
        
        self.running = False
        # Use environment variable for Redis host, fallback to localhost for local development
        redis_host = os.environ.get('REDIS_URL', 'localhost').replace('redis://', '').split(':')[0]
        self.redis_client = redis.Redis(host=redis_host, port=6379, decode_responses=True)
        
    def generate_metrics(self) -> SystemMetrics:
        """Generate realistic system metrics"""
        base_cpu = self.load_simulator.get_current_load()
        
        # Add some realistic variation
        cpu_percent = max(0, min(100, base_cpu + random.uniform(-10, 10)))
        memory_percent = max(0, min(100, cpu_percent * 0.6 + random.uniform(-5, 5)))
        active_connections = max(0, int(cpu_percent * 2 + random.uniform(-10, 10)))
        request_rate = max(0, cpu_percent / 10 + random.uniform(-1, 1))
        response_time = max(0.1, 1.0 - (cpu_percent / 100) + random.uniform(-0.2, 0.2))
        queue_depth = max(0, int(cpu_percent / 5 + random.uniform(-5, 5)))
        
        return SystemMetrics(
            timestamp=time.time(),
            cpu_percent=cpu_percent,
            memory_percent=memory_percent,
            active_connections=active_connections,
            request_rate=request_rate,
            response_time=response_time,
            queue_depth=queue_depth
        )
    
    def run_scaling_cycle(self):
        """Run one complete scaling cycle"""
        metrics = self.generate_metrics()
        
        # Get scaling decisions from all algorithms
        reactive_decision = self.reactive_autoscaler.should_scale(metrics, self.instances['reactive'])
        predictive_decision = self.predictive_autoscaler.should_scale(metrics, self.instances['predictive'])
        hybrid_decision = self.hybrid_autoscaler.should_scale(metrics, self.instances['hybrid'])
        
        # Apply scaling decisions
        if reactive_decision.action == 'scale_out':
            self.instances['reactive'] = reactive_decision.target_instances
        elif reactive_decision.action == 'scale_in':
            self.instances['reactive'] = reactive_decision.target_instances
            
        if predictive_decision.action == 'scale_out':
            self.instances['predictive'] = predictive_decision.target_instances
        elif predictive_decision.action == 'scale_in':
            self.instances['predictive'] = predictive_decision.target_instances
            
        if hybrid_decision.action == 'scale_out':
            self.instances['hybrid'] = hybrid_decision.target_instances
        elif hybrid_decision.action == 'scale_in':
            self.instances['hybrid'] = hybrid_decision.target_instances
        
        # Log current state
        logger.info(f"CPU: {metrics.cpu_percent:.1f}%, Instances: {self.instances}")
        
        # Store metrics in Redis for web interface
        data = {
            'timestamp': metrics.timestamp,
            'cpu_percent': metrics.cpu_percent,
            'memory_percent': metrics.memory_percent,
            'active_connections': metrics.active_connections,
            'request_rate': metrics.request_rate,
            'response_time': metrics.response_time,
            'queue_depth': metrics.queue_depth,
            'instances': self.instances,
            'decisions': {
                'reactive': {
                    'action': reactive_decision.action,
                    'reason': reactive_decision.reason
                },
                'predictive': {
                    'action': predictive_decision.action,
                    'reason': predictive_decision.reason
                },
                'hybrid': {
                    'action': hybrid_decision.action,
                    'reason': hybrid_decision.reason
                }
            }
        }
        
        self.redis_client.set('current_metrics', json.dumps(data))
        
        # Emit to WebSocket clients
        socketio.emit('metrics_update', data)
    
    def start(self):
        """Start the autoscaling engine"""
        self.running = True
        logger.info("Autoscaling engine started")
        
        while self.running:
            try:
                self.run_scaling_cycle()
                time.sleep(2)  # Run every 2 seconds
            except Exception as e:
                logger.error(f"Error in scaling cycle: {e}")
                time.sleep(5)
    
    def stop(self):
        """Stop the autoscaling engine"""
        self.running = False
        logger.info("Autoscaling engine stopped")
    
    def set_load_pattern(self, pattern: str):
        """Set the load simulation pattern"""
        self.load_simulator.pattern = pattern
        logger.info(f"Load pattern changed to: {pattern}")

# Global engine instance
engine = AutoscalingEngine()

@app.route('/')
def index():
    try:
        return render_template('index.html')
    except Exception as e:
        logger.error(f"Template error: {e}")
        return f"Template error: {str(e)}", 500

@app.route('/api/start', methods=['GET', 'POST'])
def start_engine():
    if not engine.running:
        threading.Thread(target=engine.start, daemon=True).start()
    return jsonify({'status': 'started'})

@app.route('/api/stop', methods=['GET', 'POST'])
def stop_engine():
    engine.stop()
    return jsonify({'status': 'stopped'})

@app.route('/api/load_pattern', methods=['POST'])
def set_load_pattern():
    pattern = request.json.get('pattern', 'steady')
    engine.set_load_pattern(pattern)
    return jsonify({'status': 'pattern_changed', 'pattern': pattern})

@app.route('/api/status')
def get_status():
    try:
        metrics_data = engine.redis_client.get('current_metrics')
        if metrics_data:
            return jsonify(json.loads(metrics_data))
        else:
            return jsonify({
                'timestamp': time.time(),
                'cpu_percent': 0,
                'memory_percent': 0,
                'active_connections': 0,
                'request_rate': 0,
                'response_time': 0,
                'queue_depth': 0,
                'instances': engine.instances,
                'decisions': {}
            })
    except redis.ConnectionError:
        # Return basic status when Redis is not available
        return jsonify({
            'timestamp': time.time(),
            'cpu_percent': 0,
            'memory_percent': 0,
            'active_connections': 0,
            'request_rate': 0,
            'response_time': 0,
            'queue_depth': 0,
            'instances': engine.instances,
            'decisions': {},
            'redis_status': 'disconnected'
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@socketio.on('connect')
def handle_connect():
    logger.info('Client connected')
    emit('connected', {'data': 'Connected to autoscaling demo'})

if __name__ == '__main__':
    # Start the engine automatically
    threading.Thread(target=engine.start, daemon=True).start()
    socketio.run(app, host='0.0.0.0', port=3000, debug=False, allow_unsafe_werkzeug=True)
