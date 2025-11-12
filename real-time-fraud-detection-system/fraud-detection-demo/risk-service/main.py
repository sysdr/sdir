import json
import os
from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import NoBrokersAvailable
import redis
from sklearn.ensemble import RandomForestClassifier
import numpy as np
import psycopg2
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

# Simple ML model (pre-trained simulation)
class FraudModel:
    def __init__(self):
        self.model = RandomForestClassifier(n_estimators=10, random_state=42)
        # Train on dummy data
        X_train = np.random.rand(100, 5) * 100
        y_train = (X_train.sum(axis=1) > 200).astype(int)
        self.model.fit(X_train, y_train)
    
    def predict_proba(self, features):
        return self.model.predict_proba([features])[0][1] * 100

model = FraudModel()

def apply_rules(features):
    """Rule-based scoring"""
    rule_score = 0
    triggered_rules = []
    
    # Rule 1: High velocity
    if features['velocityScore'] > 30:
        rule_score += 20
        triggered_rules.append("R1: High velocity")
    
    # Rule 2: Geo anomaly
    if features['geoScore'] > 20:
        rule_score += 25
        triggered_rules.append("R2: Geographic anomaly")
    
    # Rule 3: New device + high amount
    if features['deviceScore'] > 20 and features['amount'] > 500:
        rule_score += 15
        triggered_rules.append("R3: New device + high amount")
    
    # Rule 4: Graph risk
    if features['graphScore'] > 10:
        rule_score += 20
        triggered_rules.append("R4: Fraud network connection")
    
    return min(100, rule_score), triggered_rules

def calculate_risk_score(features):
    """Hybrid scoring: Rules + ML"""
    # Rule-based score
    rule_score, triggered_rules = apply_rules(features)
    
    # ML model score
    feature_vector = [
        features['velocityScore'],
        features['geoScore'],
        features['deviceScore'],
        features['graphScore'],
        features['amount']
    ]
    ml_score = model.predict_proba(feature_vector)
    
    # Weighted combination: 60% rules, 40% ML
    final_score = int(rule_score * 0.6 + ml_score * 0.4)
    
    return final_score, ml_score, triggered_rules

def make_decision(risk_score):
    """Decision logic with thresholds"""
    if risk_score < 40:
        return "APPROVE"
    elif risk_score < 75:
        return "CHALLENGE"
    else:
        return "BLOCK"

def process_features():
    max_retries = 30
    retry_delay = 2
    
    consumer = None
    for attempt in range(max_retries):
        try:
            consumer = KafkaConsumer(
                'features',
                bootstrap_servers=[KAFKA_BROKER],
                value_deserializer=lambda m: json.loads(m.decode('utf-8')),
                group_id='risk-scorer',
                api_version=(0, 10, 1)
            )
            print("🎯 Risk scoring service started...")
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
        features = message.value
        
        # Calculate risk
        risk_score, ml_score, triggered_rules = calculate_risk_score(features)
        decision = make_decision(risk_score)
        
        result = {
            'transactionId': features['transactionId'],
            'userId': features['userId'],
            'amount': features['amount'],
            'riskScore': risk_score,
            'mlScore': int(ml_score),
            'decision': decision,
            'triggeredRules': triggered_rules,
            'features': features,
            'timestamp': features['timestamp']
        }
        
        # Send decision
        producer.send('fraud-decisions', value=result)
        
        symbol = "✅" if decision == "APPROVE" else "⚠️" if decision == "CHALLENGE" else "🚫"
        print(f"{symbol} Risk Score: {risk_score} | ML: {int(ml_score)} | Decision: {decision} | {features['transactionId']}")

if __name__ == "__main__":
    process_features()
