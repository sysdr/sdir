from flask import Flask, render_template, jsonify
import redis
import json
import requests
from datetime import datetime

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/metrics')
def api_metrics():
    try:
        latest_metrics = redis_client.lrange('metrics', 0, 9)  # Last 10 metrics
        metrics = [json.loads(m) for m in latest_metrics]
        return jsonify(metrics)
    except:
        return jsonify([])

@app.route('/api/alerts')
def api_alerts():
    try:
        alerts = redis_client.lrange('alerts', 0, 9)  # Last 10 alerts
        alert_list = [json.loads(a) for a in alerts]
        return jsonify(alert_list)
    except:
        return jsonify([])

@app.route('/api/actions')
def api_actions():
    try:
        actions = redis_client.lrange('automation_actions', 0, 9)  # Last 10 actions
        action_list = [json.loads(a) for a in actions]
        return jsonify(action_list)
    except:
        return jsonify([])

@app.route('/api/simulate/<incident_type>')
def api_simulate(incident_type):
    """Proxy endpoint to simulate incidents via monitoring service"""
    try:
        # Make request to monitoring service from backend (no CORS issues)
        response = requests.get(f'http://monitoring:5001/simulate/{incident_type}')
        return jsonify(response.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
