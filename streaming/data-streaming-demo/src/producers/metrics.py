import json
import time
import random
import logging
from datetime import datetime, timezone
from kafka import KafkaProducer
import os
import psutil

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MetricsProducer:
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
        self.topic = 'system-metrics'
        self.services = ['web-server', 'database', 'cache', 'queue-processor', 'auth-service']
        
    def generate_metric(self):
        """Generate system metrics"""
        service = random.choice(self.services)
        
        # Base metrics with realistic variations
        cpu_usage = random.uniform(10, 90)
        memory_usage = random.uniform(20, 85)
        disk_usage = random.uniform(30, 95)
        network_io = random.uniform(0, 1000)
        
        # Add service-specific patterns
        if service == 'database':
            cpu_usage *= 1.2  # Database typically uses more CPU
            memory_usage *= 1.1
        elif service == 'cache':
            memory_usage *= 1.3  # Cache uses more memory
            
        metric = {
            'metric_id': f"{service}_{int(time.time() * 1000)}",
            'service': service,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'metrics': {
                'cpu_usage_percent': min(100, cpu_usage),
                'memory_usage_percent': min(100, memory_usage),
                'disk_usage_percent': min(100, disk_usage),
                'network_io_mbps': network_io,
                'active_connections': random.randint(0, 1000),
                'response_time_ms': random.uniform(10, 2000),
                'error_rate_percent': random.uniform(0, 5),
                'throughput_rps': random.uniform(10, 500)
            },
            'host': f"host-{random.randint(1, 10)}",
            'environment': random.choice(['production', 'staging', 'development']),
            'region': random.choice(['us-east-1', 'us-west-2', 'eu-west-1'])
        }
        
        return metric
    
    def run(self, rate=50):
        """Run producer with specified rate (metrics per second)"""
        logger.info(f"Starting metrics producer with rate: {rate} metrics/second")
        
        interval = 1.0 / rate
        
        try:
            while True:
                start_time = time.time()
                
                metric = self.generate_metric()
                key = metric['service']
                
                # Send to Kafka
                future = self.producer.send(
                    self.topic,
                    key=key,
                    value=metric,
                    partition=hash(key) % 6  # Distribute across 6 partitions
                )
                
                # Log every 20th metric
                if random.random() < 0.05:
                    logger.info(f"Sent metric: {metric['service']} CPU: {metric['metrics']['cpu_usage_percent']:.1f}%")
                
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
    rate = int(os.getenv('PRODUCER_RATE', '50'))
    
    producer = MetricsProducer(bootstrap_servers)
    producer.run(rate)
