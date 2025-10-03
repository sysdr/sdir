import psycopg2
import time
import requests
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MONITOR_INTERVAL = 5  # seconds
FAILURE_THRESHOLD = 3  # consecutive failures

failure_counts = {
    'primary': 0,
    'replica1': 0,
    'replica2': 0
}

def get_connection(host, port=5432):
    try:
        return psycopg2.connect(
            host=host,
            port=port,
            user='postgres',
            password='password',
            database='testdb',
            connect_timeout=3
        )
    except Exception as e:
        return None

def health_check_with_write(host):
    """Perform health check including write operation"""
    conn = get_connection(host)
    if not conn:
        return False
    
    try:
        cur = conn.cursor()
        # Try to write health check
        cur.execute(
            "INSERT INTO health_check (node_name) VALUES (%s) RETURNING timestamp",
            (host,)
        )
        result = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        
        if result:
            logger.info(f"✓ Health check passed for {host}: {result[0]}")
            return True
        return False
    except Exception as e:
        logger.error(f"✗ Health check failed for {host}: {e}")
        return False

def check_query_latency(host):
    """Check P99 query latency"""
    conn = get_connection(host)
    if not conn:
        return float('inf')
    
    try:
        cur = conn.cursor()
        start = time.time()
        cur.execute("SELECT COUNT(*) FROM transactions")
        result = cur.fetchone()
        latency = (time.time() - start) * 1000  # ms
        cur.close()
        conn.close()
        
        logger.info(f"Query latency for {host}: {latency:.2f}ms")
        return latency
    except:
        return float('inf')

def monitor_cluster():
    """Monitor cluster health"""
    logger.info("Starting cluster monitoring...")
    
    # Get current primary from orchestrator
    try:
        response = requests.get('http://orchestrator:5001/status', timeout=5)
        cluster_state = response.json()
        current_primary = cluster_state.get('primary', 'primary')
    except:
        current_primary = 'primary'
        logger.warning("Could not fetch cluster state from orchestrator")
    
    while True:
        try:
            # Check primary health
            primary_healthy = health_check_with_write(current_primary)
            latency = check_query_latency(current_primary)
            
            if not primary_healthy or latency > 5000:  # 5 second threshold
                failure_counts[current_primary] += 1
                logger.warning(f"Primary {current_primary} unhealthy (failures: {failure_counts[current_primary]})")
                
                if failure_counts[current_primary] >= FAILURE_THRESHOLD:
                    logger.error(f"Primary {current_primary} failed! Triggering failover...")
                    
                    # Notify orchestrator
                    try:
                        requests.post(
                            'http://orchestrator:5001/failover_notification',
                            json={'action': 'failover', 'failed_node': current_primary},
                            timeout=5
                        )
                    except Exception as e:
                        logger.error(f"Failed to notify orchestrator: {e}")
                    
                    # Reset counter and wait for failover
                    failure_counts[current_primary] = 0
                    time.sleep(30)
                    
                    # Update primary
                    try:
                        response = requests.get('http://orchestrator:5001/status', timeout=5)
                        cluster_state = response.json()
                        current_primary = cluster_state.get('primary', 'primary')
                        logger.info(f"New primary: {current_primary}")
                    except:
                        pass
            else:
                failure_counts[current_primary] = 0
            
            # Check replicas
            for replica in ['replica1', 'replica2']:
                replica_healthy = health_check_with_write(replica)
                if replica_healthy:
                    failure_counts[replica] = 0
                else:
                    failure_counts[replica] += 1
            
        except Exception as e:
            logger.error(f"Monitor error: {e}")
        
        time.sleep(MONITOR_INTERVAL)

if __name__ == '__main__':
    time.sleep(15)  # Wait for all services
    monitor_cluster()
