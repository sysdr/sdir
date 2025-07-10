import json
import time
import logging
from datetime import datetime, timezone
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
import redis
import os
import threading
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = 'streaming-demo-secret-key'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

# Redis connections
redis_analytics = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=6379, db=0)
redis_recommendations = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=6379, db=1)
redis_notifications = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=6379, db=2)

# Global stats
stats = {
    'analytics': defaultdict(int),
    'recommendations': defaultdict(int),
    'notifications': defaultdict(int),
    'system': defaultdict(int)
}

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html')

@app.route('/api/stats')
def get_stats():
    """Get current system stats"""
    try:
        # Get consumer metrics
        analytics_metrics = redis_analytics.hgetall('consumer_metrics:analytics')
        recommendations_metrics = redis_recommendations.hgetall('consumer_metrics:recommendations')
        notifications_metrics = redis_notifications.hgetall('consumer_metrics:notifications')
        
        # Get analytics data
        total_purchases = redis_analytics.get('analytics:total_purchases')
        total_revenue = redis_analytics.get('analytics:total_revenue')
        
        # Get recent notifications
        recent_notifications = redis_notifications.lrange('notifications:recent', 0, 9)
        
        return jsonify({
            'timestamp': datetime.now().isoformat(),
            'consumers': {
                'analytics': {k.decode(): v.decode() for k, v in analytics_metrics.items()},
                'recommendations': {k.decode(): v.decode() for k, v in recommendations_metrics.items()},
                'notifications': {k.decode(): v.decode() for k, v in notifications_metrics.items()}
            },
            'analytics': {
                'total_purchases': int(total_purchases) if total_purchases else 0,
                'total_revenue': float(total_revenue) if total_revenue else 0.0
            },
            'recent_notifications': [json.loads(n.decode()) for n in recent_notifications]
        })
    except Exception as e:
        logger.error(f"Error getting stats: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/kafka/topics')
def get_kafka_topics():
    """Get Kafka topic information"""
    # This would normally connect to Kafka admin API
    # For demo purposes, return simulated data
    return jsonify({
        'topics': [
            {
                'name': 'user-events',
                'partitions': 6,
                'replicas': 1,
                'messages_per_sec': 100,
                'consumer_lag': 0
            },
            {
                'name': 'system-metrics',
                'partitions': 6,
                'replicas': 1,
                'messages_per_sec': 50,
                'consumer_lag': 0
            }
        ]
    })

@app.route('/api/simulate/traffic_spike')
def simulate_traffic_spike():
    """Simulate traffic spike for testing"""
    # This would normally trigger increased producer rate
    logger.info("Simulating traffic spike...")
    return jsonify({'message': 'Traffic spike simulated'})

@app.route('/api/simulate/consumer_failure')
def simulate_consumer_failure():
    """Simulate consumer failure for testing"""
    # This would normally stop a consumer temporarily
    logger.info("Simulating consumer failure...")
    return jsonify({'message': 'Consumer failure simulated'})

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    logger.info('Client connected')
    emit('connected', {'data': 'Connected to streaming dashboard'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    logger.info('Client disconnected')

def background_thread():
    """Background thread to emit real-time updates"""
    with app.app_context():
        while True:
            try:
                # Get current stats
                stats_data = get_stats().get_json()
                
                # Emit to all connected clients
                socketio.emit('stats_update', stats_data)
                
                # Sleep for 2 seconds
                time.sleep(2)
                
            except Exception as e:
                logger.error(f"Error in background thread: {e}")
                time.sleep(5)

if __name__ == '__main__':
    # Start background thread
    thread = threading.Thread(target=background_thread)
    thread.daemon = True
    thread.start()
    
    # Run Flask app
    port = int(os.getenv('PORT', 8080))
    socketio.run(app, host='0.0.0.0', port=port, debug=False, allow_unsafe_werkzeug=True)
