import json
import asyncio
from datetime import datetime, timedelta
from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import NoBrokersAvailable
import redis
import os
from collections import defaultdict
import math
import time

KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'localhost:9092')
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379')

redis_client = redis.from_url(REDIS_URL, decode_responses=True)

def create_producer():
    """Create Kafka producer with retry logic"""
    max_retries = 30
    retry_delay = 2
    
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=[KAFKA_BROKER],
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                api_version=(0, 10, 1)
            )
            print(f"✅ Connected to Kafka broker at {KAFKA_BROKER}")
            return producer
        except (NoBrokersAvailable, Exception) as e:
            if attempt < max_retries - 1:
                print(f"⏳ Waiting for Kafka broker... (attempt {attempt + 1}/{max_retries})")
                time.sleep(retry_delay)
            else:
                print(f"❌ Failed to connect to Kafka after {max_retries} attempts: {e}")
                raise

producer = create_producer()

def calculate_velocity_score(user_id, device_id):
    """Calculate transaction velocity"""
    user_key = f"velocity:user:{user_id}"
    device_key = f"velocity:device:{device_id}"
    
    user_count = redis_client.incr(user_key)
    redis_client.expire(user_key, 300)  # 5 minutes
    
    device_count = redis_client.incr(device_key)
    redis_client.expire(device_key, 300)
    
    # Score based on velocity (0-50 points)
    velocity_score = min(50, (user_count - 1) * 15 + (device_count - 1) * 10)
    
    return velocity_score, user_count, device_count

def calculate_geo_anomaly(user_id, latitude, longitude):
    """Detect geographical impossibility"""
    last_location_key = f"location:{user_id}"
    last_data = redis_client.get(last_location_key)
    
    if not last_data:
        redis_client.setex(last_location_key, 3600, json.dumps({
            'lat': latitude,
            'lon': longitude,
            'timestamp': datetime.now().isoformat()
        }))
        return 0, "First transaction"
    
    last = json.loads(last_data)
    
    # Calculate distance (simple Haversine)
    lat1, lon1 = math.radians(last['lat']), math.radians(last['lon'])
    lat2, lon2 = math.radians(latitude), math.radians(longitude)
    
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    distance_km = 6371 * c
    
    # Time difference
    last_time = datetime.fromisoformat(last['timestamp'])
    time_diff_hours = (datetime.now() - last_time).total_seconds() / 3600
    
    # Impossible velocity check (>800 km/h suggests fraud)
    if time_diff_hours > 0:
        speed = distance_km / time_diff_hours
        if speed > 800:
            score = 30
            reason = f"Impossible velocity: {speed:.0f} km/h"
        elif distance_km > 500:
            score = 20
            reason = f"Large distance: {distance_km:.0f} km"
        else:
            score = 0
            reason = "Normal"
    else:
        score = 0
        reason = "Same timeframe"
    
    # Update location
    redis_client.setex(last_location_key, 3600, json.dumps({
        'lat': latitude,
        'lon': longitude,
        'timestamp': datetime.now().isoformat()
    }))
    
    return score, reason

def calculate_device_risk(device_id):
    """Check device reputation"""
    device_key = f"device:reputation:{device_id}"
    reputation = redis_client.get(device_key)
    
    if not reputation:
        # New device
        redis_client.setex(device_key, 86400, "new")
        return 25, "New device"
    
    if reputation == "blocked":
        return 50, "Previously blocked device"
    
    return 0, "Known device"

def calculate_graph_score(user_id):
    """Simple graph-based risk (simulated)"""
    # Check if user is connected to known fraudsters
    fraud_network_key = f"fraud:network:{user_id}"
    is_connected = redis_client.get(fraud_network_key)
    
    if is_connected:
        return 15, "Connected to fraud network"
    
    return 0, "Clean network"

async def process_transactions():
    max_retries = 30
    retry_delay = 2
    
    consumer = None
    for attempt in range(max_retries):
        try:
            consumer = KafkaConsumer(
                'transactions',
                bootstrap_servers=[KAFKA_BROKER],
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                group_id='feature-extractor',
                api_version=(0, 10, 1)
            )
            print("🔍 Feature extraction service started...")
            break
        except (NoBrokersAvailable, Exception) as e:
            if attempt < max_retries - 1:
                print(f"⏳ Waiting for Kafka broker... (attempt {attempt + 1}/{max_retries})")
                time.sleep(retry_delay)
            else:
                print(f"❌ Failed to connect to Kafka after {max_retries} attempts: {e}")
                raise
    
    if consumer is None:
        raise Exception("Failed to create Kafka consumer")
    
    for message in consumer:
        txn = message.value
        
        # Extract features
        velocity_score, user_count, device_count = calculate_velocity_score(
            txn['userId'], txn['deviceId']
        )
        
        geo_score, geo_reason = calculate_geo_anomaly(
            txn['userId'], txn['latitude'], txn['longitude']
        )
        
        device_score, device_reason = calculate_device_risk(txn['deviceId'])
        graph_score, graph_reason = calculate_graph_score(txn['userId'])
        
        features = {
            'transactionId': txn['transactionId'],
            'userId': txn['userId'],
            'amount': txn['amount'],
            'velocityScore': velocity_score,
            'velocityDetails': f"{user_count} txn/5min (user), {device_count} txn/5min (device)",
            'geoScore': geo_score,
            'geoDetails': geo_reason,
            'deviceScore': device_score,
            'deviceDetails': device_reason,
            'graphScore': graph_score,
            'graphDetails': graph_reason,
            'timestamp': txn['timestamp']
        }
        
        # Send to risk scoring
        producer.send('features', value=features)
        
        print(f"✅ Features extracted: {txn['transactionId']} - Total risk indicators: {velocity_score + geo_score + device_score + graph_score}")

if __name__ == "__main__":
    asyncio.run(process_transactions())
