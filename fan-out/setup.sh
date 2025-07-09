
#!/bin/bash

# Fan-Out Architecture Patterns Demo
# Creates a complete demonstration of fan-out strategies with real-time visualization

set -e

PROJECT_NAME="fanout-demo"
PORT=8080

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is required but not installed"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is required but not installed"
        exit 1
    fi
    
    log "All dependencies satisfied"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    mkdir -p $PROJECT_NAME/{app,static/{css,js},templates,tests,config}
    cd $PROJECT_NAME
    
    log "Project structure created"
}

# Create Python application files
create_application() {
    log "Creating application files..."
    
    # Requirements file
    cat > requirements.txt << 'EOF'
flask==3.0.0
redis==5.0.1
websockets==12.0
asyncio==3.4.3
numpy==1.24.3
aiohttp==3.9.1
flask-socketio==5.3.6
eventlet==0.33.3
prometheus-client==0.19.0
psutil==5.9.6
gunicorn==21.2.0
EOF

    # Main application
    cat > app/main.py << 'EOF'
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

app = Flask(__name__)
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
            
        if self.should_use_write_fanout(user):
            message.fanout_strategy = 'write'
            result = await self.fanout_on_write(message)
        else:
            message.fanout_strategy = 'read'
            result = {'strategy': 'fanout_on_read', 'deferred': True}
        
        metrics['fanout_operations'].labels(strategy=message.fanout_strategy).inc()
        
        # Emit real-time update
        socketio.emit('fanout_update', {
            'message': asdict(message),
            'result': result,
            'user_tier': user.tier,
            'timestamp': datetime.now().isoformat()
        })
        
        return result

fanout_manager = FanOutManager()

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
    emit('connected', {'status': 'Connected to Fan-Out Demo'})

if __name__ == '__main__':
    init_demo_data()
    socketio.run(app, host='0.0.0.0', port=8080, debug=True)
EOF

    # HTML Template
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fan-Out Architecture Demo</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.7.2/socket.io.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <header class="header">
            <div class="header-content">
                <h1 class="title">Fan-Out Architecture Patterns</h1>
                <p class="subtitle">Interactive demonstration of distributed message broadcasting strategies</p>
            </div>
        </header>

        <div class="main-content">
            <div class="sidebar">
                <div class="card">
                    <h3>System Overview</h3>
                    <div class="stats" id="systemStats">
                        <div class="stat-item">
                            <span class="stat-label">Total Users:</span>
                            <span class="stat-value" id="totalUsers">0</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Queue Size:</span>
                            <span class="stat-value" id="queueSize">0</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">CPU Usage:</span>
                            <span class="stat-value" id="cpuUsage">0%</span>
                        </div>
                    </div>
                </div>

                <div class="card">
                    <h3>User Tiers</h3>
                    <div class="user-tiers" id="userTiers">
                        <div class="tier-item celebrity">
                            <span class="tier-label">Celebrity (10K+ followers)</span>
                            <span class="tier-count" id="celebrityCount">0</span>
                        </div>
                        <div class="tier-item regular">
                            <span class="tier-label">Regular (100-10K followers)</span>
                            <span class="tier-count" id="regularCount">0</span>
                        </div>
                        <div class="tier-item inactive">
                            <span class="tier-label">New Users (<100 followers)</span>
                            <span class="tier-count" id="inactiveCount">0</span>
                        </div>
                    </div>
                </div>
            </div>

            <div class="content">
                <div class="demo-section">
                    <div class="card">
                        <h3>Post Message</h3>
                        <div class="message-form">
                            <select id="userSelect" class="form-select">
                                <option value="">Select a user...</option>
                            </select>
                            <textarea id="messageContent" placeholder="What's happening?" class="form-textarea"></textarea>
                            <button id="postButton" class="btn btn-primary">Post Message</button>
                        </div>
                    </div>

                    <div class="card">
                        <h3>Real-time Activity</h3>
                        <div class="activity-feed" id="activityFeed">
                            <div class="activity-item placeholder">
                                <p>Post a message to see fan-out strategies in action...</p>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="metrics-section">
                    <div class="card">
                        <h3>Performance Metrics</h3>
                        <canvas id="metricsChart" width="400" height="200"></canvas>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="{{ url_for('static', filename='js/app.js') }}"></script>
</body>
</html>
EOF

    # CSS Styles (Google Cloud Skills Boost inspired)
    cat > static/css/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Google Sans', -apple-system, BlinkMacSystemFont, sans-serif;
    background: linear-gradient(135deg, #f8f9fa 0%, #e3f2fd 100%);
    color: #202124;
    min-height: 100vh;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

.header {
    background: #fff;
    border-radius: 16px;
    padding: 32px;
    margin-bottom: 24px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    border: 1px solid #e8eaed;
}

.title {
    font-size: 2.5rem;
    font-weight: 400;
    color: #1976d2;
    margin-bottom: 8px;
}

.subtitle {
    font-size: 1.1rem;
    color: #5f6368;
    font-weight: 400;
}

.main-content {
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: 24px;
}

.card {
    background: #fff;
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    border: 1px solid #e8eaed;
    margin-bottom: 24px;
}

.card h3 {
    font-size: 1.25rem;
    font-weight: 500;
    color: #1976d2;
    margin-bottom: 16px;
    padding-bottom: 8px;
    border-bottom: 2px solid #e3f2fd;
}

.stats {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.stat-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
}

.stat-label {
    color: #5f6368;
    font-weight: 400;
}

.stat-value {
    font-weight: 500;
    color: #1976d2;
    font-size: 1.1rem;
}

.user-tiers {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.tier-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px;
    border-radius: 8px;
    border-left: 4px solid;
}

.tier-item.celebrity {
    background: #fff3e0;
    border-left-color: #ff9800;
}

.tier-item.regular {
    background: #e8f5e8;
    border-left-color: #4caf50;
}

.tier-item.inactive {
    background: #f3e5f5;
    border-left-color: #9c27b0;
}

.tier-label {
    font-size: 0.9rem;
    color: #5f6368;
}

.tier-count {
    font-weight: 600;
    font-size: 1.1rem;
}

.demo-section {
    margin-bottom: 24px;
}

.message-form {
    display: flex;
    flex-direction: column;
    gap: 16px;
}

.form-select, .form-textarea {
    padding: 12px 16px;
    border: 2px solid #e8eaed;
    border-radius: 8px;
    font-size: 1rem;
    transition: border-color 0.2s ease;
}

.form-select:focus, .form-textarea:focus {
    outline: none;
    border-color: #1976d2;
}

.form-textarea {
    min-height: 80px;
    resize: vertical;
    font-family: inherit;
}

.btn {
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
}

.btn-primary {
    background: #1976d2;
    color: white;
}

.btn-primary:hover {
    background: #1565c0;
    transform: translateY(-1px);
    box-shadow: 0 6px 16px rgba(25,118,210,0.3);
}

.activity-feed {
    max-height: 400px;
    overflow-y: auto;
    border: 1px solid #e8eaed;
    border-radius: 8px;
    padding: 16px;
}

.activity-item {
    padding: 16px;
    border-radius: 8px;
    margin-bottom: 12px;
    border-left: 4px solid #1976d2;
    background: #f8f9ff;
    animation: slideIn 0.3s ease-out;
}

.activity-item.placeholder {
    color: #5f6368;
    text-align: center;
    border-left-color: #e8eaed;
    background: #f8f9fa;
}

.activity-strategy {
    font-weight: 600;
    color: #1976d2;
    text-transform: uppercase;
    font-size: 0.8rem;
    letter-spacing: 0.5px;
}

.activity-content {
    margin: 8px 0;
    font-size: 1rem;
}

.activity-meta {
    font-size: 0.85rem;
    color: #5f6368;
    display: flex;
    gap: 16px;
}

.metrics-section canvas {
    width: 100% !important;
    height: 300px !important;
}

@keyframes slideIn {
    from {
        opacity: 0;
        transform: translateY(-10px);
    }
    to {
        opacity: 1;
        transform: translateY(0);
    }
}

@media (max-width: 768px) {
    .main-content {
        grid-template-columns: 1fr;
    }
    
    .title {
        font-size: 2rem;
    }
}
EOF

    # JavaScript Application
    cat > static/js/app.js << 'EOF'
class FanOutDemo {
    constructor() {
        this.socket = io();
        this.metricsChart = null;
        this.init();
    }

    init() {
        this.setupSocketListeners();
        this.setupEventListeners();
        this.loadUsers();
        this.startMetricsUpdates();
        this.initChart();
    }

    setupSocketListeners() {
        this.socket.on('connect', () => {
            console.log('Connected to server');
        });

        this.socket.on('fanout_update', (data) => {
            this.addActivityItem(data);
        });
    }

    setupEventListeners() {
        document.getElementById('postButton').addEventListener('click', () => {
            this.postMessage();
        });

        document.getElementById('messageContent').addEventListener('keypress', (e) => {
            if (e.key === 'Enter' && e.ctrlKey) {
                this.postMessage();
            }
        });
    }

    async loadUsers() {
        try {
            const response = await fetch('/api/users');
            const users = await response.json();
            this.populateUserSelect(users);
        } catch (error) {
            console.error('Error loading users:', error);
        }
    }

    populateUserSelect(users) {
        const select = document.getElementById('userSelect');
        select.innerHTML = '<option value="">Select a user...</option>';
        
        users.forEach(user => {
            const option = document.createElement('option');
            option.value = user.id;
            option.textContent = `${user.id} (${user.follower_count} followers - ${user.tier})`;
            select.appendChild(option);
        });
    }

    async postMessage() {
        const userId = document.getElementById('userSelect').value;
        const content = document.getElementById('messageContent').value.trim();

        if (!userId || !content) {
            alert('Please select a user and enter a message');
            return;
        }

        try {
            const response = await fetch('/api/post_message', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    user_id: userId,
                    content: content
                })
            });

            if (response.ok) {
                document.getElementById('messageContent').value = '';
                this.showNotification('Message posted successfully!', 'success');
            }
        } catch (error) {
            console.error('Error posting message:', error);
            this.showNotification('Error posting message', 'error');
        }
    }

    addActivityItem(data) {
        const feed = document.getElementById('activityFeed');
        const placeholder = feed.querySelector('.placeholder');
        if (placeholder) {
            placeholder.remove();
        }

        const item = document.createElement('div');
        item.className = 'activity-item';
        
        const strategy = data.message.fanout_strategy === 'write' ? 'Fan-Out on Write' : 'Fan-Out on Read';
        const strategyClass = data.message.fanout_strategy === 'write' ? 'write' : 'read';
        
        item.innerHTML = `
            <div class="activity-strategy ${strategyClass}">${strategy}</div>
            <div class="activity-content">${data.message.content}</div>
            <div class="activity-meta">
                <span>User: ${data.message.user_id}</span>
                <span>Tier: ${data.user_tier}</span>
                <span>Time: ${new Date(data.timestamp).toLocaleTimeString()}</span>
                ${data.result.processing_time ? `<span>Processed in: ${(data.result.processing_time * 1000).toFixed(2)}ms</span>` : ''}
            </div>
        `;

        feed.insertBefore(item, feed.firstChild);

        // Keep only last 10 items
        const items = feed.querySelectorAll('.activity-item');
        if (items.length > 10) {
            items[items.length - 1].remove();
        }
    }

    async startMetricsUpdates() {
        setInterval(async () => {
            await this.updateStats();
        }, 2000);
        
        // Initial update
        await this.updateStats();
    }

    async updateStats() {
        try {
            const response = await fetch('/api/stats');
            const stats = await response.json();
            
            document.getElementById('totalUsers').textContent = stats.total_users;
            document.getElementById('queueSize').textContent = stats.queue_size;
            document.getElementById('cpuUsage').textContent = `${stats.cpu_usage.toFixed(1)}%`;
            
            document.getElementById('celebrityCount').textContent = stats.users_by_tier.celebrity || 0;
            document.getElementById('regularCount').textContent = stats.users_by_tier.regular || 0;
            document.getElementById('inactiveCount').textContent = stats.users_by_tier.inactive || 0;
            
        } catch (error) {
            console.error('Error updating stats:', error);
        }
    }

    initChart() {
        const ctx = document.getElementById('metricsChart').getContext('2d');
        this.metricsChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Fan-Out Operations/sec',
                    data: [],
                    borderColor: '#1976d2',
                    backgroundColor: 'rgba(25, 118, 210, 0.1)',
                    tension: 0.4
                }, {
                    label: 'Average Processing Time (ms)',
                    data: [],
                    borderColor: '#ff9800',
                    backgroundColor: 'rgba(255, 152, 0, 0.1)',
                    tension: 0.4,
                    yAxisID: 'y1'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        grid: {
                            drawOnChartArea: false,
                        },
                    }
                },
                plugins: {
                    legend: {
                        position: 'top',
                    }
                }
            }
        });

        // Simulate some metric updates
        setInterval(() => {
            this.updateChart();
        }, 3000);
    }

    updateChart() {
        const now = new Date().toLocaleTimeString();
        const operations = Math.floor(Math.random() * 100) + 50;
        const processingTime = Math.random() * 50 + 10;

        this.metricsChart.data.labels.push(now);
        this.metricsChart.data.datasets[0].data.push(operations);
        this.metricsChart.data.datasets[1].data.push(processingTime);

        // Keep only last 10 data points
        if (this.metricsChart.data.labels.length > 10) {
            this.metricsChart.data.labels.shift();
            this.metricsChart.data.datasets[0].data.shift();
            this.metricsChart.data.datasets[1].data.shift();
        }

        this.metricsChart.update('none');
    }

    showNotification(message, type) {
        // Simple notification system
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 24px;
            border-radius: 8px;
            color: white;
            font-weight: 500;
            z-index: 1000;
            background: ${type === 'success' ? '#4caf50' : '#f44336'};
            animation: slideInRight 0.3s ease-out;
        `;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.remove();
        }, 3000);
    }
}

// Initialize the demo when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new FanOutDemo();
});
EOF

    # Docker Compose
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "8080:8080"
    depends_on:
      - redis
    environment:
      - FLASK_ENV=development
    volumes:
      - .:/app
    working_dir: /app

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data

volumes:
  redis_data:
EOF

    # Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "app/main.py"]
EOF

    # Tests
    cat > tests/test_fanout.py << 'EOF'
import unittest
import asyncio
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import FanOutManager, User, Message

class TestFanOutPatterns(unittest.TestCase):
    def setUp(self):
        self.manager = FanOutManager()
        self.manager.add_user('test_user', 1000)
        self.manager.add_user('celebrity_user', 50000)
    
    def test_user_tier_assignment(self):
        """Test that users are assigned correct tiers based on follower count"""
        regular_user = self.manager.users['test_user']
        celebrity_user = self.manager.users['celebrity_user']
        
        self.assertEqual(regular_user.tier, 'regular')
        self.assertEqual(celebrity_user.tier, 'celebrity')
    
    def test_fanout_strategy_selection(self):
        """Test that appropriate fanout strategy is selected for different user tiers"""
        regular_user = self.manager.users['test_user']
        celebrity_user = self.manager.users['celebrity_user']
        
        # Regular users should use write fanout
        self.assertTrue(self.manager.should_use_write_fanout(regular_user))
        
        # Celebrities should use read fanout
        self.assertFalse(self.manager.should_use_write_fanout(celebrity_user))
    
    def test_back_pressure_handling(self):
        """Test that system switches to read fanout under high load"""
        # Fill queue to trigger back pressure
        self.manager.message_queue = ['msg'] * 1500  # Exceed threshold
        
        regular_user = self.manager.users['test_user']
        
        # Should switch to read fanout under back pressure
        self.assertFalse(self.manager.should_use_write_fanout(regular_user))
    
    async def test_fanout_on_write_processing(self):
        """Test fanout on write message processing"""
        message = Message(
            id='test_msg_1',
            user_id='test_user',
            content='Test message',
            timestamp=1234567890.0,
            fanout_strategy='write'
        )
        
        result = await self.manager.fanout_on_write(message)
        
        self.assertEqual(result['strategy'], 'fanout_on_write')
        self.assertGreater(result['notifications_created'], 0)
        self.assertGreater(result['processing_time'], 0)
    
    async def test_fanout_on_read_processing(self):
        """Test fanout on read feed generation"""
        result = await self.manager.fanout_on_read('test_user')
        
        self.assertEqual(result['strategy'], 'fanout_on_read')
        self.assertIsInstance(result['feed_items'], list)
        self.assertGreater(result['processing_time'], 0)

def run_async_test(test_func):
    """Helper to run async test functions"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(test_func())
    finally:
        loop.close()

if __name__ == '__main__':
    # Run async tests
    test_case = TestFanOutPatterns()
    test_case.setUp()
    
    print("Running Fan-Out Architecture Tests...")
    
    # Run sync tests
    test_case.test_user_tier_assignment()
    print("✓ User tier assignment test passed")
    
    test_case.test_fanout_strategy_selection()
    print("✓ Fanout strategy selection test passed")
    
    test_case.test_back_pressure_handling()
    print("✓ Back pressure handling test passed")
    
    # Run async tests
    run_async_test(test_case.test_fanout_on_write_processing)
    print("✓ Fanout on write processing test passed")
    
    run_async_test(test_case.test_fanout_on_read_processing)
    print("✓ Fanout on read processing test passed")
    
    print("\nAll tests passed! ✨")
EOF

    log "Application files created successfully"
}

# Create SVG diagrams
create_svg_diagrams() {
    log "Creating SVG diagrams..."
    
    # SVG 1: Fan-Out Architecture Overview
    cat > static/fanout_architecture.svg << 'EOF'
<svg viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="#666" flood-opacity="0.3"/>
    </filter>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="500" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-size="24" font-weight="bold" fill="#1976d2">
    Fan-Out Architecture Overview
  </text>
  
  <!-- Message Producer -->
  <g transform="translate(50, 100)">
    <rect width="120" height="80" rx="10" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" filter="url(#shadow)"/>
    <text x="60" y="35" text-anchor="middle" font-size="14" font-weight="bold" fill="#1976d2">Message</text>
    <text x="60" y="55" text-anchor="middle" font-size="14" font-weight="bold" fill="#1976d2">Producer</text>
  </g>
  
  <!-- Fan-Out Manager -->
  <g transform="translate(350, 80)">
    <rect width="100" height="120" rx="15" fill="#fff3e0" stroke="#ff9800" stroke-width="3" filter="url(#shadow)"/>
    <text x="50" y="30" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Fan-Out</text>
    <text x="50" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Manager</text>
    <circle cx="50" cy="80" r="15" fill="#ff9800" opacity="0.3"/>
    <text x="50" y="85" text-anchor="middle" font-size="10" fill="#ff9800">Logic</text>
  </g>
  
  <!-- Strategy Decision Diamond -->
  <g transform="translate(375, 250)">
    <polygon points="50,0 100,25 50,50 0,25" fill="#f3e5f5" stroke="#9c27b0" stroke-width="2" filter="url(#shadow)"/>
    <text x="50" y="20" text-anchor="middle" font-size="10" fill="#9c27b0">Strategy</text>
    <text x="50" y="35" text-anchor="middle" font-size="10" fill="#9c27b0">Decision</text>
  </g>
  
  <!-- Write Path -->
  <g transform="translate(200, 350)">
    <rect width="140" height="60" rx="8" fill="#e8f5e8" stroke="#4caf50" stroke-width="2" filter="url(#shadow)"/>
    <text x="70" y="25" text-anchor="middle" font-size="12" font-weight="bold" fill="#4caf50">Fan-Out on Write</text>
    <text x="70" y="45" text-anchor="middle" font-size="10" fill="#4caf50">Pre-compute all feeds</text>
  </g>
  
  <!-- Read Path -->
  <g transform="translate(460, 350)">
    <rect width="140" height="60" rx="8" fill="#fff3e0" stroke="#ff9800" stroke-width="2" filter="url(#shadow)"/>
    <text x="70" y="25" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Fan-Out on Read</text>
    <text x="70" y="45" text-anchor="middle" font-size="10" fill="#ff9800">Compute on demand</text>
  </g>
  
  <!-- Consumers -->
  <g transform="translate(650, 120)">
    <circle cx="30" cy="30" r="25" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" filter="url(#shadow)"/>
    <text x="30" y="25" text-anchor="middle" font-size="10" fill="#1976d2">User</text>
    <text x="30" y="38" text-anchor="middle" font-size="10" fill="#1976d2">Feed</text>
  </g>
  
  <g transform="translate(650, 200)">
    <circle cx="30" cy="30" r="25" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" filter="url(#shadow)"/>
    <text x="30" y="25" text-anchor="middle" font-size="10" fill="#1976d2">Push</text>
    <text x="30" y="38" text-anchor="middle" font-size="10" fill="#1976d2">Notify</text>
  </g>
  
  <g transform="translate(650, 280)">
    <circle cx="30" cy="30" r="25" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" filter="url(#shadow)"/>
    <text x="30" y="25" text-anchor="middle" font-size="10" fill="#1976d2">Email</text>
    <text x="30" y="38" text-anchor="middle" font-size="10" fill="#1976d2">Service</text>
  </g>
  
  <!-- Arrows -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#666"/>
    </marker>
  </defs>
  
  <!-- Producer to Manager -->
  <line x1="170" y1="140" x2="350" y2="140" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  
  <!-- Manager to Decision -->
  <line x1="400" y1="200" x2="400" y2="250" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  
  <!-- Decision to Write -->
  <line x1="375" y1="275" x2="320" y2="350" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <text x="330" y="320" font-size="10" fill="#666">High followers</text>
  
  <!-- Decision to Read -->
  <line x1="425" y1="275" x2="480" y2="350" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <text x="460" y="320" font-size="10" fill="#666">Celebrity users</text>
  
  <!-- To Consumers -->
  <line x1="450" y1="140" x2="650" y2="150" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <line x1="450" y1="150" x2="650" y2="230" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <line x1="450" y1="160" x2="650" y2="310" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
</svg>
EOF

    # SVG 2: Strategy Comparison
    cat > static/strategy_comparison.svg << 'EOF'
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="#666" flood-opacity="0.3"/>
    </filter>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="600" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-size="24" font-weight="bold" fill="#1976d2">
    Fan-Out Strategy Comparison
  </text>
  
  <!-- Fan-Out on Write Section -->
  <g transform="translate(50, 80)">
    <rect width="300" height="200" rx="15" fill="#e8f5e8" stroke="#4caf50" stroke-width="3" filter="url(#shadow)"/>
    <text x="150" y="30" text-anchor="middle" font-size="18" font-weight="bold" fill="#4caf50">Fan-Out on Write</text>
    
    <!-- Write time -->
    <rect x="20" y="50" width="80" height="30" rx="5" fill="#4caf50" opacity="0.7"/>
    <text x="60" y="70" text-anchor="middle" font-size="12" fill="white">Write Time</text>
    
    <!-- High cost bar -->
    <rect x="20" y="90" width="200" height="15" rx="3" fill="#f44336"/>
    <text x="230" y="102" font-size="12" fill="#f44336">High Cost</text>
    
    <!-- Read time -->
    <rect x="20" y="120" width="80" height="30" rx="5" fill="#4caf50" opacity="0.7"/>
    <text x="60" y="140" text-anchor="middle" font-size="12" fill="white">Read Time</text>
    
    <!-- Low latency bar -->
    <rect x="20" y="160" width="60" height="15" rx="3" fill="#4caf50"/>
    <text x="90" y="172" font-size="12" fill="#4caf50">Low Latency</text>
  </g>
  
  <!-- Fan-Out on Read Section -->
  <g transform="translate(450, 80)">
    <rect width="300" height="200" rx="15" fill="#fff3e0" stroke="#ff9800" stroke-width="3" filter="url(#shadow)"/>
    <text x="150" y="30" text-anchor="middle" font-size="18" font-weight="bold" fill="#ff9800">Fan-Out on Read</text>
    
    <!-- Write time -->
    <rect x="20" y="50" width="80" height="30" rx="5" fill="#ff9800" opacity="0.7"/>
    <text x="60" y="70" text-anchor="middle" font-size="12" fill="white">Write Time</text>
    
    <!-- Low cost bar -->
    <rect x="20" y="90" width="60" height="15" rx="3" fill="#4caf50"/>
    <text x="90" y="102" font-size="12" fill="#4caf50">Low Cost</text>
    
    <!-- Read time -->
    <rect x="20" y="120" width="80" height="30" rx="5" fill="#ff9800" opacity="0.7"/>
    <text x="60" y="140" text-anchor="middle" font-size="12" fill="white">Read Time</text>
    
    <!-- High latency bar -->
    <rect x="20" y="160" width="180" height="15" rx="3" fill="#f44336"/>
    <text x="210" y="172" font-size="12" fill="#f44336">High Latency</text>
  </g>
  
  <!-- User Types Section -->
  <text x="400" y="340" text-anchor="middle" font-size="18" font-weight="bold" fill="#1976d2">
    Recommended Strategy by User Type
  </text>
  
  <!-- Regular Users -->
  <g transform="translate(100, 370)">
    <circle cx="60" cy="60" r="50" fill="#e3f2fd" stroke="#1976d2" stroke-width="3" filter="url(#shadow)"/>
    <text x="60" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="#1976d2">Regular</text>
    <text x="60" y="65" text-anchor="middle" font-size="12" font-weight="bold" fill="#1976d2">Users</text>
    <text x="60" y="80" text-anchor="middle" font-size="10" fill="#1976d2">&lt; 10K followers</text>
    
    <rect x="10" y="140" width="100" height="25" rx="5" fill="#4caf50"/>
    <text x="60" y="157" text-anchor="middle" font-size="12" fill="white">Write Strategy</text>
  </g>
  
  <!-- Celebrity Users -->
  <g transform="translate(300, 370)">
    <circle cx="60" cy="60" r="50" fill="#fff3e0" stroke="#ff9800" stroke-width="3" filter="url(#shadow)"/>
    <text x="60" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Celebrity</text>
    <text x="60" y="65" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Users</text>
    <text x="60" y="80" text-anchor="middle" font-size="10" fill="#ff9800">&gt; 10K followers</text>
    
    <rect x="10" y="140" width="100" height="25" rx="5" fill="#ff9800"/>
    <text x="60" y="157" text-anchor="middle" font-size="12" fill="white">Read Strategy</text>
  </g>
  
  <!-- Hybrid Approach -->
  <g transform="translate(500, 370)">
    <circle cx="60" cy="60" r="50" fill="#f3e5f5" stroke="#9c27b0" stroke-width="3" filter="url(#shadow)"/>
    <text x="60" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="#9c27b0">Hybrid</text>
    <text x="60" y="65" text-anchor="middle" font-size="12" font-weight="bold" fill="#9c27b0">System</text>
    <text x="60" y="80" text-anchor="middle" font-size="10" fill="#9c27b0">Adaptive</text>
    
    <rect x="10" y="140" width="100" height="25" rx="5" fill="#9c27b0"/>
    <text x="60" y="157" text-anchor="middle" font-size="12" fill="white">Best of Both</text>
  </g>
  
  <!-- Performance Metrics -->
  <text x="400" y="540" text-anchor="middle" font-size="16" font-weight="bold" fill="#666">
    Choose strategy based on user follower count, system load, and latency requirements
  </text>
</svg>
EOF

    # SVG 3: Back-Pressure Handling
    cat > static/backpressure_handling.svg << 'EOF'
<svg viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="#666" flood-opacity="0.3"/>
    </filter>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#666"/>
    </marker>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="500" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-size="24" font-weight="bold" fill="#1976d2">
    Back-Pressure Handling Mechanisms
  </text>
  
  <!-- Message Queue -->
  <g transform="translate(50, 100)">
    <rect width="120" height="300" rx="10" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" filter="url(#shadow)"/>
    <text x="60" y="25" text-anchor="middle" font-size="14" font-weight="bold" fill="#1976d2">Message Queue</text>
    
    <!-- Queue items -->
    <rect x="20" y="50" width="80" height="20" rx="3" fill="#1976d2" opacity="0.8"/>
    <rect x="20" y="80" width="80" height="20" rx="3" fill="#1976d2" opacity="0.7"/>
    <rect x="20" y="110" width="80" height="20" rx="3" fill="#1976d2" opacity="0.6"/>
    <rect x="20" y="140" width="80" height="20" rx="3" fill="#f44336" opacity="0.8"/>
    <rect x="20" y="170" width="80" height="20" rx="3" fill="#f44336" opacity="0.7"/>
    
    <text x="60" y="280" text-anchor="middle" font-size="12" fill="#f44336">Queue Full!</text>
  </g>
  
  <!-- Load Monitor -->
  <g transform="translate(250, 120)">
    <circle cx="60" cy="60" r="50" fill="#fff3e0" stroke="#ff9800" stroke-width="3" filter="url(#shadow)"/>
    <text x="60" y="45" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Load</text>
    <text x="60" y="60" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Monitor</text>
    <text x="60" y="85" text-anchor="middle" font-size="16" font-weight="bold" fill="#f44336">95%</text>
  </g>
  
  <!-- Circuit Breaker -->
  <g transform="translate(400, 100)">
    <rect width="100" height="120" rx="10" fill="#ffebee" stroke="#f44336" stroke-width="2" filter="url(#shadow)"/>
    <text x="50" y="25" text-anchor="middle" font-size="12" font-weight="bold" fill="#f44336">Circuit</text>
    <text x="50" y="40" text-anchor="middle" font-size="12" font-weight="bold" fill="#f44336">Breaker</text>
    
    <!-- Switch in OPEN position -->
    <circle cx="50" cy="70" r="15" fill="#f44336"/>
    <text x="50" y="75" text-anchor="middle" font-size="10" fill="white">OPEN</text>
    
    <text x="50" y="110" text-anchor="middle" font-size="10" fill="#f44336">Rejecting</text>
    <text x="50" y="125" text-anchor="middle" font-size="10" fill="#f44336">Requests</text>
  </g>
  
  <!-- Degraded Service -->
  <g transform="translate(580, 120)">
    <rect width="120" height="80" rx="10" fill="#fff3e0" stroke="#ff9800" stroke-width="2" filter="url(#shadow)"/>
    <text x="60" y="25" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Degraded</text>
    <text x="60" y="40" text-anchor="middle" font-size="12" font-weight="bold" fill="#ff9800">Service</text>
    <text x="60" y="65" text-anchor="middle" font-size="10" fill="#ff9800">Essential only</text>
  </g>
  
  <!-- Priority Queues -->
  <g transform="translate(200, 280)">
    <text x="200" y="20" text-anchor="middle" font-size="16" font-weight="bold" fill="#1976d2">
      Priority-Based Queue Management
    </text>
    
    <!-- High Priority -->
    <rect x="50" y="40" width="120" height="40" rx="5" fill="#4caf50" filter="url(#shadow)"/>
    <text x="110" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="white">High Priority</text>
    <text x="110" y="67" text-anchor="middle" font-size="10" fill="white">Critical notifications</text>
    
    <!-- Medium Priority -->
    <rect x="200" y="40" width="120" height="40" rx="5" fill="#ff9800" filter="url(#shadow)"/>
    <text x="260" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="white">Medium Priority</text>
    <text x="260" y="67" text-anchor="middle" font-size="10" fill="white">Social updates</text>
    
    <!-- Low Priority -->
    <rect x="350" y="40" width="120" height="40" rx="5" fill="#9e9e9e" filter="url(#shadow)"/>
    <text x="410" y="50" text-anchor="middle" font-size="12" font-weight="bold" fill="white">Low Priority</text>
    <text x="410" y="67" text-anchor="middle" font-size="10" fill="white">Analytics events</text>
  </g>
  
  <!-- Flow arrows -->
  <line x1="170" y1="180" x2="250" y2="180" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <line x1="320" y1="180" x2="400" y2="180" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  <line x1="500" y1="160" x2="580" y2="160" stroke="#666" stroke-width="2" marker-end="url(#arrowhead)"/>
  
  <!-- Back-pressure indication -->
  <path d="M 380 250 Q 300 230 220 250" stroke="#f44336" stroke-width="3" fill="none" stroke-dasharray="5,5"/>
  <text x="300" y="235" text-anchor="middle" font-size="12" fill="#f44336">Back-pressure signal</text>
</svg>
EOF

    log "SVG diagrams created successfully"
}

# Build and run the demo
build_and_run() {
    log "Building and running the demo..."
    
    # Build and start with Docker Compose
    docker-compose down -v 2>/dev/null || true
    docker-compose build
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for services to start..."
    sleep 10
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        log "Services started successfully!"
        log "🌐 Demo available at: http://localhost:$PORT"
        log "📊 Access the interactive fan-out demo in your browser"
    else
        error "Failed to start services"
        docker-compose logs
        exit 1
    fi
}

# Run tests
run_tests() {
    log "Running tests..."
    
    # Run tests inside the container
    docker-compose exec -T app python tests/test_fanout.py
    
    if [ $? -eq 0 ]; then
        log "All tests passed! ✨"
    else
        warn "Some tests failed"
    fi
}

# Display demo information
show_demo_info() {
    log "Demo is ready! 🚀"
    echo ""
    echo "📊 Access Points:"
    echo "   Main Demo: http://localhost:$PORT"
    echo "   Fan-Out Architecture: http://localhost:$PORT/static/fanout_architecture.svg"
    echo "   Strategy Comparison: http://localhost:$PORT/static/strategy_comparison.svg"
    echo "   Back-Pressure Handling: http://localhost:$PORT/static/backpressure_handling.svg"
    echo ""
    echo "🧪 How to Test:"
    echo "   1. Select different user types (celebrity vs regular)"
    echo "   2. Post messages and observe strategy selection"
    echo "   3. Watch real-time metrics and activity feed"
    echo "   4. Monitor back-pressure handling under load"
    echo ""
    echo "🔍 Key Features:"
    echo "   ✓ Real-time fan-out strategy selection"
    echo "   ✓ User tier management (celebrity detection)"
    echo "   ✓ Back-pressure and graceful degradation"
    echo "   ✓ Performance metrics and visualization"
    echo "   ✓ Interactive web interface"
    echo ""
    echo "📋 To stop the demo: ./cleanup.sh"
}

# Main execution
main() {
    log "Starting Fan-Out Architecture Demo Setup..."
    
    check_dependencies
    create_project_structure
    create_application
    create_svg_diagrams
    build_and_run
    run_tests
    show_demo_info
}

# Execute main function
main "$@"