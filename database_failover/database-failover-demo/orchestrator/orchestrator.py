import psycopg2
import time
import json
import logging
from datetime import datetime
from flask import Flask, jsonify, request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Cluster state
cluster_state = {
    'primary': 'primary',
    'replicas': ['replica1', 'replica2'],
    'failover_in_progress': False,
    'last_failover': None,
    'split_brain_prevented': 0,
    'lease_holder': 'primary',
    'lease_expiry': None
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
        logger.error(f"Connection failed to {host}: {e}")
        return None

def check_replication_lag(replica_host):
    """Check replication lag in seconds"""
    conn = get_connection(replica_host)
    if not conn:
        return float('inf')
    
    try:
        cur = conn.cursor()
        cur.execute("SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag")
        result = cur.fetchone()
        lag = result[0] if result and result[0] else 0
        cur.close()
        conn.close()
        return lag if lag else 0
    except Exception as e:
        logger.error(f"Error checking lag on {replica_host}: {e}")
        return float('inf')

def is_in_recovery(host):
    """Check if database is in recovery mode (replica)"""
    conn = get_connection(host)
    if not conn:
        return None
    
    try:
        cur = conn.cursor()
        cur.execute("SELECT pg_is_in_recovery()")
        result = cur.fetchone()[0]
        cur.close()
        conn.close()
        return result
    except:
        return None

def promote_replica(replica_host):
    """Promote replica to primary"""
    logger.info(f"Promoting {replica_host} to primary...")
    
    # Check split-brain prevention
    if cluster_state['lease_holder'] != cluster_state['primary']:
        logger.warning("Split-brain prevention: Lease holder mismatch!")
        cluster_state['split_brain_prevented'] += 1
        return False
    
    conn = get_connection(replica_host)
    if not conn:
        logger.error(f"Cannot connect to {replica_host} for promotion")
        return False
    
    try:
        # Promote using pg_promote
        cur = conn.cursor()
        cur.execute("SELECT pg_promote()")
        conn.commit()
        cur.close()
        conn.close()
        
        # Wait for promotion to complete
        time.sleep(3)
        
        # Verify promotion
        if not is_in_recovery(replica_host):
            logger.info(f"Successfully promoted {replica_host} to primary")
            old_primary = cluster_state['primary']
            cluster_state['primary'] = replica_host
            cluster_state['replicas'].remove(replica_host)
            if old_primary not in cluster_state['replicas']:
                cluster_state['replicas'].append(old_primary)
            cluster_state['lease_holder'] = replica_host
            cluster_state['last_failover'] = datetime.now().isoformat()
            return True
        else:
            logger.error(f"Promotion failed: {replica_host} still in recovery")
            return False
    except Exception as e:
        logger.error(f"Error promoting {replica_host}: {e}")
        return False

def perform_failover():
    """Perform automatic failover to best replica"""
    if cluster_state['failover_in_progress']:
        logger.warning("Failover already in progress")
        return False
    
    cluster_state['failover_in_progress'] = True
    logger.info("Starting automatic failover...")
    
    # Find replica with lowest lag
    best_replica = None
    min_lag = float('inf')
    
    for replica in cluster_state['replicas']:
        lag = check_replication_lag(replica)
        logger.info(f"{replica} replication lag: {lag:.2f}s")
        
        if lag < min_lag and lag < 10:  # Max acceptable lag: 10 seconds
            min_lag = lag
            best_replica = replica
    
    if best_replica:
        logger.info(f"Selected {best_replica} as new primary (lag: {min_lag:.2f}s)")
        success = promote_replica(best_replica)
        cluster_state['failover_in_progress'] = False
        return success
    else:
        logger.error("No suitable replica found for promotion")
        cluster_state['failover_in_progress'] = False
        return False

@app.route('/status', methods=['GET'])
def status():
    """Return cluster status"""
    return jsonify(cluster_state)

@app.route('/trigger_failover', methods=['POST'])
def trigger_failover():
    """Manually trigger failover"""
    success = perform_failover()
    return jsonify({'success': success, 'cluster_state': cluster_state})

@app.route('/failover_notification', methods=['POST'])
def failover_notification():
    """Receive failover notification from monitor"""
    data = request.json
    logger.info(f"Failover notification received: {data}")
    
    if data.get('action') == 'failover':
        success = perform_failover()
        return jsonify({'success': success})
    
    return jsonify({'success': False})

if __name__ == '__main__':
    time.sleep(10)  # Wait for databases to be ready
    logger.info("Orchestrator service started")
    app.run(host='0.0.0.0', port=5001)
