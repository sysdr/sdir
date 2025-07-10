import json
import time
import logging
from datetime import datetime, timezone
from kafka import KafkaConsumer
import redis
import os
import random
from collections import defaultdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class RecommendationsConsumer:
    def __init__(self, bootstrap_servers='localhost:9092', redis_host='localhost'):
        self.consumer = KafkaConsumer(
            'user-events',
            bootstrap_servers=bootstrap_servers,
            group_id='recommendations',
            auto_offset_reset='latest',
            enable_auto_commit=True,
            auto_commit_interval_ms=1000,
            value_deserializer=lambda m: json.loads(m.decode('utf-8'))
        )
        
        self.redis_client = redis.Redis(host=redis_host, port=6379, db=1)
        self.stats = defaultdict(int)
        self.user_preferences = defaultdict(dict)
        
    def process_event(self, event):
        """Process user event for recommendations"""
        start_time = time.time()
        
        try:
            user_id = event.get('user_id')
            event_type = event.get('event_type')
            
            if not user_id:
                return
                
            # Update user behavior patterns
            if event_type == 'page_view':
                page_url = event.get('page_url', '')
                if '/product/' in page_url:
                    product_id = page_url.split('/product/')[-1].split('?')[0]
                    self.user_preferences[user_id]['viewed_products'] = \
                        self.user_preferences[user_id].get('viewed_products', [])
                    self.user_preferences[user_id]['viewed_products'].append(product_id)
                    
            elif event_type == 'purchase':
                purchase_data = event.get('purchase_data', {})
                product_id = purchase_data.get('product_id')
                if product_id:
                    self.user_preferences[user_id]['purchased_products'] = \
                        self.user_preferences[user_id].get('purchased_products', [])
                    self.user_preferences[user_id]['purchased_products'].append(product_id)
                    
            elif event_type == 'search':
                search_data = event.get('search_data', {})
                query = search_data.get('query')
                if query:
                    self.user_preferences[user_id]['search_history'] = \
                        self.user_preferences[user_id].get('search_history', [])
                    self.user_preferences[user_id]['search_history'].append(query)
            
            # Generate recommendations (simulated)
            if random.random() < 0.1:  # Generate recommendations for 10% of events
                recommendations = self.generate_recommendations(user_id)
                self.redis_client.setex(
                    f"recommendations:{user_id}",
                    3600,  # 1 hour TTL
                    json.dumps(recommendations)
                )
                self.stats['recommendations_generated'] += 1
            
            # Update consumer metrics
            processing_time = time.time() - start_time
            self.redis_client.hset('consumer_metrics:recommendations', mapping={
                'processed_events': self.stats.get('total_processed', 0),
                'recommendations_generated': self.stats.get('recommendations_generated', 0),
                'avg_processing_time': processing_time,
                'last_processed': datetime.now().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error processing event: {e}")
            self.stats['errors'] += 1
    
    def generate_recommendations(self, user_id):
        """Generate sample recommendations"""
        # Simulated recommendation logic
        categories = ['electronics', 'clothing', 'books', 'home', 'sports']
        
        recommendations = []
        for i in range(5):
            recommendations.append({
                'product_id': f"prod_{random.randint(1, 10000)}",
                'title': f"Recommended Product {i+1}",
                'category': random.choice(categories),
                'score': random.uniform(0.5, 1.0),
                'reason': random.choice(['frequently_bought', 'similar_users', 'viewed_together'])
            })
        
        return recommendations
    
    def run(self):
        """Run consumer"""
        logger.info("Starting recommendations consumer...")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                self.stats['total_processed'] += 1
                
                # Log progress every 200 events
                if self.stats['total_processed'] % 200 == 0:
                    logger.info(f"Processed {self.stats['total_processed']} events, "
                              f"generated {self.stats['recommendations_generated']} recommendations")
                    
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
        finally:
            self.consumer.close()

if __name__ == "__main__":
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    
    consumer = RecommendationsConsumer(bootstrap_servers, redis_host)
    consumer.run()
