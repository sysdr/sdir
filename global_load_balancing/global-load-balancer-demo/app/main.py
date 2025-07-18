#!/usr/bin/env python3
"""
Global Load Balancing Strategies Demo
System Design Interview Roadmap - Issue #99
"""

import os
import json
import time
import random
import threading
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import requests
from geopy.distance import geodesic

app = Flask(__name__, 
           template_folder='../templates',
           static_folder='../static')
app.config['SECRET_KEY'] = 'global-lb-demo-2025'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Global data centers with realistic coordinates
DATA_CENTERS = {
    'us-east-1': {
        'name': 'US East (Virginia)',
        'location': (39.0458, -77.5058),
        'capacity': 1000,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 50
    },
    'us-west-2': {
        'name': 'US West (Oregon)',
        'location': (45.5152, -122.6784),
        'capacity': 800,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 80
    },
    'eu-west-1': {
        'name': 'Europe (Ireland)',
        'location': (53.3498, -6.2603),
        'capacity': 600,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 120
    },
    'ap-southeast-1': {
        'name': 'Asia Pacific (Singapore)',
        'location': (1.3521, 103.8198),
        'capacity': 500,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 200
    }
}

# Simulated user locations
USER_LOCATIONS = {
    'new_york': (40.7128, -74.0060),
    'london': (51.5074, -0.1278),
    'tokyo': (35.6762, 139.6503),
    'sydney': (-33.8688, 151.2093),
    'sao_paulo': (-23.5505, -46.6333)
}

# Global statistics
GLOBAL_STATS = {
    'total_requests': 0,
    'successful_requests': 0,
    'failed_requests': 0,
    'average_latency': 0,
    'routing_decisions': []
}

class GlobalLoadBalancer:
    def __init__(self):
        self.strategy = 'latency'  # latency, geographic, round_robin
        self.health_check_interval = 5
        self.running = True
        
    def calculate_distance(self, user_location, dc_location):
        """Calculate distance between user and data center"""
        return geodesic(user_location, dc_location).kilometers
        
    def calculate_latency(self, distance, base_latency):
        """Simulate network latency based on distance"""
        # Rough approximation: 1ms per 100km + base latency + jitter
        network_latency = (distance / 100) * 1
        jitter = random.uniform(-10, 20)
        return base_latency + network_latency + jitter
        
    def get_healthy_data_centers(self):
        """Return only healthy data centers"""
        return {k: v for k, v in DATA_CENTERS.items() 
                if v['health'] == 'healthy'}
        
    def select_data_center(self, user_location, strategy=None):
        """Select optimal data center based on strategy"""
        if strategy is None:
            strategy = self.strategy
            
        healthy_dcs = self.get_healthy_data_centers()
        if not healthy_dcs:
            return None, float('inf'), 'no_healthy_dc'
            
        if strategy == 'geographic':
            # Route to nearest geographic location
            best_dc = min(healthy_dcs.items(),
                         key=lambda x: self.calculate_distance(user_location, x[1]['location']))
            
        elif strategy == 'latency':
            # Route based on estimated latency
            latencies = {}
            for dc_id, dc_info in healthy_dcs.items():
                distance = self.calculate_distance(user_location, dc_info['location'])
                latency = self.calculate_latency(distance, dc_info['latency_base'])
                latencies[dc_id] = (dc_info, latency)
            
            best_dc = min(latencies.items(), key=lambda x: x[1][1])
            return best_dc[0], best_dc[1][1], 'latency_optimized'
            
        elif strategy == 'capacity':
            # Route based on available capacity
            available_capacity = {
                dc_id: dc_info['capacity'] - dc_info['current_load']
                for dc_id, dc_info in healthy_dcs.items()
            }
            best_dc_id = max(available_capacity, key=available_capacity.get)
            best_dc = (best_dc_id, healthy_dcs[best_dc_id])
            
        else:  # round_robin
            dc_items = list(healthy_dcs.items())
            best_dc = random.choice(dc_items)
            
        # Calculate latency for selected DC
        distance = self.calculate_distance(user_location, best_dc[1]['location'])
        latency = self.calculate_latency(distance, best_dc[1]['latency_base'])
        
        return best_dc[0], latency, strategy
        
    def process_request(self, user_location_name):
        """Process a user request and return routing decision"""
        if user_location_name not in USER_LOCATIONS:
            return {'error': 'Invalid user location'}
            
        user_location = USER_LOCATIONS[user_location_name]
        
        # Select data center
        selected_dc, latency, strategy = self.select_data_center(user_location)
        
        if selected_dc is None:
            GLOBAL_STATS['failed_requests'] += 1
            return {
                'success': False,
                'error': 'No healthy data centers available',
                'timestamp': datetime.now().isoformat()
            }
            
        # Update data center load
        DATA_CENTERS[selected_dc]['current_load'] += 1
        
        # Simulate request processing
        processing_success = random.random() > 0.05  # 5% failure rate
        
        if processing_success:
            GLOBAL_STATS['successful_requests'] += 1
        else:
            GLOBAL_STATS['failed_requests'] += 1
            
        GLOBAL_STATS['total_requests'] += 1
        
        # Update average latency
        if GLOBAL_STATS['total_requests'] > 0:
            GLOBAL_STATS['average_latency'] = (
                GLOBAL_STATS['average_latency'] * (GLOBAL_STATS['total_requests'] - 1) + latency
            ) / GLOBAL_STATS['total_requests']
            
        # Record routing decision
        decision = {
            'timestamp': datetime.now().isoformat(),
            'user_location': user_location_name,
            'selected_dc': selected_dc,
            'latency': round(latency, 2),
            'strategy': strategy,
            'success': processing_success
        }
        
        GLOBAL_STATS['routing_decisions'].append(decision)
        if len(GLOBAL_STATS['routing_decisions']) > 100:
            GLOBAL_STATS['routing_decisions'].pop(0)
            
        return decision
        
    def health_check(self):
        """Periodic health check for data centers"""
        while self.running:
            for dc_id, dc_info in DATA_CENTERS.items():
                # Simulate health check
                if random.random() < 0.95:  # 95% chance of being healthy
                    dc_info['health'] = 'healthy'
                else:
                    dc_info['health'] = 'unhealthy'
                    
                # Simulate load decay
                dc_info['current_load'] = max(0, dc_info['current_load'] - 10)
                
            time.sleep(self.health_check_interval)

# Initialize load balancer
lb = GlobalLoadBalancer()

@app.route('/')
def index():
    """Main dashboard"""
    return render_template('index.html')

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/api/data-centers')
def get_data_centers():
    """Get current data center status"""
    return jsonify(DATA_CENTERS)

@app.route('/api/stats')
def get_stats():
    """Get global statistics"""
    return jsonify(GLOBAL_STATS)

@app.route('/api/request', methods=['POST'])
def handle_request():
    """Handle incoming request"""
    data = request.get_json()
    user_location = data.get('user_location', 'new_york')
    
    result = lb.process_request(user_location)
    
    # Emit real-time update
    socketio.emit('request_processed', result)
    
    return jsonify(result)

@app.route('/api/config', methods=['POST'])
def update_config():
    """Update load balancer configuration"""
    data = request.get_json()
    
    if 'strategy' in data:
        lb.strategy = data['strategy']
        
    if 'dc_health' in data:
        dc_id = data['dc_health']['dc_id']
        health_status = data['dc_health']['status']
        if dc_id in DATA_CENTERS:
            DATA_CENTERS[dc_id]['health'] = health_status
            
    return jsonify({'success': True})

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    emit('connected', {'data': 'Connected to Global Load Balancer Demo'})

@socketio.on('get_initial_data')
def handle_initial_data():
    """Send initial data to client"""
    emit('data_centers_update', DATA_CENTERS)
    emit('stats_update', GLOBAL_STATS)

def start_background_tasks():
    """Start background monitoring tasks"""
    health_thread = threading.Thread(target=lb.health_check)
    health_thread.daemon = True
    health_thread.start()
    
    def emit_updates():
        while True:
            socketio.emit('data_centers_update', DATA_CENTERS)
            socketio.emit('stats_update', GLOBAL_STATS)
            time.sleep(2)
    
    update_thread = threading.Thread(target=emit_updates)
    update_thread.daemon = True
    update_thread.start()

if __name__ == '__main__':
    print(f"🌍 Starting Global Load Balancer Demo...")
    print(f"📊 Dashboard: http://localhost:5000")
    print(f"🔧 API Documentation: http://localhost:5000/api/stats")
    
    start_background_tasks()
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
