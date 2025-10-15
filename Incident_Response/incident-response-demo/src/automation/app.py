from flask import Flask, jsonify
import redis
import json
import threading
import time
from datetime import datetime
import requests

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

class AutomationEngine:
    def __init__(self):
        self.remediation_actions = {
            'high_cpu': self.handle_high_cpu,
            'high_memory': self.handle_high_memory,
            'high_error_rate': self.handle_high_errors,
            'slow_response': self.handle_slow_response
        }
        self.action_history = []
        
    def monitor_alerts(self):
        """Monitor alerts and trigger automated responses"""
        processed_alerts = set()
        
        while True:
            try:
                alerts = redis_client.lrange('alerts', 0, -1)
                for alert_data in alerts:
                    alert = json.loads(alert_data)
                    
                    # Only process firing alerts we haven't seen
                    alert_key = f"{alert['id']}_{alert['timestamp']}"
                    if alert['status'] == 'firing' and alert_key not in processed_alerts:
                        processed_alerts.add(alert_key)
                        self.execute_remediation(alert)
                        
            except Exception as e:
                print(f"Error monitoring alerts: {e}")
                
            time.sleep(3)
            
    def execute_remediation(self, alert):
        """Execute automated remediation based on alert type"""
        alert_id = alert['id']
        
        if alert_id in self.remediation_actions:
            action_result = self.remediation_actions[alert_id](alert)
            
            # Record action
            action_record = {
                'timestamp': datetime.now().isoformat(),
                'alert_id': alert_id,
                'action': action_result['action'],
                'success': action_result['success'],
                'details': action_result['details']
            }
            
            self.action_history.append(action_record)
            redis_client.lpush('automation_actions', json.dumps(action_record))
            redis_client.ltrim('automation_actions', 0, 49)
            
    def handle_high_cpu(self, alert):
        """Automated response to high CPU usage"""
        return {
            'action': 'scale_up_instances',
            'success': True,
            'details': 'Triggered auto-scaling to add 2 additional instances'
        }
        
    def handle_high_memory(self, alert):
        """Automated response to high memory usage"""
        return {
            'action': 'restart_services',
            'success': True,
            'details': 'Initiated rolling restart of application services'
        }
        
    def handle_high_errors(self, alert):
        """Automated response to high error rate"""
        return {
            'action': 'circuit_breaker_activation',
            'success': True,
            'details': 'Activated circuit breaker for downstream services'
        }
        
    def handle_slow_response(self, alert):
        """Automated response to slow response times"""
        return {
            'action': 'cache_warmup',
            'success': True,
            'details': 'Initiated cache warm-up procedure'
        }

automation_engine = AutomationEngine()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/actions')
def get_actions():
    return jsonify(automation_engine.action_history[-10:])  # Last 10 actions

if __name__ == '__main__':
    # Start alert monitoring in background
    threading.Thread(target=automation_engine.monitor_alerts, daemon=True).start()
    app.run(host='0.0.0.0', port=5003)
