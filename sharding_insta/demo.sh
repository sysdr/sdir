#!/bin/bash

# Instagram Sharding Demo Setup Script
# Creates a comprehensive sharding demonstration with web interface

set -e

PROJECT_NAME="instagram-sharding-demo"
echo "🚀 Setting up $PROJECT_NAME..."

# Create project structure
mkdir -p $PROJECT_NAME/{src,templates,static/{css,js},tests,data}
cd $PROJECT_NAME

echo "📁 Creating project structure..."

# Create requirements.txt with latest compatible versions
cat > requirements.txt << 'EOF'
Flask==3.0.0
Flask-CORS==4.0.0
redis==5.0.1
psycopg2-binary==2.9.9
SQLAlchemy==2.0.23
Faker==20.1.0
requests==2.31.0
pytest==7.4.3
gunicorn==21.2.0
hashlib==1.0.0
mmh3==4.0.1
numpy==1.24.4
plotly==5.17.0
dash==2.14.2
concurrent-futures==3.1.1
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000 8050

CMD ["python", "src/app.py"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "5000:5000"
      - "8050:8050"
    environment:
      - REDIS_URL=redis://redis:6379
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/instagram_demo
    depends_on:
      - redis
      - postgres
    volumes:
      - ./data:/app/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=instagram_demo
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  redis_data:
  postgres_data:
EOF

# Create main application
cat > src/app.py << 'EOF'
"""
Instagram Sharding Demo - Main Application
Demonstrates user-ID based sharding with real-time visualization
"""

import os
import hashlib
import mmh3
import random
import time
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Optional
from concurrent.futures import ThreadPoolExecutor
import threading

from flask import Flask, render_template, request, jsonify, redirect, url_for
from flask_cors import CORS
import redis
import psycopg2
from faker import Faker
import json

# Initialize Flask app
app = Flask(__name__)
CORS(app)
fake = Faker()

# Configuration
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379')
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/instagram_demo')

# Initialize Redis
redis_client = redis.from_url(REDIS_URL, decode_responses=True)

@dataclass
class User:
    user_id: int
    username: str
    email: str
    shard_id: int
    created_at: datetime
    follower_count: int = 0
    photo_count: int = 0

@dataclass
class Photo:
    photo_id: int
    user_id: int
    caption: str
    shard_id: int
    likes: int = 0
    created_at: datetime = None

class ShardManager:
    """Manages Instagram-style sharding logic"""
    
    def __init__(self, num_shards: int = 8):
        self.num_shards = num_shards
        self.shard_stats = {i: {'users': 0, 'photos': 0, 'queries': 0, 'load': 0} for i in range(num_shards)}
        self.hot_threshold = 1000  # Queries per minute threshold for hot shard
    
    def get_shard_for_user(self, user_id: int) -> int:
        """Simple modulo sharding - Instagram's core approach"""
        return user_id % self.num_shards
    
    def get_shard_with_consistent_hash(self, user_id: int) -> int:
        """Alternative: Consistent hashing approach"""
        hash_value = mmh3.hash(str(user_id))
        return abs(hash_value) % self.num_shards
    
    def generate_user_id(self) -> int:
        """Generate Instagram-style 64-bit ID with embedded timestamp"""
        timestamp = int(time.time() * 1000)  # 41 bits
        shard_id = random.randint(0, 1023)  # 10 bits  
        sequence = random.randint(0, 4095)  # 12 bits
        
        # Combine into 64-bit ID (simplified version)
        user_id = (timestamp << 22) | (shard_id << 12) | sequence
        return user_id
    
    def update_shard_stats(self, shard_id: int, operation: str):
        """Track shard usage for hot shard detection"""
        if operation == 'user_added':
            self.shard_stats[shard_id]['users'] += 1
        elif operation == 'photo_added':
            self.shard_stats[shard_id]['photos'] += 1
        elif operation == 'query':
            self.shard_stats[shard_id]['queries'] += 1
        
        # Calculate load score
        stats = self.shard_stats[shard_id]
        self.shard_stats[shard_id]['load'] = stats['users'] + stats['photos'] + (stats['queries'] / 10)
    
    def get_hot_shards(self) -> List[int]:
        """Identify hot shards exceeding threshold"""
        return [shard_id for shard_id, stats in self.shard_stats.items() 
                if stats['load'] > self.hot_threshold]
    
    def get_stats(self) -> Dict:
        """Get comprehensive shard statistics"""
        total_users = sum(stats['users'] for stats in self.shard_stats.values())
        total_photos = sum(stats['photos'] for stats in self.shard_stats.values())
        hot_shards = self.get_hot_shards()
        
        return {
            'shard_stats': self.shard_stats,
            'total_users': total_users,
            'total_photos': total_photos,
            'hot_shards': hot_shards,
            'num_shards': self.num_shards
        }

# Initialize shard manager
shard_manager = ShardManager(num_shards=8)

class InMemoryStorage:
    """Simulated database storage for demo purposes"""
    
    def __init__(self):
        self.users = {}  # user_id -> User
        self.photos = {}  # photo_id -> Photo
        self.user_photos = {}  # user_id -> [photo_ids]
        self.shard_users = {i: [] for i in range(8)}  # shard_id -> [user_ids]
        self.lock = threading.Lock()
    
    def add_user(self, user: User):
        with self.lock:
            self.users[user.user_id] = user
            self.shard_users[user.shard_id].append(user.user_id)
            shard_manager.update_shard_stats(user.shard_id, 'user_added')
    
    def add_photo(self, photo: Photo):
        with self.lock:
            self.photos[photo.photo_id] = photo
            if photo.user_id not in self.user_photos:
                self.user_photos[photo.user_id] = []
            self.user_photos[photo.user_id].append(photo.photo_id)
            shard_manager.update_shard_stats(photo.shard_id, 'photo_added')
    
    def get_user(self, user_id: int) -> Optional[User]:
        shard_id = shard_manager.get_shard_for_user(user_id)
        shard_manager.update_shard_stats(shard_id, 'query')
        return self.users.get(user_id)
    
    def get_user_photos(self, user_id: int) -> List[Photo]:
        shard_id = shard_manager.get_shard_for_user(user_id)
        shard_manager.update_shard_stats(shard_id, 'query')
        photo_ids = self.user_photos.get(user_id, [])
        return [self.photos[pid] for pid in photo_ids if pid in self.photos]
    
    def get_shard_users(self, shard_id: int) -> List[User]:
        user_ids = self.shard_users.get(shard_id, [])
        return [self.users[uid] for uid in user_ids if uid in self.users]

# Initialize storage
storage = InMemoryStorage()

def generate_sample_data():
    """Generate sample users and photos for demonstration"""
    print("🎭 Generating sample data...")
    
    # Generate users
    for i in range(100):
        user_id = shard_manager.generate_user_id()
        shard_id = shard_manager.get_shard_for_user(user_id)
        
        user = User(
            user_id=user_id,
            username=fake.user_name(),
            email=fake.email(),
            shard_id=shard_id,
            created_at=fake.date_time_between(start_date='-2y', end_date='now'),
            follower_count=random.randint(10, 10000)
        )
        storage.add_user(user)
    
    # Generate photos
    photo_id = 1
    for user_id, user in storage.users.items():
        num_photos = random.randint(1, 20)
        for _ in range(num_photos):
            photo = Photo(
                photo_id=photo_id,
                user_id=user_id,
                caption=fake.sentence(),
                shard_id=user.shard_id,
                likes=random.randint(0, 1000),
                created_at=fake.date_time_between(start_date=user.created_at, end_date='now')
            )
            storage.add_photo(photo)
            photo_id += 1
        
        # Update user photo count
        user.photo_count = num_photos

@app.route('/')
def index():
    """Main dashboard showing sharding overview"""
    return render_template('index.html')

@app.route('/api/stats')
def get_stats():
    """Get current sharding statistics"""
    return jsonify(shard_manager.get_stats())

@app.route('/api/user/<int:user_id>')
def get_user_data(user_id):
    """Get user data and demonstrate shard routing"""
    user = storage.get_user(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404
    
    photos = storage.get_user_photos(user_id)
    
    return jsonify({
        'user': asdict(user),
        'photos': [asdict(photo) for photo in photos],
        'shard_info': {
            'shard_id': user.shard_id,
            'total_shards': shard_manager.num_shards,
            'routing_method': 'user_id % num_shards'
        }
    })

@app.route('/api/shard/<int:shard_id>')
def get_shard_data(shard_id):
    """Get all data for a specific shard"""
    if shard_id >= shard_manager.num_shards:
        return jsonify({'error': 'Invalid shard ID'}), 400
    
    users = storage.get_shard_users(shard_id)
    stats = shard_manager.shard_stats[shard_id]
    
    return jsonify({
        'shard_id': shard_id,
        'users': [asdict(user) for user in users],
        'stats': stats,
        'is_hot': shard_id in shard_manager.get_hot_shards()
    })

@app.route('/api/add_user', methods=['POST'])
def add_user():
    """Add new user and demonstrate sharding in action"""
    data = request.json
    
    user_id = shard_manager.generate_user_id()
    shard_id = shard_manager.get_shard_for_user(user_id)
    
    user = User(
        user_id=user_id,
        username=data.get('username', fake.user_name()),
        email=data.get('email', fake.email()),
        shard_id=shard_id,
        created_at=datetime.now()
    )
    
    storage.add_user(user)
    
    return jsonify({
        'user': asdict(user),
        'routing_info': {
            'calculation': f'{user_id} % {shard_manager.num_shards} = {shard_id}',
            'shard_id': shard_id
        }
    })

@app.route('/api/simulate_load', methods=['POST'])
def simulate_load():
    """Simulate load to create hot shards"""
    data = request.json
    target_shard = data.get('shard_id', 0)
    load_intensity = data.get('intensity', 100)
    
    # Simulate heavy queries on target shard
    for _ in range(load_intensity):
        shard_manager.update_shard_stats(target_shard, 'query')
    
    return jsonify({
        'message': f'Simulated {load_intensity} queries on shard {target_shard}',
        'new_stats': shard_manager.shard_stats[target_shard]
    })

if __name__ == '__main__':
    # Generate sample data on startup
    generate_sample_data()
    print("🌟 Instagram Sharding Demo ready!")
    print("📊 Dashboard: http://localhost:5000")
    print("🔧 API: http://localhost:5000/api/stats")
    
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# Create HTML template
mkdir -p templates
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Instagram Sharding Demo</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/tailwindcss/2.2.19/tailwind.min.css" rel="stylesheet">
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        .shard-card {
            transition: all 0.3s ease;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .shard-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 15px rgba(0, 0, 0, 0.15);
        }
        .hot-shard {
            background: linear-gradient(135deg, #ff6b6b, #ff8e8e);
            color: white;
        }
        .normal-shard {
            background: linear-gradient(135deg, #4ecdc4, #44a08d);
            color: white;
        }
        .metric-card {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            border-radius: 12px;
        }
        .gcp-inspired {
            background: linear-gradient(135deg, #1a73e8, #34a853);
        }
    </style>
</head>
<body class="bg-gray-50">
    <!-- Header -->
    <div class="gcp-inspired text-white py-6 mb-8">
        <div class="container mx-auto px-4">
            <h1 class="text-4xl font-bold mb-2">📸 Instagram Sharding Demo</h1>
            <p class="text-lg opacity-90">Explore how Instagram scales to billions of users using smart data sharding</p>
        </div>
    </div>

    <div class="container mx-auto px-4">
        <!-- Control Panel -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
            <h2 class="text-2xl font-bold mb-4">🎛️ Interactive Controls</h2>
            <div class="grid md:grid-cols-3 gap-4">
                <button onclick="addRandomUser()" class="bg-blue-500 hover:bg-blue-600 text-white px-6 py-3 rounded-lg font-semibold transition">
                    ➕ Add Random User
                </button>
                <button onclick="simulateLoad()" class="bg-orange-500 hover:bg-orange-600 text-white px-6 py-3 rounded-lg font-semibold transition">
                    🔥 Simulate Load
                </button>
                <button onclick="refreshData()" class="bg-green-500 hover:bg-green-600 text-white px-6 py-3 rounded-lg font-semibold transition">
                    🔄 Refresh Data
                </button>
            </div>
        </div>

        <!-- Metrics Overview -->
        <div class="grid md:grid-cols-4 gap-6 mb-8" id="metricsOverview">
            <!-- Metrics will be populated by JavaScript -->
        </div>

        <!-- Sharding Visualization -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
            <h2 class="text-2xl font-bold mb-4">🗄️ Shard Distribution</h2>
            <div id="shardVisualization" class="grid md:grid-cols-4 gap-4">
                <!-- Shard cards will be populated by JavaScript -->
            </div>
        </div>

        <!-- User Data Explorer -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
            <h2 class="text-2xl font-bold mb-4">👤 User Data Explorer</h2>
            <div class="mb-4">
                <input type="number" id="userIdInput" placeholder="Enter User ID" 
                       class="border rounded-lg px-4 py-2 mr-2 w-64">
                <button onclick="searchUser()" 
                        class="bg-purple-500 hover:bg-purple-600 text-white px-6 py-2 rounded-lg font-semibold transition">
                    🔍 Search User
                </button>
            </div>
            <div id="userDataResult" class="mt-4">
                <!-- User data will be displayed here -->
            </div>
        </div>

        <!-- Load Distribution Chart -->
        <div class="bg-white rounded-lg shadow-lg p-6">
            <h2 class="text-2xl font-bold mb-4">📊 Load Distribution Analysis</h2>
            <div id="loadChart" style="height: 400px;"></div>
        </div>
    </div>

    <script>
        let currentStats = {};

        // Initialize dashboard
        document.addEventListener('DOMContentLoaded', function() {
            refreshData();
            setInterval(refreshData, 10000); // Auto-refresh every 10 seconds
        });

        async function refreshData() {
            try {
                const response = await fetch('/api/stats');
                const stats = await response.json();
                currentStats = stats;
                
                updateMetricsOverview(stats);
                updateShardVisualization(stats);
                updateLoadChart(stats);
            } catch (error) {
                console.error('Error fetching stats:', error);
            }
        }

        function updateMetricsOverview(stats) {
            const metricsHtml = `
                <div class="metric-card p-6 text-center">
                    <div class="text-3xl font-bold">${stats.total_users}</div>
                    <div class="text-sm opacity-80">Total Users</div>
                </div>
                <div class="metric-card p-6 text-center">
                    <div class="text-3xl font-bold">${stats.total_photos}</div>
                    <div class="text-sm opacity-80">Total Photos</div>
                </div>
                <div class="metric-card p-6 text-center">
                    <div class="text-3xl font-bold">${stats.num_shards}</div>
                    <div class="text-sm opacity-80">Active Shards</div>
                </div>
                <div class="metric-card p-6 text-center">
                    <div class="text-3xl font-bold">${stats.hot_shards.length}</div>
                    <div class="text-sm opacity-80">Hot Shards</div>
                </div>
            `;
            document.getElementById('metricsOverview').innerHTML = metricsHtml;
        }

        function updateShardVisualization(stats) {
            let shardsHtml = '';
            
            for (let i = 0; i < stats.num_shards; i++) {
                const shardData = stats.shard_stats[i];
                const isHot = stats.hot_shards.includes(i);
                const cardClass = isHot ? 'hot-shard' : 'normal-shard';
                
                shardsHtml += `
                    <div class="shard-card ${cardClass} p-4 cursor-pointer" onclick="viewShardDetails(${i})">
                        <div class="font-bold text-lg">Shard ${i}</div>
                        <div class="text-sm opacity-80 mt-2">
                            <div>👥 Users: ${shardData.users}</div>
                            <div>📷 Photos: ${shardData.photos}</div>
                            <div>🔄 Queries: ${shardData.queries}</div>
                            <div>⚡ Load: ${Math.round(shardData.load)}</div>
                        </div>
                        ${isHot ? '<div class="mt-2 font-bold">🔥 HOT SHARD</div>' : ''}
                    </div>
                `;
            }
            
            document.getElementById('shardVisualization').innerHTML = shardsHtml;
        }

        function updateLoadChart(stats) {
            const shardIds = Object.keys(stats.shard_stats).map(Number);
            const loadValues = shardIds.map(id => stats.shard_stats[id].load);
            const colors = shardIds.map(id => stats.hot_shards.includes(id) ? '#ff6b6b' : '#4ecdc4');
            
            const trace = {
                x: shardIds.map(id => `Shard ${id}`),
                y: loadValues,
                type: 'bar',
                marker: {
                    color: colors
                },
                name: 'Shard Load'
            };
            
            const layout = {
                title: 'Load Distribution Across Shards',
                xaxis: { title: 'Shard ID' },
                yaxis: { title: 'Load Score' },
                showlegend: false
            };
            
            Plotly.newPlot('loadChart', [trace], layout);
        }

        async function addRandomUser() {
            try {
                const response = await fetch('/api/add_user', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({})
                });
                
                const result = await response.json();
                alert(`✅ User added to Shard ${result.user.shard_id}!\nCalculation: ${result.routing_info.calculation}`);
                refreshData();
            } catch (error) {
                console.error('Error adding user:', error);
            }
        }

        async function simulateLoad() {
            const shardId = prompt('Which shard should receive load? (0-7)', '0');
            const intensity = prompt('Load intensity (number of queries)', '100');
            
            if (shardId !== null && intensity !== null) {
                try {
                    const response = await fetch('/api/simulate_load', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({
                            shard_id: parseInt(shardId),
                            intensity: parseInt(intensity)
                        })
                    });
                    
                    const result = await response.json();
                    alert(`🔥 Load simulation complete!\n${result.message}`);
                    refreshData();
                } catch (error) {
                    console.error('Error simulating load:', error);
                }
            }
        }

        async function searchUser() {
            const userId = document.getElementById('userIdInput').value;
            if (!userId) {
                alert('Please enter a User ID');
                return;
            }
            
            try {
                const response = await fetch(`/api/user/${userId}`);
                const result = await response.json();
                
                if (response.ok) {
                    displayUserData(result);
                } else {
                    document.getElementById('userDataResult').innerHTML = 
                        `<div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
                            ❌ ${result.error}
                        </div>`;
                }
            } catch (error) {
                console.error('Error searching user:', error);
            }
        }

        function displayUserData(data) {
            const html = `
                <div class="bg-gray-50 rounded-lg p-4">
                    <h3 class="text-lg font-bold mb-2">User: ${data.user.username}</h3>
                    <div class="grid md:grid-cols-2 gap-4">
                        <div>
                            <p><strong>User ID:</strong> ${data.user.user_id}</p>
                            <p><strong>Email:</strong> ${data.user.email}</p>
                            <p><strong>Followers:</strong> ${data.user.follower_count}</p>
                            <p><strong>Photos:</strong> ${data.photos.length}</p>
                        </div>
                        <div class="bg-blue-50 p-3 rounded">
                            <h4 class="font-bold">🗄️ Shard Information</h4>
                            <p><strong>Shard ID:</strong> ${data.shard_info.shard_id}</p>
                            <p><strong>Routing:</strong> ${data.shard_info.routing_method}</p>
                        </div>
                    </div>
                </div>
            `;
            document.getElementById('userDataResult').innerHTML = html;
        }

        async function viewShardDetails(shardId) {
            try {
                const response = await fetch(`/api/shard/${shardId}`);
                const result = await response.json();
                
                alert(`🗄️ Shard ${shardId} Details:\n` +
                      `Users: ${result.users.length}\n` +
                      `Queries: ${result.stats.queries}\n` +
                      `Load: ${Math.round(result.stats.load)}\n` +
                      `Status: ${result.is_hot ? 'HOT 🔥' : 'Normal ✅'}`);
            } catch (error) {
                console.error('Error fetching shard details:', error);
            }
        }
    </script>
</body>
</html>
EOF

# Create test file
cat > tests/test_sharding.py << 'EOF'
"""
Test suite for Instagram sharding demo
"""

import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from app import ShardManager, User, Photo, InMemoryStorage
from datetime import datetime

def test_shard_manager_basic():
    """Test basic shard manager functionality"""
    sm = ShardManager(num_shards=4)
    
    # Test user ID sharding
    assert sm.get_shard_for_user(100) == 0  # 100 % 4 = 0
    assert sm.get_shard_for_user(101) == 1  # 101 % 4 = 1
    assert sm.get_shard_for_user(102) == 2  # 102 % 4 = 2
    assert sm.get_shard_for_user(103) == 3  # 103 % 4 = 3

def test_user_id_generation():
    """Test Instagram-style user ID generation"""
    sm = ShardManager()
    
    user_id = sm.generate_user_id()
    assert isinstance(user_id, int)
    assert user_id > 0
    
    # Generate multiple IDs and ensure they're unique
    ids = set()
    for _ in range(1000):
        uid = sm.generate_user_id()
        assert uid not in ids
        ids.add(uid)

def test_storage_operations():
    """Test in-memory storage operations"""
    storage = InMemoryStorage()
    sm = ShardManager(num_shards=4)
    
    # Create test user
    user = User(
        user_id=100,
        username="testuser",
        email="test@example.com",
        shard_id=sm.get_shard_for_user(100),
        created_at=datetime.now()
    )
    
    storage.add_user(user)
    retrieved_user = storage.get_user(100)
    
    assert retrieved_user is not None
    assert retrieved_user.username == "testuser"
    assert retrieved_user.shard_id == 0  # 100 % 4 = 0

def test_hot_shard_detection():
    """Test hot shard detection logic"""
    sm = ShardManager(num_shards=4)
    sm.hot_threshold = 10  # Low threshold for testing
    
    # Generate load on shard 0
    for _ in range(15):
        sm.update_shard_stats(0, 'query')
    
    hot_shards = sm.get_hot_shards()
    assert 0 in hot_shards

def test_shard_distribution():
    """Test that users are distributed across shards"""
    sm = ShardManager(num_shards=8)
    storage = InMemoryStorage()
    
    # Add users and check distribution
    shard_counts = {i: 0 for i in range(8)}
    
    for i in range(800):  # 100 users per shard on average
        user_id = sm.generate_user_id()
        shard_id = sm.get_shard_for_user(user_id)
        shard_counts[shard_id] += 1
    
    # Each shard should have some users (rough distribution)
    for count in shard_counts.values():
        assert count > 0, "All shards should have some users"

if __name__ == '__main__':
    pytest.main([__file__, '-v'])
EOF

# Create demo script
cat > demo.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Instagram Sharding Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start services
echo "🔧 Building Docker containers..."
docker-compose build

echo "🌟 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Run tests
echo "🧪 Running tests..."
docker-compose exec app pytest tests/ -v

# Show access information
echo ""
echo "✅ Instagram Sharding Demo is ready!"
echo "🌐 Access the demo at: http://localhost:5000"
echo "📊 API endpoint: http://localhost:5000/api/stats"
echo ""
echo "🎯 Demo Features:"
echo "   • Interactive shard visualization"
echo "   • User creation and routing"
echo "   • Hot shard simulation"
echo "   • Load distribution analysis"
echo ""
echo "📋 Commands:"
echo "   • View logs: docker-compose logs -f"
echo "   • Stop demo: ./cleanup.sh"
echo ""
EOF

chmod +x demo.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Instagram Sharding Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all --volumes --remove-orphans

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

# Create README
cat > README.md << 'EOF'
# Instagram Sharding Demo

This demo illustrates Instagram's sharding strategy evolution from monolithic to user-ID based sharding.

## Quick Start

1. **Start Demo**: `./demo.sh`
2. **Access Dashboard**: http://localhost:5000
3. **Clean Up**: `./cleanup.sh`

## Features

- **Interactive Visualization**: See how users distribute across shards
- **Hot Shard Detection**: Simulate and observe hot shard behavior  
- **User Creation**: Add users and watch shard routing in action
- **Load Analysis**: Real-time charts showing shard load distribution

## Learning Objectives

- Understand Instagram's sharding evolution
- Experience user-ID based partitioning
- Observe hot shard patterns
- Learn about cross-shard query challenges

## Architecture

- **Flask**: Web application and API
- **Redis**: Cache and session storage
- **PostgreSQL**: Simulated shard databases
- **Docker**: Containerized deployment

## API Endpoints

- `GET /api/stats` - Overall sharding statistics
- `GET /api/user/{id}` - User data and shard routing
- `GET /api/shard/{id}` - Shard-specific data
- `POST /api/add_user` - Create new user
- `POST /api/simulate_load` - Generate shard load

Happy Learning! 🚀
EOF

echo "✅ Instagram Sharding Demo setup complete!"
echo ""
echo "📁 Project structure created in: $PROJECT_NAME/"
echo ""
echo "🚀 Next steps:"
echo "   1. cd $PROJECT_NAME"
echo "   2. ./demo.sh"
echo "   3. Visit http://localhost:5000"
echo ""
echo "🧹 To clean up later: ./cleanup.sh"