from flask import Flask, jsonify
import redis
import json
import threading
import time
from datetime import datetime

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

class AlertManager:
    def __init__(self):
        self.active_alerts = {}
        self.alert_rules = {
            'high_cpu': {'threshold': 80, 'duration': 10},
            'high_memory': {'threshold': 80, 'duration': 15},
            'high_error_rate': {'threshold': 5.0, 'duration': 10},
            'slow_response': {'threshold': 1000, 'duration': 10}
        }
        
    def evaluate_alerts(self):
        """Continuously evaluate alert conditions"""
        while True:
            try:
                # Get latest metrics
                latest_metrics = redis_client.lrange('metrics', 0, 0)
                if not latest_metrics:
                    time.sleep(5)
                    continue
                    
                metrics = json.loads(latest_metrics[0])
                
                # Check CPU alert
                if metrics['cpu_usage'] > self.alert_rules['high_cpu']['threshold']:
                    self.trigger_alert('high_cpu', f"CPU usage at {metrics['cpu_usage']}%", 'critical')
                else:
                    self.resolve_alert('high_cpu')
                    
                # Check memory alert
                if metrics['memory_usage'] > self.alert_rules['high_memory']['threshold']:
                    self.trigger_alert('high_memory', f"Memory usage at {metrics['memory_usage']}%", 'critical')
                else:
                    self.resolve_alert('high_memory')
                    
                # Check error rate
                if metrics['error_rate'] > self.alert_rules['high_error_rate']['threshold']:
                    self.trigger_alert('high_error_rate', f"Error rate at {metrics['error_rate']}%", 'warning')
                else:
                    self.resolve_alert('high_error_rate')
                    
                # Check response time
                if metrics['response_time'] > self.alert_rules['slow_response']['threshold']:
                    self.trigger_alert('slow_response', f"Response time at {metrics['response_time']}ms", 'warning')
                else:
                    self.resolve_alert('slow_response')
                    
            except Exception as e:
                print(f"Error in alert evaluation: {e}")
                
            time.sleep(5)
            
    def trigger_alert(self, alert_id, message, severity):
        if alert_id not in self.active_alerts:
            alert = {
                'id': alert_id,
                'message': message,
                'severity': severity,
                'timestamp': datetime.now().isoformat(),
                'status': 'firing'
            }
            self.active_alerts[alert_id] = alert
            
            # Publish alert
            redis_client.lpush('alerts', json.dumps(alert))
            redis_client.ltrim('alerts', 0, 49)  # Keep last 50 alerts
            
    def resolve_alert(self, alert_id):
        if alert_id in self.active_alerts:
            alert = self.active_alerts[alert_id]
            alert['status'] = 'resolved'
            alert['resolved_at'] = datetime.now().isoformat()
            
            # Publish resolution
            redis_client.lpush('alerts', json.dumps(alert))
            del self.active_alerts[alert_id]

alert_manager = AlertManager()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/alerts')
def get_alerts():
    return jsonify(list(alert_manager.active_alerts.values()))

if __name__ == '__main__':
    # Start alert evaluation in background
    threading.Thread(target=alert_manager.evaluate_alerts, daemon=True).start()
    app.run(host='0.0.0.0', port=5002)
