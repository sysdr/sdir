import unittest
import json
import time
import threading
from unittest.mock import Mock, patch
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from producers.user_events import UserEventsProducer
from consumers.analytics import AnalyticsConsumer

class TestStreamingPipeline(unittest.TestCase):
    
    def setUp(self):
        """Set up test environment"""
        self.mock_producer = Mock()
        self.mock_consumer = Mock()
        self.mock_redis = Mock()
    
    def test_user_event_generation(self):
        """Test user event generation"""
        producer = UserEventsProducer('localhost:9092')
        
        # Generate test event
        event = producer.generate_event()
        
        # Verify event structure
        self.assertIn('event_id', event)
        self.assertIn('user_id', event)
        self.assertIn('event_type', event)
        self.assertIn('timestamp', event)
        self.assertIn('session_id', event)
        
        # Verify event types
        self.assertIn(event['event_type'], ['page_view', 'click', 'search', 'purchase', 'logout'])
        
        # Verify purchase event has required data
        if event['event_type'] == 'purchase':
            self.assertIn('purchase_data', event)
            self.assertIn('product_id', event['purchase_data'])
            self.assertIn('amount', event['purchase_data'])
    
    def test_analytics_consumer_processing(self):
        """Test analytics consumer event processing"""
        with patch('redis.Redis') as mock_redis_class:
            mock_redis_instance = Mock()
            mock_redis_class.return_value = mock_redis_instance
            
            consumer = AnalyticsConsumer('localhost:9092', 'localhost')
            
            # Test event processing
            test_event = {
                'event_id': 'test-123',
                'user_id': 'user_1',
                'event_type': 'purchase',
                'timestamp': '2024-01-01T12:00:00Z',
                'purchase_data': {
                    'product_id': 'prod_123',
                    'amount': 99.99
                }
            }
            
            consumer.process_event(test_event)
            
            # Verify stats were updated
            self.assertEqual(consumer.stats['event_type:purchase'], 1)
            self.assertEqual(consumer.stats['total_revenue'], 99.99)
            self.assertEqual(consumer.stats['total_purchases'], 1)
            
            # Verify Redis calls
            mock_redis_instance.incr.assert_called()
            mock_redis_instance.incrbyfloat.assert_called()
    
    def test_event_serialization(self):
        """Test event serialization/deserialization"""
        producer = UserEventsProducer('localhost:9092')
        event = producer.generate_event()
        
        # Serialize event
        serialized = json.dumps(event)
        
        # Deserialize event
        deserialized = json.loads(serialized)
        
        # Verify integrity
        self.assertEqual(event['event_id'], deserialized['event_id'])
        self.assertEqual(event['user_id'], deserialized['user_id'])
        self.assertEqual(event['event_type'], deserialized['event_type'])
    
    def test_consumer_error_handling(self):
        """Test consumer error handling"""
        with patch('redis.Redis') as mock_redis_class:
            mock_redis_instance = Mock()
            mock_redis_class.return_value = mock_redis_instance
            
            consumer = AnalyticsConsumer('localhost:9092', 'localhost')
            
            # Test with invalid event
            invalid_event = {'invalid': 'data'}
            
            # Should not raise exception
            consumer.process_event(invalid_event)
            
            # Error count should be incremented
            self.assertEqual(consumer.stats['errors'], 1)
    
    def test_rate_limiting(self):
        """Test producer rate limiting"""
        producer = UserEventsProducer('localhost:9092')
        
        # Test that events are generated at correct rate
        start_time = time.time()
        event_count = 0
        
        # Simulate 5 events at 10 events/second
        for _ in range(5):
            producer.generate_event()
            event_count += 1
            time.sleep(0.1)  # 100ms interval = 10 events/second
        
        elapsed = time.time() - start_time
        actual_rate = event_count / elapsed
        
        # Should be approximately 10 events/second (within 20% tolerance)
        self.assertGreater(actual_rate, 8)
        self.assertLess(actual_rate, 12)

if __name__ == '__main__':
    unittest.main()
