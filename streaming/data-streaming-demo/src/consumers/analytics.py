import json
import time
import logging
from datetime import datetime, timezone
from kafka import KafkaConsumer
import redis
import os
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AnalyticsConsumer:
    def __init__(self, bootstrap_servers='localhost:9092', redis_host='localhost'):
        self.consumer = KafkaConsumer(
            'user-events',
            bootstrap_servers=bootstrap_servers,
            group_id='analytics',
            auto_offset_reset='latest',
            enable_auto_commit=True,
            auto_commit_interval_ms=1000,
            value_deserializer=lambda m: json.loads(m.decode('utf-8'))
        )
        
        self.redis_client = redis.Redis(host=redis_host, port=6379, db=0)
        self.stats = defaultdict(int)
        self.processing_times = []
        
    def process_event(self, event):
        """Process user event for analytics"""
        start_time = time.time()
        
        try:
            # Update event type counters
            event_type = event.get('event_type', 'unknown')
            self.stats[f"event_type:{event_type}"] += 1
            
            # Update device type stats
            device_type = event.get('device_type', 'unknown')
            self.stats[f"device_type:{device_type}"] += 1
            
            # Process purchase events
            if event_type == 'purchase':
                purchase_data = event.get('purchase_data', {})
                amount = purchase_data.get('amount', 0)
                self.stats['total_revenue'] += amount
                self.stats['total_purchases'] += 1
                
                # Store in Redis for real-time dashboard
                self.redis_client.incr('analytics:total_purchases')
                self.redis_client.incrbyfloat('analytics:total_revenue', amount)
                
            # Update user activity
            user_id = event.get('user_id')
            if user_id:
                self.redis_client.setex(f"user_activity:{user_id}", 3600, datetime.now().isoformat())
                
            # Store processing metrics
            processing_time = time.time() - start_time
            self.processing_times.append(processing_time)
            
            # Keep only last 100 processing times
            if len(self.processing_times) > 100:
                self.processing_times = self.processing_times[-100:]
                
            # Update Redis with consumer metrics
            self.redis_client.hset('consumer_metrics:analytics', mapping={
                'processed_events': self.stats.get('total_processed', 0),
                'avg_processing_time': sum(self.processing_times) / len(self.processing_times),
                'last_processed': datetime.now().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error processing event: {e}")
            self.stats['errors'] += 1
    
    def run(self):
        """Run consumer"""
        logger.info("Starting analytics consumer...")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                self.stats['total_processed'] += 1
                
                # Log progress every 100 events
                if self.stats['total_processed'] % 100 == 0:
                    logger.info(f"Processed {self.stats['total_processed']} events")
                    
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
        finally:
            self.consumer.close()

if __name__ == "__main__":
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    
    consumer = AnalyticsConsumer(bootstrap_servers, redis_host)
    consumer.run()
