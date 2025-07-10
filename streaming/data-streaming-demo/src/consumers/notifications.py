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

class NotificationsConsumer:
    def __init__(self, bootstrap_servers='localhost:9092', redis_host='localhost'):
        self.consumer = KafkaConsumer(
            'user-events',
            bootstrap_servers=bootstrap_servers,
            group_id='notifications',
            auto_offset_reset='latest',
            enable_auto_commit=True,
            auto_commit_interval_ms=1000,
            value_deserializer=lambda m: json.loads(m.decode('utf-8'))
        )
        
        self.redis_client = redis.Redis(host=redis_host, port=6379, db=2)
        self.stats = defaultdict(int)
        
    def process_event(self, event):
        """Process user event for notifications"""
        start_time = time.time()
        
        try:
            user_id = event.get('user_id')
            event_type = event.get('event_type')
            
            if not user_id:
                return
                
            # Determine if notification should be sent
            should_notify = False
            notification_type = None
            
            if event_type == 'purchase':
                should_notify = True
                notification_type = 'purchase_confirmation'
                
            elif event_type == 'search' and random.random() < 0.05:  # 5% chance
                should_notify = True
                notification_type = 'search_suggestions'
                
            elif event_type == 'page_view':
                # Check if user has been inactive
                last_activity = self.redis_client.get(f"last_activity:{user_id}")
                if last_activity:
                    last_time = datetime.fromisoformat(last_activity.decode('utf-8'))
                    if (datetime.now() - last_time).total_seconds() > 1800:  # 30 minutes
                        should_notify = True
                        notification_type = 'welcome_back'
                        
            # Store last activity
            self.redis_client.setex(f"last_activity:{user_id}", 3600, datetime.now().isoformat())
            
            # Send notification if needed
            if should_notify:
                notification = self.create_notification(user_id, event, notification_type)
                self.send_notification(notification)
                self.stats['notifications_sent'] += 1
            
            # Update consumer metrics
            processing_time = time.time() - start_time
            self.redis_client.hset('consumer_metrics:notifications', mapping={
                'processed_events': self.stats.get('total_processed', 0),
                'notifications_sent': self.stats.get('notifications_sent', 0),
                'avg_processing_time': processing_time,
                'last_processed': datetime.now().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error processing event: {e}")
            self.stats['errors'] += 1
    
    def create_notification(self, user_id, event, notification_type):
        """Create notification object"""
        notification = {
            'id': f"notif_{int(time.time() * 1000)}_{user_id}",
            'user_id': user_id,
            'type': notification_type,
            'timestamp': datetime.now().isoformat(),
            'channels': ['email', 'push'],
            'priority': 'normal'
        }
        
        if notification_type == 'purchase_confirmation':
            purchase_data = event.get('purchase_data', {})
            notification.update({
                'title': 'Purchase Confirmed',
                'message': f"Your order for {purchase_data.get('product_id', 'item')} has been confirmed.",
                'priority': 'high'
            })
            
        elif notification_type == 'search_suggestions':
            search_data = event.get('search_data', {})
            notification.update({
                'title': 'Search Suggestions',
                'message': f"Found {search_data.get('results_count', 0)} results for your search.",
                'priority': 'low'
            })
            
        elif notification_type == 'welcome_back':
            notification.update({
                'title': 'Welcome Back!',
                'message': 'Check out what\'s new since your last visit.',
                'priority': 'normal'
            })
        
        return notification
    
    def send_notification(self, notification):
        """Simulate sending notification"""
        # Store notification in Redis for dashboard
        self.redis_client.lpush('notifications:recent', json.dumps(notification))
        self.redis_client.ltrim('notifications:recent', 0, 99)  # Keep only last 100
        
        # Simulate processing delay
        time.sleep(random.uniform(0.1, 0.5))
        
        logger.info(f"Sent {notification['type']} notification to user {notification['user_id']}")
    
    def run(self):
        """Run consumer"""
        logger.info("Starting notifications consumer...")
        
        try:
            for message in self.consumer:
                event = message.value
                self.process_event(event)
                
                self.stats['total_processed'] += 1
                
                # Log progress every 150 events
                if self.stats['total_processed'] % 150 == 0:
                    logger.info(f"Processed {self.stats['total_processed']} events, "
                              f"sent {self.stats['notifications_sent']} notifications")
                    
        except KeyboardInterrupt:
            logger.info("Shutting down consumer...")
        finally:
            self.consumer.close()

if __name__ == "__main__":
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    
    consumer = NotificationsConsumer(bootstrap_servers, redis_host)
    consumer.run()
