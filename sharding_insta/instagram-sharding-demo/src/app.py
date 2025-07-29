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
        self.shard_stats[shard_id]['load'] = stats['users'] + stats['photos'] + stats['queries']
    
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
        'new_stats': shard_manager.shard_stats[target_shard],
        'is_hot': target_shard in shard_manager.get_hot_shards()
    })

@app.route('/api/simulate_pattern', methods=['POST'])
def simulate_pattern():
    """Simulate different load patterns across shards"""
    data = request.json
    pattern_type = data.get('pattern', 'random')
    total_load = data.get('total_load', 500)
    
    if pattern_type == 'hot_spot':
        # Create a hot spot on a random shard
        hot_shard = random.randint(0, shard_manager.num_shards - 1)
        hot_load = int(total_load * 0.7)  # 70% of load on hot shard
        remaining_load = total_load - hot_load
        
        # Apply hot load
        for _ in range(hot_load):
            shard_manager.update_shard_stats(hot_shard, 'query')
        
        # Distribute remaining load
        for _ in range(remaining_load):
            shard_id = random.randint(0, shard_manager.num_shards - 1)
            shard_manager.update_shard_stats(shard_id, 'query')
        
        return jsonify({
            'message': f'Created hot spot on shard {hot_shard} with {hot_load} queries',
            'hot_shard': hot_shard,
            'hot_load': hot_load,
            'total_load': total_load
        })
    
    elif pattern_type == 'cascade':
        # Create cascading load across shards
        for i in range(shard_manager.num_shards):
            load_per_shard = total_load // shard_manager.num_shards
            for _ in range(load_per_shard):
                shard_manager.update_shard_stats(i, 'query')
        
        return jsonify({
            'message': f'Applied cascading load across all {shard_manager.num_shards} shards',
            'load_per_shard': total_load // shard_manager.num_shards,
            'total_load': total_load
        })
    
    else:  # random
        # Random distribution
        for _ in range(total_load):
            shard_id = random.randint(0, shard_manager.num_shards - 1)
            shard_manager.update_shard_stats(shard_id, 'query')
        
        return jsonify({
            'message': f'Randomly distributed {total_load} queries across shards',
            'total_load': total_load
        })

if __name__ == '__main__':
    # Generate sample data on startup
    generate_sample_data()
    print("🌟 Instagram Sharding Demo ready!")
    print("📊 Dashboard: http://localhost:5000")
    print("🔧 API: http://localhost:5000/api/stats")
    
    app.run(host='0.0.0.0', port=5000, debug=True)
