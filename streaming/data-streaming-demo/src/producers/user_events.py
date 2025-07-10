import json
import time
import random
import logging
from datetime import datetime, timezone
from kafka import KafkaProducer
from faker import Faker
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class UserEventsProducer:
    def __init__(self, bootstrap_servers='localhost:9092'):
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None,
            batch_size=16384,
            linger_ms=10,
            retries=5,
            acks='all'
        )
        self.fake = Faker()
        self.topic = 'user-events'
        self.user_ids = [f"user_{i}" for i in range(1000)]
        
    def generate_event(self):
        """Generate realistic user events"""
        event_types = ['page_view', 'click', 'search', 'purchase', 'logout']
        
        event = {
            'event_id': self.fake.uuid4(),
            'user_id': random.choice(self.user_ids),
            'event_type': random.choice(event_types),
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'session_id': self.fake.uuid4()[:8],
            'device_type': random.choice(['desktop', 'mobile', 'tablet']),
            'page_url': self.fake.url(),
            'user_agent': self.fake.user_agent(),
            'ip_address': self.fake.ipv4(),
            'metadata': {
                'referrer': self.fake.url() if random.random() > 0.3 else None,
                'duration': random.randint(1, 300),
                'elements_clicked': random.randint(0, 10)
            }
        }
        
        # Add event-specific data
        if event['event_type'] == 'purchase':
            event['purchase_data'] = {
                'product_id': f"prod_{random.randint(1, 10000)}",
                'amount': round(random.uniform(10, 1000), 2),
                'currency': 'USD',
                'payment_method': random.choice(['credit_card', 'paypal', 'bank_transfer'])
            }
        elif event['event_type'] == 'search':
            event['search_data'] = {
                'query': self.fake.sentence(),
                'results_count': random.randint(0, 100),
                'filters_applied': random.choice([True, False])
            }
            
        return event
    
    def run(self, rate=100):
        """Run producer with specified rate (events per second)"""
        logger.info(f"Starting user events producer with rate: {rate} events/second")
        
        interval = 1.0 / rate
        
        try:
            while True:
                start_time = time.time()
                
                event = self.generate_event()
                key = event['user_id']
                
                # Send to Kafka
                future = self.producer.send(
                    self.topic,
                    key=key,
                    value=event,
                    partition=hash(key) % 6  # Distribute across 6 partitions
                )
                
                # Log every 100th event
                if random.random() < 0.01:
                    logger.info(f"Sent event: {event['event_type']} for user {event['user_id']}")
                
                # Sleep to maintain rate
                elapsed = time.time() - start_time
                sleep_time = max(0, interval - elapsed)
                time.sleep(sleep_time)
                
        except KeyboardInterrupt:
            logger.info("Shutting down producer...")
        finally:
            self.producer.close()

if __name__ == "__main__":
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    rate = int(os.getenv('PRODUCER_RATE', '100'))
    
    producer = UserEventsProducer(bootstrap_servers)
    producer.run(rate)
