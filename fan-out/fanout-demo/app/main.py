import asyncio
import json
import time
import random
import threading
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
import redis
import psutil
import logging
from prometheus_client import Counter, Histogram, Gauge, generate_latest

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'fanout-demo-secret'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# Redis connection
try:
    redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
    redis_client.ping()
except:
    redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

# Metrics
metrics = {
    'fanout_operations': Counter('fanout_operations_total', 'Total fanout operations', ['strategy']),
    'processing_time': Histogram('fanout_processing_seconds', 'Processing time', ['strategy']),
    'active_users': Gauge('active_users_total', 'Number of active users'),
    'queue_size': Gauge('message_queue_size', 'Size of message queue')
}

@dataclass
class User:
    id: str
    follower_count: int
    tier: str  # celebrity, regular, inactive
    last_activity: float
    
@dataclass
class Message:
    id: str
    user_id: str
    content: str
    timestamp: float
    fanout_strategy: str

class FanOutManager:
    def __init__(self):
        self.users: Dict[str, User] = {}
        self.message_queue = []
        self.is_processing = False
        self.back_pressure_threshold = 1000
        self.celebrity_threshold = 10000
        
    def add_user(self, user_id: str, follower_count: int = 0):
        tier = self.determine_tier(follower_count)
        self.users[user_id] = User(
            id=user_id,
            follower_count=follower_count,
            tier=tier,
            last_activity=time.time()
        )
        
    def determine_tier(self, follower_count: int) -> str:
        if follower_count >= self.celebrity_threshold:
            return "celebrity"
        elif follower_count >= 100:
            return "regular"
        else:
            return "inactive"
    
    def should_use_write_fanout(self, user: User) -> bool:
        # Use read fanout for celebrities, write fanout for others
        if user.tier == "celebrity":
            return False
        return len(self.message_queue) < self.back_pressure_threshold
    
    async def fanout_on_write(self, message: Message):
        """Pre-compute and store notifications for all followers"""
        start_time = time.time()
        user = self.users.get(message.user_id)
        
        if not user:
            return
            
        # Simulate writing to follower feeds
        follower_writes = min(user.follower_count, 1000)  # Cap for demo
        
        notifications = []
        for i in range(follower_writes):
            notification = {
                'follower_id': f'follower_{i}',
                'message_id': message.id,
                'content': message.content,
                'timestamp': message.timestamp
            }
            notifications.append(notification)
            
            # Simulate database write delay
            await asyncio.sleep(0.001)
        
        # Store in Redis
        key = f"feed_cache:{message.user_id}"
        redis_client.lpush(key, json.dumps(asdict(message)))
        redis_client.expire(key, 3600)  # 1 hour TTL
        
        processing_time = time.time() - start_time
        metrics['processing_time'].labels(strategy='write').observe(processing_time)
        
        return {
            'strategy': 'fanout_on_write',
            'notifications_created': len(notifications),
            'processing_time': processing_time
        }
    
    async def fanout_on_read(self, user_id: str) -> List[Dict]:
        """Generate feed on-demand when user requests it"""
        start_time = time.time()
        
        # Simulate fetching and ranking content
        feed_items = []
        
        # Get recent messages from popular users
        for uid, user in list(self.users.items())[:10]:  # Limit for demo
            key = f"feed_cache:{uid}"
            messages = redis_client.lrange(key, 0, 5)
            
            for msg_data in messages:
                try:
                    msg = json.loads(msg_data)
                    feed_items.append(msg)
                except:
                    continue
                    
            await asyncio.sleep(0.01)  # Simulate computation delay
        
        processing_time = time.time() - start_time
        metrics['processing_time'].labels(strategy='read').observe(processing_time)
        
        return {
            'strategy': 'fanout_on_read',
            'feed_items': feed_items[:20],  # Return top 20
            'processing_time': processing_time
        }
    
    async def process_message(self, message: Message):
        user = self.users.get(message.user_id)
        if not user:
            return
        
        # Update last activity
        user.last_activity = time.time()
        
        # Add message to queue for processing
        self.message_queue.append(message)
        
        # Update queue size metric
        metrics['queue_size'].set(len(self.message_queue))
        
        if self.should_use_write_fanout(user):
            message.fanout_strategy = 'write'
            result = await self.fanout_on_write(message)
            # Remove processed message from queue
            if message in self.message_queue:
                self.message_queue.remove(message)
        else:
            message.fanout_strategy = 'read'
            result = {'strategy': 'fanout_on_read', 'deferred': True}
            # For read fanout, keep message in queue for later processing
        
        metrics['fanout_operations'].labels(strategy=message.fanout_strategy).inc()
        
        # Update queue size metric again after processing
        metrics['queue_size'].set(len(self.message_queue))
        
        # Update active users metric
        self.update_active_users_metric()
        
        # Emit real-time update
        update_data = {
            'message': asdict(message),
            'result': result,
            'user_tier': user.tier,
            'timestamp': datetime.now().isoformat()
        }
        logger.info(f"Emitting fanout_update: {update_data}")
        socketio.emit('fanout_update', update_data)
        
        return result

    def update_active_users_metric(self):
        now = time.time()
        active_count = sum(1 for u in self.users.values() if now - u.last_activity < 60)
        metrics['active_users'].set(active_count)

fanout_manager = FanOutManager()

def cleanup_queue():
    """Periodically clean up old messages from queue and update active users metric"""
    while True:
        try:
            current_time = time.time()
            # Remove messages older than 60 seconds
            fanout_manager.message_queue = [
                msg for msg in fanout_manager.message_queue 
                if current_time - msg.timestamp < 60
            ]
            # Update queue size metric
            metrics['queue_size'].set(len(fanout_manager.message_queue))
            # Update active users metric
            fanout_manager.update_active_users_metric()
            time.sleep(30)  # Run every 30 seconds
        except Exception as e:
            logger.error(f"Error in queue cleanup: {e}")
            time.sleep(30)

# Initialize demo data
def init_demo_data():
    """Initialize with sample users of different tiers"""
    users = [
        ('celebrity_user', 50000),
        ('popular_user', 5000),
        ('regular_user1', 500),
        ('regular_user2', 200),
        ('new_user', 10)
    ]
    
    for user_id, followers in users:
        fanout_manager.add_user(user_id, followers)
    
    logger.info(f"Initialized {len(users)} demo users")
    
    # Start queue cleanup thread
    cleanup_thread = threading.Thread(target=cleanup_queue, daemon=True)
    cleanup_thread.start()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/users')
def get_users():
    return jsonify([asdict(user) for user in fanout_manager.users.values()])

@app.route('/api/post_message', methods=['POST'])
def post_message():
    data = request.json
    
    message = Message(
        id=f"msg_{int(time.time() * 1000)}",
        user_id=data['user_id'],
        content=data['content'],
        timestamp=time.time(),
        fanout_strategy=''
    )
    
    # Process asynchronously
    def process_async():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(fanout_manager.process_message(message))
        loop.close()
    
    thread = threading.Thread(target=process_async)
    thread.start()
    
    return jsonify({'message_id': message.id, 'status': 'processing'})

@app.route('/api/get_feed/<user_id>')
def get_feed(user_id):
    # Process asynchronously
    def get_feed_async():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        result = loop.run_until_complete(fanout_manager.fanout_on_read(user_id))
        loop.close()
        return result
    
    # Update last activity and active users metric
    user = fanout_manager.users.get(user_id)
    if user:
        user.last_activity = time.time()
        fanout_manager.update_active_users_metric()
    
    result = get_feed_async()
    return jsonify(result)

@app.route('/api/metrics')
def get_metrics():
    return generate_latest(), 200, {'Content-Type': 'text/plain; charset=utf-8'}

@app.route('/api/stats')
def get_stats():
    return jsonify({
        'total_users': len(fanout_manager.users),
        'queue_size': len(fanout_manager.message_queue),
        'memory_usage': psutil.virtual_memory().percent,
        'cpu_usage': psutil.cpu_percent(),
        'users_by_tier': {
            tier: len([u for u in fanout_manager.users.values() if u.tier == tier])
            for tier in ['celebrity', 'regular', 'inactive']
        }
    })

@socketio.on('connect')
def handle_connect():
    # Mark a random user as active for demo purposes
    if fanout_manager.users:
        user = random.choice(list(fanout_manager.users.values()))
        user.last_activity = time.time()
        fanout_manager.update_active_users_metric()
    emit('connected', {'status': 'Connected to Fan-Out Demo'})

if __name__ == '__main__':
    init_demo_data()
    socketio.run(app, host='0.0.0.0', port=8080, debug=True)
