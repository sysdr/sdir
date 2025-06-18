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
