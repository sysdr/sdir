import redis
import json
import asyncio
from typing import List, Callable
from shared.events.base import DomainEvent

class EventBus:
    def __init__(self, redis_url: str):
        self.redis_client = redis.from_url(redis_url)
        self.subscribers = {}
    
    def publish(self, event: DomainEvent):
        """Publish domain event to the event bus"""
        channel = f"events.{event.event_type}"
        self.redis_client.publish(channel, event.to_json())
        print(f"📤 Published {event.event_type}: {event.event_id}")
    
    def subscribe(self, event_type: str, handler: Callable[[dict], None]):
        """Subscribe to specific event types"""
        if event_type not in self.subscribers:
            self.subscribers[event_type] = []
        self.subscribers[event_type].append(handler)
        
    def start_listening(self):
        """Start listening for events"""
        pubsub = self.redis_client.pubsub()
        
        for event_type in self.subscribers.keys():
            pubsub.subscribe(f"events.{event_type}")
        
        for message in pubsub.listen():
            if message['type'] == 'message':
                try:
                    event_data = json.loads(message['data'])
                    event_type = event_data['event_type']
                    
                    if event_type in self.subscribers:
                        for handler in self.subscribers[event_type]:
                            handler(event_data)
                            
                except Exception as e:
                    print(f"❌ Error processing event: {e}")

