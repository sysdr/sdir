#!/bin/bash

# Two-Phase Commit Protocol - Complete Demo Setup
# This script creates a comprehensive demonstration of 2PC with multiple services,
# failure scenarios, and observability features.

set -e

echo "🚀 Setting up Two-Phase Commit Protocol Demo Environment"
echo "=================================================="

# Create project directory structure
PROJECT_NAME="two-phase-commit-demo"
mkdir -p $PROJECT_NAME
cd $PROJECT_NAME

echo "📁 Creating project structure..."
mkdir -p {coordinator,participant,monitoring,web-ui,scripts,logs}

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Transaction Coordinator
  coordinator:
    build: ./coordinator
    ports:
      - "8000:8000"
    environment:
      - PYTHONUNBUFFERED=1
      - LOG_LEVEL=DEBUG
    volumes:
      - ./logs:/app/logs
      - ./coordinator/data:/app/data
    networks:
      - transaction-network
    depends_on:
      - prometheus
    restart: unless-stopped

  # Payment Service (Participant 1)
  payment-service:
    build: ./participant
    ports:
      - "8001:8000"
    environment:
      - SERVICE_NAME=payment-service
      - SERVICE_PORT=8000
      - COORDINATOR_URL=http://coordinator:8000
      - FAILURE_RATE=0.1
      - PYTHONUNBUFFERED=1
    volumes:
      - ./logs:/app/logs
    networks:
      - transaction-network
    restart: unless-stopped

  # Inventory Service (Participant 2)
  inventory-service:
    build: ./participant
    ports:
      - "8002:8000"
    environment:
      - SERVICE_NAME=inventory-service
      - SERVICE_PORT=8000
      - COORDINATOR_URL=http://coordinator:8000
      - FAILURE_RATE=0.05
      - PYTHONUNBUFFERED=1
    volumes:
      - ./logs:/app/logs
    networks:
      - transaction-network
    restart: unless-stopped

  # Shipping Service (Participant 3)
  shipping-service:
    build: ./participant
    ports:
      - "8003:8000"
    environment:
      - SERVICE_NAME=shipping-service
      - SERVICE_PORT=8000
      - COORDINATOR_URL=http://coordinator:8000
      - FAILURE_RATE=0.15
      - PYTHONUNBUFFERED=1
    volumes:
      - ./logs:/app/logs
    networks:
      - transaction-network
    restart: unless-stopped

  # Web UI
  web-ui:
    build: ./web-ui
    ports:
      - "3000:3000"
    environment:
      - COORDINATOR_URL=http://coordinator:8000
    networks:
      - transaction-network
    depends_on:
      - coordinator
    restart: unless-stopped

  # Monitoring with Prometheus
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - transaction-network
    restart: unless-stopped

  # Grafana for visualization
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./monitoring/grafana:/var/lib/grafana
    networks:
      - transaction-network
    depends_on:
      - prometheus
    restart: unless-stopped

networks:
  transaction-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  prometheus-data:
  grafana-data:
EOF

# Create Transaction Coordinator Service
echo "🎯 Creating Transaction Coordinator Service..."
cat > coordinator/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["python", "coordinator.py"]
EOF

cat > coordinator/requirements.txt << 'EOF'
flask==3.0.0
flask-cors==4.0.0
requests==2.31.0
prometheus-client==0.19.0
pyyaml==6.0.1
asyncio==3.4.3
aiohttp==3.9.1
pydantic==2.5.0
structlog==23.2.0
EOF

cat > coordinator/coordinator.py << 'EOF'
#!/usr/bin/env python3
"""
Two-Phase Commit Protocol - Transaction Coordinator
Advanced implementation with comprehensive failure handling and observability
"""

import asyncio
import json
import logging
import os
import time
import uuid
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Set
import aiohttp
import structlog
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from dataclasses import dataclass, asdict
import threading
import pickle

# Configure structured logging
logging.basicConfig(level=logging.DEBUG)
logger = structlog.get_logger()

# Prometheus metrics
TRANSACTION_COUNTER = Counter('coordinator_transactions_total', 'Total transactions', ['outcome'])
TRANSACTION_DURATION = Histogram('coordinator_transaction_duration_seconds', 'Transaction duration')
PREPARE_DURATION = Histogram('coordinator_prepare_phase_duration_seconds', 'Prepare phase duration')
COMMIT_DURATION = Histogram('coordinator_commit_phase_duration_seconds', 'Commit phase duration')
ACTIVE_TRANSACTIONS = Gauge('coordinator_active_transactions', 'Active transactions')
PARTICIPANT_FAILURES = Counter('coordinator_participant_failures_total', 'Participant failures', ['participant', 'phase'])

class TransactionState(Enum):
    IDLE = "idle"
    PREPARING = "preparing"
    PREPARED = "prepared"
    COMMITTING = "committing"
    ABORTING = "aborting"
    COMMITTED = "committed"
    ABORTED = "aborted"

class Vote(Enum):
    PREPARED = "prepared"
    ABORT = "abort"

class Decision(Enum):
    COMMIT = "commit"
    ABORT = "abort"

@dataclass
class Participant:
    service_name: str
    url: str
    status: str = "active"
    last_seen: datetime = None
    response_time_ms: float = 0.0

@dataclass
class Transaction:
    transaction_id: str
    state: TransactionState
    participants: List[Participant]
    operation_data: Dict
    start_time: datetime
    prepare_votes: Dict[str, Vote]
    decision: Optional[Decision]
    commit_responses: Dict[str, bool]
    timeout: datetime
    recovery_attempts: int = 0

class TransactionLog:
    """Persistent transaction log for recovery"""
    
    def __init__(self, log_file="data/transaction_log.pkl"):
        self.log_file = log_file
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        self.transactions = self._load_log()
    
    def _load_log(self) -> Dict[str, Transaction]:
        try:
            if os.path.exists(self.log_file):
                with open(self.log_file, 'rb') as f:
                    return pickle.load(f)
        except Exception as e:
            logger.error("Failed to load transaction log", error=str(e))
        return {}
    
    def _save_log(self):
        try:
            with open(self.log_file, 'wb') as f:
                pickle.dump(self.transactions, f)
        except Exception as e:
            logger.error("Failed to save transaction log", error=str(e))
    
    def write_transaction(self, transaction: Transaction):
        self.transactions[transaction.transaction_id] = transaction
        self._save_log()
        logger.info("Transaction logged", transaction_id=transaction.transaction_id, state=transaction.state.value)
    
    def get_incomplete_transactions(self) -> List[Transaction]:
        return [t for t in self.transactions.values() 
                if t.state not in [TransactionState.COMMITTED, TransactionState.ABORTED]]

class TwoPhaseCommitCoordinator:
    def __init__(self):
        self.active_transactions: Dict[str, Transaction] = {}
        self.participant_registry: Dict[str, Participant] = {}
        self.transaction_log = TransactionLog()
        self.timeout_manager = TimeoutManager(self)
        self.recovery_manager = RecoveryManager(self)
        
        # Start background tasks
        self.timeout_manager.start()
        self.recovery_manager.start()
    
    async def register_participant(self, service_name: str, url: str) -> bool:
        """Register a new participant service"""
        try:
            # Health check the participant
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{url}/health", timeout=aiohttp.ClientTimeout(total=5)) as response:
                    if response.status == 200:
                        self.participant_registry[service_name] = Participant(
                            service_name=service_name,
                            url=url,
                            last_seen=datetime.now()
                        )
                        logger.info("Participant registered", service_name=service_name, url=url)
                        return True
        except Exception as e:
            logger.error("Failed to register participant", service_name=service_name, error=str(e))
        return False
    
    async def begin_transaction(self, participants: List[str], operation_data: Dict) -> str:
        """Begin a new distributed transaction"""
        transaction_id = str(uuid.uuid4())
        
        # Validate participants
        selected_participants = []
        for participant_name in participants:
            if participant_name in self.participant_registry:
                selected_participants.append(self.participant_registry[participant_name])
            else:
                raise ValueError(f"Unknown participant: {participant_name}")
        
        # Create transaction
        transaction = Transaction(
            transaction_id=transaction_id,
            state=TransactionState.IDLE,
            participants=selected_participants,
            operation_data=operation_data,
            start_time=datetime.now(),
            prepare_votes={},
            decision=None,
            commit_responses={},
            timeout=datetime.now() + timedelta(seconds=30)  # 30 second timeout
        )
        
        self.active_transactions[transaction_id] = transaction
        ACTIVE_TRANSACTIONS.set(len(self.active_transactions))
        
        logger.info("Transaction started", transaction_id=transaction_id, participants=participants)
        
        # Start transaction execution in background
        asyncio.create_task(self._execute_transaction(transaction))
        
        return transaction_id
    
    async def _execute_transaction(self, transaction: Transaction):
        """Execute the two-phase commit protocol"""
        try:
            with TRANSACTION_DURATION.time():
                # Phase 1: Prepare
                transaction.state = TransactionState.PREPARING
                self.transaction_log.write_transaction(transaction)
                
                success = await self._prepare_phase(transaction)
                
                if success:
                    # Phase 2: Commit
                    transaction.decision = Decision.COMMIT
                    transaction.state = TransactionState.COMMITTING
                    self.transaction_log.write_transaction(transaction)
                    
                    await self._commit_phase(transaction)
                    transaction.state = TransactionState.COMMITTED
                    TRANSACTION_COUNTER.labels(outcome='committed').inc()
                else:
                    # Phase 2: Abort
                    transaction.decision = Decision.ABORT
                    transaction.state = TransactionState.ABORTING
                    self.transaction_log.write_transaction(transaction)
                    
                    await self._abort_phase(transaction)
                    transaction.state = TransactionState.ABORTED
                    TRANSACTION_COUNTER.labels(outcome='aborted').inc()
                
                self.transaction_log.write_transaction(transaction)
                
        except Exception as e:
            logger.error("Transaction execution failed", 
                        transaction_id=transaction.transaction_id, error=str(e))
            transaction.state = TransactionState.ABORTED
            TRANSACTION_COUNTER.labels(outcome='error').inc()
        
        finally:
            # Cleanup
            self.active_transactions.pop(transaction.transaction_id, None)
            ACTIVE_TRANSACTIONS.set(len(self.active_transactions))
            
            logger.info("Transaction completed", 
                       transaction_id=transaction.transaction_id, 
                       state=transaction.state.value,
                       duration_ms=(datetime.now() - transaction.start_time).total_seconds() * 1000)
    
    async def _prepare_phase(self, transaction: Transaction) -> bool:
        """Phase 1: Send prepare requests to all participants"""
        logger.info("Starting prepare phase", transaction_id=transaction.transaction_id)
        
        with PREPARE_DURATION.time():
            tasks = []
            for participant in transaction.participants:
                task = self._send_prepare_request(transaction, participant)
                tasks.append(task)
            
            # Wait for all prepare responses
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Evaluate responses
            all_prepared = True
            for i, response in enumerate(responses):
                participant = transaction.participants[i]
                
                if isinstance(response, Exception):
                    logger.error("Prepare request failed", 
                               participant=participant.service_name, 
                               error=str(response))
                    transaction.prepare_votes[participant.service_name] = Vote.ABORT
                    PARTICIPANT_FAILURES.labels(participant=participant.service_name, phase='prepare').inc()
                    all_prepared = False
                elif response == Vote.PREPARED:
                    transaction.prepare_votes[participant.service_name] = Vote.PREPARED
                else:
                    transaction.prepare_votes[participant.service_name] = Vote.ABORT
                    all_prepared = False
            
            logger.info("Prepare phase completed", 
                       transaction_id=transaction.transaction_id, 
                       all_prepared=all_prepared,
                       votes=transaction.prepare_votes)
            
            return all_prepared
    
    async def _send_prepare_request(self, transaction: Transaction, participant: Participant) -> Vote:
        """Send prepare request to a participant"""
        try:
            prepare_data = {
                'transaction_id': transaction.transaction_id,
                'operation_data': transaction.operation_data
            }
            
            async with aiohttp.ClientSession() as session:
                start_time = time.time()
                async with session.post(
                    f"{participant.url}/prepare",
                    json=prepare_data,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    response_time = (time.time() - start_time) * 1000
                    participant.response_time_ms = response_time
                    participant.last_seen = datetime.now()
                    
                    if response.status == 200:
                        result = await response.json()
                        vote = Vote.PREPARED if result.get('vote') == 'prepared' else Vote.ABORT
                        logger.debug("Prepare response received", 
                                   participant=participant.service_name, 
                                   vote=vote.value,
                                   response_time_ms=response_time)
                        return vote
                    else:
                        logger.error("Prepare request failed", 
                                   participant=participant.service_name, 
                                   status=response.status)
                        return Vote.ABORT
                        
        except Exception as e:
            logger.error("Prepare request exception", 
                        participant=participant.service_name, error=str(e))
            return Vote.ABORT
    
    async def _commit_phase(self, transaction: Transaction):
        """Phase 2: Send commit requests to all participants"""
        logger.info("Starting commit phase", transaction_id=transaction.transaction_id)
        
        with COMMIT_DURATION.time():
            tasks = []
            for participant in transaction.participants:
                task = self._send_commit_request(transaction, participant)
                tasks.append(task)
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            for i, response in enumerate(responses):
                participant = transaction.participants[i]
                
                if isinstance(response, Exception):
                    logger.error("Commit request failed", 
                               participant=participant.service_name, 
                               error=str(response))
                    transaction.commit_responses[participant.service_name] = False
                    PARTICIPANT_FAILURES.labels(participant=participant.service_name, phase='commit').inc()
                else:
                    transaction.commit_responses[participant.service_name] = response
    
    async def _send_commit_request(self, transaction: Transaction, participant: Participant) -> bool:
        """Send commit request to a participant"""
        try:
            commit_data = {
                'transaction_id': transaction.transaction_id,
                'decision': 'commit'
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{participant.url}/commit",
                    json=commit_data,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    participant.last_seen = datetime.now()
                    return response.status == 200
                    
        except Exception as e:
            logger.error("Commit request exception", 
                        participant=participant.service_name, error=str(e))
            return False
    
    async def _abort_phase(self, transaction: Transaction):
        """Phase 2: Send abort requests to all participants"""
        logger.info("Starting abort phase", transaction_id=transaction.transaction_id)
        
        tasks = []
        for participant in transaction.participants:
            task = self._send_abort_request(transaction, participant)
            tasks.append(task)
        
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _send_abort_request(self, transaction: Transaction, participant: Participant) -> bool:
        """Send abort request to a participant"""
        try:
            abort_data = {
                'transaction_id': transaction.transaction_id,
                'decision': 'abort'
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{participant.url}/abort",
                    json=abort_data,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    participant.last_seen = datetime.now()
                    return response.status == 200
                    
        except Exception as e:
            logger.error("Abort request exception", 
                        participant=participant.service_name, error=str(e))
            return False
    
    def get_transaction_status(self, transaction_id: str) -> Optional[Dict]:
        """Get status of a transaction"""
        if transaction_id in self.active_transactions:
            transaction = self.active_transactions[transaction_id]
            return {
                'transaction_id': transaction_id,
                'state': transaction.state.value,
                'participants': [p.service_name for p in transaction.participants],
                'start_time': transaction.start_time.isoformat(),
                'prepare_votes': {k: v.value for k, v in transaction.prepare_votes.items()},
                'decision': transaction.decision.value if transaction.decision else None
            }
        
        # Check transaction log for completed transactions
        if transaction_id in self.transaction_log.transactions:
            transaction = self.transaction_log.transactions[transaction_id]
            return {
                'transaction_id': transaction_id,
                'state': transaction.state.value,
                'participants': [p.service_name for p in transaction.participants],
                'start_time': transaction.start_time.isoformat(),
                'prepare_votes': {k: v.value for k, v in transaction.prepare_votes.items()},
                'decision': transaction.decision.value if transaction.decision else None
            }
        
        return None
    
    def get_system_status(self) -> Dict:
        """Get overall system status"""
        return {
            'active_transactions': len(self.active_transactions),
            'registered_participants': len(self.participant_registry),
            'participants': {name: {
                'url': p.url,
                'status': p.status,
                'last_seen': p.last_seen.isoformat() if p.last_seen else None,
                'response_time_ms': p.response_time_ms
            } for name, p in self.participant_registry.items()}
        }

class TimeoutManager:
    """Manages transaction timeouts"""
    
    def __init__(self, coordinator):
        self.coordinator = coordinator
        self.running = False
    
    def start(self):
        self.running = True
        threading.Thread(target=self._timeout_worker, daemon=True).start()
    
    def _timeout_worker(self):
        while self.running:
            try:
                current_time = datetime.now()
                expired_transactions = []
                
                for tx_id, transaction in self.coordinator.active_transactions.items():
                    if current_time > transaction.timeout:
                        expired_transactions.append(transaction)
                
                for transaction in expired_transactions:
                    logger.warning("Transaction timeout", transaction_id=transaction.transaction_id)
                    asyncio.create_task(self._handle_timeout(transaction))
                
                time.sleep(1)  # Check every second
            except Exception as e:
                logger.error("Timeout manager error", error=str(e))
    
    async def _handle_timeout(self, transaction: Transaction):
        """Handle transaction timeout"""
        if transaction.state == TransactionState.PREPARING:
            # Timeout during prepare phase - abort transaction
            transaction.decision = Decision.ABORT
            transaction.state = TransactionState.ABORTING
            await self.coordinator._abort_phase(transaction)
            transaction.state = TransactionState.ABORTED
        elif transaction.state == TransactionState.COMMITTING:
            # Timeout during commit phase - retry commit
            transaction.recovery_attempts += 1
            if transaction.recovery_attempts < 3:
                logger.info("Retrying commit phase", transaction_id=transaction.transaction_id)
                await self.coordinator._commit_phase(transaction)
            else:
                logger.error("Max commit retries exceeded", transaction_id=transaction.transaction_id)
                transaction.state = TransactionState.ABORTED

class RecoveryManager:
    """Manages coordinator recovery after failures"""
    
    def __init__(self, coordinator):
        self.coordinator = coordinator
        self.running = False
    
    def start(self):
        self.running = True
        threading.Thread(target=self._recovery_worker, daemon=True).start()
    
    def _recovery_worker(self):
        """Recover incomplete transactions on startup"""
        incomplete_transactions = self.coordinator.transaction_log.get_incomplete_transactions()
        
        for transaction in incomplete_transactions:
            logger.info("Recovering transaction", transaction_id=transaction.transaction_id)
            asyncio.create_task(self._recover_transaction(transaction))
    
    async def _recover_transaction(self, transaction: Transaction):
        """Recover a specific transaction"""
        try:
            if transaction.state == TransactionState.PREPARING:
                # Abort transactions stuck in prepare phase
                transaction.decision = Decision.ABORT
                transaction.state = TransactionState.ABORTING
                await self.coordinator._abort_phase(transaction)
                transaction.state = TransactionState.ABORTED
            elif transaction.state == TransactionState.COMMITTING:
                # Retry commit for transactions stuck in commit phase
                await self.coordinator._commit_phase(transaction)
                transaction.state = TransactionState.COMMITTED
            elif transaction.state == TransactionState.ABORTING:
                # Complete abort for transactions stuck in abort phase
                await self.coordinator._abort_phase(transaction)
                transaction.state = TransactionState.ABORTED
            
            self.coordinator.transaction_log.write_transaction(transaction)
            logger.info("Transaction recovered", 
                       transaction_id=transaction.transaction_id, 
                       final_state=transaction.state.value)
        
        except Exception as e:
            logger.error("Transaction recovery failed", 
                        transaction_id=transaction.transaction_id, 
                        error=str(e))

# Flask REST API
app = Flask(__name__)
coordinator = TwoPhaseCommitCoordinator()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'service': 'coordinator'})

@app.route('/register', methods=['POST'])
def register_participant():
    data = request.json
    service_name = data.get('service_name')
    url = data.get('url')
    
    if not service_name or not url:
        return jsonify({'error': 'Missing service_name or url'}), 400
    
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    success = loop.run_until_complete(coordinator.register_participant(service_name, url))
    loop.close()
    
    if success:
        return jsonify({'message': 'Participant registered successfully'})
    else:
        return jsonify({'error': 'Failed to register participant'}), 500

@app.route('/transaction', methods=['POST'])
def begin_transaction():
    data = request.json
    participants = data.get('participants', [])
    operation_data = data.get('operation_data', {})
    
    if not participants:
        return jsonify({'error': 'No participants specified'}), 400
    
    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        transaction_id = loop.run_until_complete(
            coordinator.begin_transaction(participants, operation_data)
        )
        loop.close()
        
        return jsonify({'transaction_id': transaction_id})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/transaction/<transaction_id>', methods=['GET'])
def get_transaction_status(transaction_id):
    status = coordinator.get_transaction_status(transaction_id)
    if status:
        return jsonify(status)
    else:
        return jsonify({'error': 'Transaction not found'}), 404

@app.route('/status', methods=['GET'])
def get_system_status():
    return jsonify(coordinator.get_system_status())

@app.route('/metrics', methods=['GET'])
def get_metrics():
    return generate_latest()

if __name__ == '__main__':
    print("🎯 Starting Two-Phase Commit Coordinator...")
    print("📊 Metrics available at: http://localhost:8000/metrics")
    print("🔍 System status at: http://localhost:8000/status")
    
    app.run(host='0.0.0.0', port=8000, debug=False)
EOF

# Create Participant Service
echo "⚡ Creating Participant Services..."
cat > participant/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["python", "participant.py"]
EOF

cat > participant/requirements.txt << 'EOF'
flask==3.0.0
flask-cors==4.0.0
requests==2.31.0
prometheus-client==0.19.0
structlog==23.2.0
pydantic==2.5.0
EOF

cat > participant/participant.py << 'EOF'
#!/usr/bin/env python3
"""
Two-Phase Commit Protocol - Participant Service
Simulates various business services (payment, inventory, shipping)
"""

import json
import logging
import os
import random
import time
import uuid
from datetime import datetime
from enum import Enum
from typing import Dict, Optional
import structlog
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, generate_latest
import requests
import threading

# Configure structured logging
logging.basicConfig(level=logging.DEBUG)
logger = structlog.get_logger()

# Prometheus metrics
PREPARE_REQUESTS = Counter('participant_prepare_requests_total', 'Total prepare requests')
COMMIT_REQUESTS = Counter('participant_commit_requests_total', 'Total commit requests')
ABORT_REQUESTS = Counter('participant_abort_requests_total', 'Total abort requests')
OPERATION_DURATION = Histogram('participant_operation_duration_seconds', 'Operation duration')
FAILURE_INJECTIONS = Counter('participant_failure_injections_total', 'Injected failures', ['type'])

class ParticipantState(Enum):
    IDLE = "idle"
    PREPARED = "prepared"
    COMMITTED = "committed"
    ABORTED = "aborted"

class TransactionContext:
    def __init__(self, transaction_id: str, operation_data: Dict):
        self.transaction_id = transaction_id
        self.operation_data = operation_data
        self.state = ParticipantState.IDLE
        self.prepared_at = None
        self.locks_held = []
        self.backup_data = {}

class BusinessService:
    """Simulates a business service with realistic behavior"""
    
    def __init__(self, service_name: str):
        self.service_name = service_name
        self.failure_rate = float(os.getenv('FAILURE_RATE', '0.1'))
        self.processing_delay_ms = random.randint(50, 200)
        self.resource_locks = {}
        self.data_store = {}
        
        # Initialize service-specific data
        self._initialize_service_data()
    
    def _initialize_service_data(self):
        """Initialize service-specific data based on service type"""
        if 'payment' in self.service_name.lower():
            self.data_store = {
                'account_balance': 10000.0,
                'pending_charges': {},
                'transaction_history': []
            }
        elif 'inventory' in self.service_name.lower():
            self.data_store = {
                'product_stock': {'laptop': 50, 'phone': 100, 'tablet': 25},
                'reserved_items': {},
                'pending_updates': {}
            }
        elif 'shipping' in self.service_name.lower():
            self.data_store = {
                'shipping_orders': {},
                'pending_shipments': {},
                'carrier_capacity': 1000
            }
    
    def prepare_operation(self, transaction_id: str, operation_data: Dict) -> bool:
        """Prepare phase - lock resources and validate operation"""
        logger.info("Preparing operation", 
                   transaction_id=transaction_id, 
                   service=self.service_name,
                   operation_data=operation_data)
        
        # Simulate processing delay
        time.sleep(self.processing_delay_ms / 1000.0)
        
        # Inject random failures
        if random.random() < self.failure_rate:
            failure_type = random.choice(['network', 'resource', 'validation'])
            FAILURE_INJECTIONS.labels(type=failure_type).inc()
            logger.warning("Injected failure during prepare", 
                         transaction_id=transaction_id,
                         failure_type=failure_type)
            return False
        
        # Service-specific prepare logic
        try:
            if 'payment' in self.service_name.lower():
                return self._prepare_payment(transaction_id, operation_data)
            elif 'inventory' in self.service_name.lower():
                return self._prepare_inventory(transaction_id, operation_data)
            elif 'shipping' in self.service_name.lower():
                return self._prepare_shipping(transaction_id, operation_data)
            else:
                return True
        except Exception as e:
            logger.error("Prepare operation failed", 
                        transaction_id=transaction_id, 
                        error=str(e))
            return False
    
    def _prepare_payment(self, transaction_id: str, operation_data: Dict) -> bool:
        """Prepare payment operation"""
        amount = operation_data.get('amount', 0)
        if amount <= 0:
            return False
        
        if self.data_store['account_balance'] < amount:
            logger.warning("Insufficient balance", 
                         transaction_id=transaction_id,
                         required=amount, 
                         available=self.data_store['account_balance'])
            return False
        
        # Reserve the amount
        self.data_store['pending_charges'][transaction_id] = amount
        self.data_store['account_balance'] -= amount
        logger.info("Payment prepared", transaction_id=transaction_id, amount=amount)
        return True
    
    def _prepare_inventory(self, transaction_id: str, operation_data: Dict) -> bool:
        """Prepare inventory operation"""
        product = operation_data.get('product', 'laptop')
        quantity = operation_data.get('quantity', 1)
        
        if product not in self.data_store['product_stock']:
            return False
        
        if self.data_store['product_stock'][product] < quantity:
            logger.warning("Insufficient inventory", 
                         transaction_id=transaction_id,
                         product=product, 
                         required=quantity,
                         available=self.data_store['product_stock'][product])
            return False
        
        # Reserve inventory
        self.data_store['reserved_items'][transaction_id] = {
            'product': product, 
            'quantity': quantity
        }
        self.data_store['product_stock'][product] -= quantity
        logger.info("Inventory prepared", 
                   transaction_id=transaction_id, 
                   product=product, 
                   quantity=quantity)
        return True
    
    def _prepare_shipping(self, transaction_id: str, operation_data: Dict) -> bool:
        """Prepare shipping operation"""
        address = operation_data.get('shipping_address', 'Default Address')
        
        if self.data_store['carrier_capacity'] <= 0:
            logger.warning("No shipping capacity", transaction_id=transaction_id)
            return False
        
        # Reserve shipping capacity
        self.data_store['pending_shipments'][transaction_id] = {
            'address': address,
            'status': 'prepared'
        }
        self.data_store['carrier_capacity'] -= 1
        logger.info("Shipping prepared", transaction_id=transaction_id, address=address)
        return True
    
    def commit_operation(self, transaction_id: str) -> bool:
        """Commit phase - make changes permanent"""
        logger.info("Committing operation", 
                   transaction_id=transaction_id, 
                   service=self.service_name)
        
        try:
            if 'payment' in self.service_name.lower():
                return self._commit_payment(transaction_id)
            elif 'inventory' in self.service_name.lower():
                return self._commit_inventory(transaction_id)
            elif 'shipping' in self.service_name.lower():
                return self._commit_shipping(transaction_id)
            else:
                return True
        except Exception as e:
            logger.error("Commit operation failed", 
                        transaction_id=transaction_id, 
                        error=str(e))
            return False
    
    def _commit_payment(self, transaction_id: str) -> bool:
        """Commit payment operation"""
        if transaction_id in self.data_store['pending_charges']:
            amount = self.data_store['pending_charges'].pop(transaction_id)
            self.data_store['transaction_history'].append({
                'transaction_id': transaction_id,
                'amount': amount,
                'timestamp': datetime.now().isoformat(),
                'status': 'committed'
            })
            logger.info("Payment committed", transaction_id=transaction_id, amount=amount)
            return True
        return False
    
    def _commit_inventory(self, transaction_id: str) -> bool:
        """Commit inventory operation"""
        if transaction_id in self.data_store['reserved_items']:
            item_info = self.data_store['reserved_items'].pop(transaction_id)
            logger.info("Inventory committed", 
                       transaction_id=transaction_id, 
                       item_info=item_info)
            return True
        return False
    
    def _commit_shipping(self, transaction_id: str) -> bool:
        """Commit shipping operation"""
        if transaction_id in self.data_store['pending_shipments']:
            shipment = self.data_store['pending_shipments'].pop(transaction_id)
            shipment['status'] = 'committed'
            shipment['tracking_number'] = f"TRK-{uuid.uuid4().hex[:8].upper()}"
            self.data_store['shipping_orders'][transaction_id] = shipment
            logger.info("Shipping committed", 
                       transaction_id=transaction_id, 
                       tracking=shipment['tracking_number'])
            return True
        return False
    
    def abort_operation(self, transaction_id: str) -> bool:
        """Abort phase - rollback changes"""
        logger.info("Aborting operation", 
                   transaction_id=transaction_id, 
                   service=self.service_name)
        
        try:
            if 'payment' in self.service_name.lower():
                return self._abort_payment(transaction_id)
            elif 'inventory' in self.service_name.lower():
                return self._abort_inventory(transaction_id)
            elif 'shipping' in self.service_name.lower():
                return self._abort_shipping(transaction_id)
            else:
                return True
        except Exception as e:
            logger.error("Abort operation failed", 
                        transaction_id=transaction_id, 
                        error=str(e))
            return False
    
    def _abort_payment(self, transaction_id: str) -> bool:
        """Abort payment operation"""
        if transaction_id in self.data_store['pending_charges']:
            amount = self.data_store['pending_charges'].pop(transaction_id)
            self.data_store['account_balance'] += amount  # Refund
            logger.info("Payment aborted", transaction_id=transaction_id, refunded=amount)
            return True
        return False
    
    def _abort_inventory(self, transaction_id: str) -> bool:
        """Abort inventory operation"""
        if transaction_id in self.data_store['reserved_items']:
            item_info = self.data_store['reserved_items'].pop(transaction_id)
            # Restore inventory
            product = item_info['product']
            quantity = item_info['quantity']
            self.data_store['product_stock'][product] += quantity
            logger.info("Inventory aborted", 
                       transaction_id=transaction_id, 
                       restored=item_info)
            return True
        return False
    
    def _abort_shipping(self, transaction_id: str) -> bool:
        """Abort shipping operation"""
        if transaction_id in self.data_store['pending_shipments']:
            self.data_store['pending_shipments'].pop(transaction_id)
            self.data_store['carrier_capacity'] += 1  # Restore capacity
            logger.info("Shipping aborted", transaction_id=transaction_id)
            return True
        return False
    
    def get_status(self) -> Dict:
        """Get service status"""
        return {
            'service_name': self.service_name,
            'failure_rate': self.failure_rate,
            'data_store': self.data_store,
            'processing_delay_ms': self.processing_delay_ms
        }

class ParticipantService:
    def __init__(self):
        self.service_name = os.getenv('SERVICE_NAME', 'participant-service')
        self.coordinator_url = os.getenv('COORDINATOR_URL', 'http://coordinator:8000')
        self.business_service = BusinessService(self.service_name)
        self.active_transactions: Dict[str, TransactionContext] = {}
        
        # Register with coordinator
        self._register_with_coordinator()
    
    def _register_with_coordinator(self):
        """Register this participant with the coordinator"""
        def register():
            time.sleep(2)  # Wait for coordinator to start
            try:
                registration_data = {
                    'service_name': self.service_name,
                    'url': f'http://{self.service_name}:8000'
                }
                
                response = requests.post(
                    f'{self.coordinator_url}/register',
                    json=registration_data,
                    timeout=10
                )
                
                if response.status_code == 200:
                    logger.info("Successfully registered with coordinator", 
                               service_name=self.service_name)
                else:
                    logger.error("Failed to register with coordinator", 
                               status_code=response.status_code)
            except Exception as e:
                logger.error("Registration failed", error=str(e))
        
        threading.Thread(target=register, daemon=True).start()
    
    def prepare(self, transaction_id: str, operation_data: Dict) -> bool:
        """Handle prepare request from coordinator"""
        PREPARE_REQUESTS.inc()
        
        with OPERATION_DURATION.time():
            # Check if transaction already exists
            if transaction_id in self.active_transactions:
                logger.warning("Transaction already exists", 
                             transaction_id=transaction_id)
                return False
            
            # Create transaction context
            tx_context = TransactionContext(transaction_id, operation_data)
            self.active_transactions[transaction_id] = tx_context
            
            # Prepare the operation
            success = self.business_service.prepare_operation(transaction_id, operation_data)
            
            if success:
                tx_context.state = ParticipantState.PREPARED
                tx_context.prepared_at = datetime.now()
                logger.info("Transaction prepared successfully", 
                           transaction_id=transaction_id)
                return True
            else:
                # Cleanup on failure
                self.active_transactions.pop(transaction_id, None)
                logger.warning("Transaction prepare failed", 
                             transaction_id=transaction_id)
                return False
    
    def commit(self, transaction_id: str) -> bool:
        """Handle commit request from coordinator"""
        COMMIT_REQUESTS.inc()
        
        if transaction_id not in self.active_transactions:
            logger.error("Unknown transaction for commit", 
                        transaction_id=transaction_id)
            return False
        
        tx_context = self.active_transactions[transaction_id]
        
        if tx_context.state != ParticipantState.PREPARED:
            logger.error("Invalid state for commit", 
                        transaction_id=transaction_id, 
                        state=tx_context.state.value)
            return False
        
        success = self.business_service.commit_operation(transaction_id)
        
        if success:
            tx_context.state = ParticipantState.COMMITTED
            logger.info("Transaction committed successfully", 
                       transaction_id=transaction_id)
        else:
            logger.error("Transaction commit failed", 
                        transaction_id=transaction_id)
        
        # Cleanup transaction context
        self.active_transactions.pop(transaction_id, None)
        return success
    
    def abort(self, transaction_id: str) -> bool:
        """Handle abort request from coordinator"""
        ABORT_REQUESTS.inc()
        
        if transaction_id not in self.active_transactions:
            logger.warning("Unknown transaction for abort", 
                          transaction_id=transaction_id)
            return True  # Abort is idempotent
        
        tx_context = self.active_transactions[transaction_id]
        
        success = self.business_service.abort_operation(transaction_id)
        
        if success:
            tx_context.state = ParticipantState.ABORTED
            logger.info("Transaction aborted successfully", 
                       transaction_id=transaction_id)
        else:
            logger.error("Transaction abort failed", 
                        transaction_id=transaction_id)
        
        # Cleanup transaction context
        self.active_transactions.pop(transaction_id, None)
        return success
    
    def get_status(self) -> Dict:
        """Get participant status"""
        return {
            'service_name': self.service_name,
            'coordinator_url': self.coordinator_url,
            'active_transactions': len(self.active_transactions),
            'business_service_status': self.business_service.get_status(),
            'transactions': {
                tx_id: {
                    'state': tx.state.value,
                    'prepared_at': tx.prepared_at.isoformat() if tx.prepared_at else None
                } for tx_id, tx in self.active_transactions.items()
            }
        }

# Flask REST API
app = Flask(__name__)
participant_service = ParticipantService()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy', 
        'service': participant_service.service_name
    })

@app.route('/prepare', methods=['POST'])
def prepare():
    data = request.json
    transaction_id = data.get('transaction_id')
    operation_data = data.get('operation_data', {})
    
    if not transaction_id:
        return jsonify({'error': 'Missing transaction_id'}), 400
    
    success = participant_service.prepare(transaction_id, operation_data)
    
    if success:
        return jsonify({'vote': 'prepared', 'transaction_id': transaction_id})
    else:
        return jsonify({'vote': 'abort', 'transaction_id': transaction_id}), 200

@app.route('/commit', methods=['POST'])
def commit():
    data = request.json
    transaction_id = data.get('transaction_id')
    
    if not transaction_id:
        return jsonify({'error': 'Missing transaction_id'}), 400
    
    success = participant_service.commit(transaction_id)
    
    if success:
        return jsonify({'status': 'committed', 'transaction_id': transaction_id})
    else:
        return jsonify({'error': 'Commit failed'}), 500

@app.route('/abort', methods=['POST'])
def abort():
    data = request.json
    transaction_id = data.get('transaction_id')
    
    if not transaction_id:
        return jsonify({'error': 'Missing transaction_id'}), 400
    
    success = participant_service.abort(transaction_id)
    
    if success:
        return jsonify({'status': 'aborted', 'transaction_id': transaction_id})
    else:
        return jsonify({'error': 'Abort failed'}), 500

@app.route('/status', methods=['GET'])
def get_status():
    return jsonify(participant_service.get_status())

@app.route('/metrics', methods=['GET'])
def get_metrics():
    return generate_latest()

if __name__ == '__main__':
    print(f"⚡ Starting {participant_service.service_name}...")
    print(f"📊 Metrics available at: http://localhost:8000/metrics")
    print(f"🔍 Status at: http://localhost:8000/status")
    
    app.run(host='0.0.0.0', port=8000, debug=False)
EOF

# Create Web UI
echo "🌐 Creating Web UI..."
cat > web-ui/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN mkdir -p /app/views && ls -la /app/views/

EXPOSE 3000

CMD ["npm", "start"]
EOF

cat > web-ui/package.json << 'EOF'
{
  "name": "two-phase-commit-ui",
  "version": "1.0.0",
  "description": "Web UI for Two-Phase Commit Demo",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "ejs": "^3.1.9"
  }
}
EOF

cat > web-ui/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const path = require('path');

const app = express();
const port = 3000;

const COORDINATOR_URL = process.env.COORDINATOR_URL || 'http://coordinator:8000';

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static('public'));
app.use(express.json());

// Home page
app.get('/', async (req, res) => {
    try {
        const statusResponse = await axios.get(`${COORDINATOR_URL}/status`);
        const systemStatus = statusResponse.data;
        
        res.render('index', { 
            systemStatus,
            coordinatorUrl: COORDINATOR_URL
        });
    } catch (error) {
        res.render('index', { 
            systemStatus: { error: 'Cannot connect to coordinator' },
            coordinatorUrl: COORDINATOR_URL
        });
    }
});

// Start transaction
app.post('/transaction', async (req, res) => {
    try {
        const transactionData = {
            participants: req.body.participants || ['payment-service', 'inventory-service', 'shipping-service'],
            operation_data: req.body.operation_data || {
                amount: 100,
                product: 'laptop',
                quantity: 1,
                shipping_address: '123 Main St, City, State'
            }
        };
        
        const response = await axios.post(`${COORDINATOR_URL}/transaction`, transactionData);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get transaction status
app.get('/transaction/:id', async (req, res) => {
    try {
        const response = await axios.get(`${COORDINATOR_URL}/transaction/${req.params.id}`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get system status
app.get('/api/status', async (req, res) => {
    try {
        const response = await axios.get(`${COORDINATOR_URL}/status`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(port, '0.0.0.0', () => {
    console.log(`🌐 Two-Phase Commit UI running at http://localhost:${port}`);
});
EOF

mkdir -p web-ui/views web-ui/public

cat > web-ui/views/index.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Two-Phase Commit Protocol Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .main-content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 30px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 10px;
            border-left: 5px solid #667eea;
        }
        
        .section h2 {
            color: #333;
            margin-bottom: 20px;
            font-size: 1.5em;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            border: 1px solid #e9ecef;
        }
        
        .card h3 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        
        .status-healthy { background-color: #28a745; }
        .status-error { background-color: #dc3545; }
        .status-warning { background-color: #ffc107; }
        
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 25px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 1em;
            transition: all 0.3s ease;
            margin: 5px;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        
        .btn-danger {
            background: linear-gradient(135deg, #dc3545 0%, #c82333 100%);
        }
        
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #1e7e34 100%);
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
            color: #555;
        }
        
        .form-group input,
        .form-group textarea,
        .form-group select {
            width: 100%;
            padding: 12px;
            border: 2px solid #e9ecef;
            border-radius: 8px;
            font-size: 1em;
            transition: border-color 0.3s ease;
        }
        
        .form-group input:focus,
        .form-group textarea:focus,
        .form-group select:focus {
            outline: none;
            border-color: #667eea;
        }
        
        .transaction-log {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            max-height: 300px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        
        .log-entry {
            margin-bottom: 8px;
            padding: 8px;
            border-radius: 4px;
        }
        
        .log-success { background-color: #d4edda; color: #155724; }
        .log-error { background-color: #f8d7da; color: #721c24; }
        .log-info { background-color: #d1ecf1; color: #0c5460; }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid #e9ecef;
        }
        
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 5px;
        }
        
        .metric-label {
            color: #6c757d;
            font-size: 0.9em;
        }
        
        .real-time-updates {
            position: fixed;
            top: 20px;
            right: 20px;
            background: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            border: 2px solid #667eea;
            max-width: 300px;
        }
        
        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }
            
            .real-time-updates {
                position: static;
                margin: 20px 0;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎯 Two-Phase Commit Protocol</h1>
            <p>Interactive Demo & Monitoring Dashboard</p>
        </div>
        
        <div class="main-content">
            <!-- System Status -->
            <div class="section">
                <h2>📊 System Status</h2>
                <div class="grid">
                    <div class="card">
                        <h3>Coordinator Status</h3>
                        <div id="coordinator-status">
                            <span class="status-indicator <%= systemStatus.error ? 'status-error' : 'status-healthy' %>"></span>
                            <%= systemStatus.error || 'Healthy' %>
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Active Transactions</h3>
                        <div class="metric-value" id="active-transactions">
                            <%= systemStatus.active_transactions || 0 %>
                        </div>
                        <div class="metric-label">Currently Running</div>
                    </div>
                    
                    <div class="card">
                        <h3>Registered Participants</h3>
                        <div class="metric-value" id="participant-count">
                            <%= systemStatus.registered_participants || 0 %>
                        </div>
                        <div class="metric-label">Services Available</div>
                    </div>
                </div>
                
                <% if (systemStatus.participants) { %>
                <h3>Participant Services</h3>
                <div class="grid">
                    <% Object.entries(systemStatus.participants).forEach(([name, info]) => { %>
                    <div class="card">
                        <h4><%= name %></h4>
                        <p><strong>URL:</strong> <%= info.url %></p>
                        <p><strong>Status:</strong> 
                            <span class="status-indicator <%= info.status === 'active' ? 'status-healthy' : 'status-error' %>"></span>
                            <%= info.status %>
                        </p>
                        <% if (info.last_seen) { %>
                        <p><strong>Last Seen:</strong> <%= new Date(info.last_seen).toLocaleString() %></p>
                        <% } %>
                        <% if (info.response_time_ms) { %>
                        <p><strong>Response Time:</strong> <%= Math.round(info.response_time_ms) %>ms</p>
                        <% } %>
                    </div>
                    <% }); %>
                </div>
                <% } %>
            </div>
            
            <!-- Transaction Control -->
            <div class="section">
                <h2>🚀 Start New Transaction</h2>
                <div class="grid">
                    <div class="card">
                        <h3>Transaction Configuration</h3>
                        <form id="transaction-form">
                            <div class="form-group">
                                <label>Participants</label>
                                <select id="participants" multiple>
                                    <option value="payment-service" selected>Payment Service</option>
                                    <option value="inventory-service" selected>Inventory Service</option>
                                    <option value="shipping-service" selected>Shipping Service</option>
                                </select>
                            </div>
                            
                            <div class="form-group">
                                <label>Purchase Amount ($)</label>
                                <input type="number" id="amount" value="150" min="1" max="10000">
                            </div>
                            
                            <div class="form-group">
                                <label>Product</label>
                                <select id="product">
                                    <option value="laptop">Laptop</option>
                                    <option value="phone">Phone</option>
                                    <option value="tablet">Tablet</option>
                                </select>
                            </div>
                            
                            <div class="form-group">
                                <label>Quantity</label>
                                <input type="number" id="quantity" value="1" min="1" max="10">
                            </div>
                            
                            <div class="form-group">
                                <label>Shipping Address</label>
                                <textarea id="shipping-address" rows="3">123 Main Street, Anytown, ST 12345</textarea>
                            </div>
                            
                            <button type="submit" class="btn">Start Transaction</button>
                        </form>
                    </div>
                    
                    <div class="card">
                        <h3>Test Scenarios</h3>
                        <button class="btn btn-success" onclick="runSuccessScenario()">✅ Success Scenario</button>
                        <button class="btn btn-danger" onclick="runFailureScenario()">❌ Failure Scenario</button>
                        <button class="btn" onclick="runStressTest()">⚡ Stress Test</button>
                        <button class="btn" onclick="simulateNetworkPartition()">🌐 Network Partition</button>
                    </div>
                </div>
            </div>
            
            <!-- Transaction Monitor -->
            <div class="section">
                <h2>📈 Transaction Monitor</h2>
                <div class="grid">
                    <div class="card">
                        <h3>Recent Transactions</h3>
                        <div id="transaction-list">
                            <!-- Populated by JavaScript -->
                        </div>
                    </div>
                    
                    <div class="card">
                        <h3>Transaction Details</h3>
                        <div id="transaction-details">
                            <p>Select a transaction to view details</p>
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <h3>Live Transaction Log</h3>
                    <div id="transaction-log" class="transaction-log">
                        <!-- Live updates will appear here -->
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="real-time-updates">
        <h4>🔄 Real-time Updates</h4>
        <div id="live-status">
            System monitoring active...
        </div>
    </div>

    <script>
        let transactionHistory = [];
        let activeTransactions = new Map();
        
        // Form submission
        document.getElementById('transaction-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const participants = Array.from(document.getElementById('participants').selectedOptions)
                .map(option => option.value);
            
            const operationData = {
                amount: parseFloat(document.getElementById('amount').value),
                product: document.getElementById('product').value,
                quantity: parseInt(document.getElementById('quantity').value),
                shipping_address: document.getElementById('shipping-address').value
            };
            
            try {
                addLogEntry('info', `Starting transaction with participants: ${participants.join(', ')}`);
                
                const response = await fetch('/transaction', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        participants: participants,
                        operation_data: operationData
                    })
                });
                
                const result = await response.json();
                
                if (response.ok) {
                    addLogEntry('success', `Transaction started: ${result.transaction_id}`);
                    monitorTransaction(result.transaction_id);
                } else {
                    addLogEntry('error', `Failed to start transaction: ${result.error}`);
                }
            } catch (error) {
                addLogEntry('error', `Network error: ${error.message}`);
            }
        });
        
        // Monitor transaction progress
        async function monitorTransaction(transactionId) {
            activeTransactions.set(transactionId, { id: transactionId, startTime: Date.now() });
            updateTransactionList();
            
            const maxAttempts = 60; // 30 seconds with 500ms intervals
            let attempts = 0;
            
            const monitor = async () => {
                try {
                    const response = await fetch(`/transaction/${transactionId}`);
                    const status = await response.json();
                    
                    if (response.ok) {
                        activeTransactions.set(transactionId, {
                            ...activeTransactions.get(transactionId),
                            ...status
                        });
                        
                        updateTransactionDetails(status);
                        addLogEntry('info', `Transaction ${transactionId}: ${status.state}`);
                        
                        if (status.state === 'committed' || status.state === 'aborted') {
                            const finalStatus = status.state === 'committed' ? 'success' : 'error';
                            addLogEntry(finalStatus, `Transaction ${transactionId} ${status.state}`);
                            
                            // Move to history
                            transactionHistory.unshift({
                                ...status,
                                completedAt: Date.now()
                            });
                            activeTransactions.delete(transactionId);
                            updateTransactionList();
                            return;
                        }
                    }
                    
                    attempts++;
                    if (attempts < maxAttempts) {
                        setTimeout(monitor, 500);
                    } else {
                        addLogEntry('error', `Transaction ${transactionId} monitoring timeout`);
                        activeTransactions.delete(transactionId);
                        updateTransactionList();
                    }
                } catch (error) {
                    addLogEntry('error', `Monitoring error for ${transactionId}: ${error.message}`);
                }
            };
            
            monitor();
        }
        
        function updateTransactionList() {
            const listElement = document.getElementById('transaction-list');
            const activeList = Array.from(activeTransactions.values());
            const recentHistory = transactionHistory.slice(0, 10);
            
            listElement.innerHTML = `
                ${activeList.length > 0 ? `
                    <h4>Active (${activeList.length})</h4>
                    ${activeList.map(tx => `
                        <div class="log-entry log-info" onclick="showTransactionDetails('${tx.id}')">
                            <strong>${tx.id.substring(0, 8)}...</strong><br>
                            State: ${tx.state || 'starting'}<br>
                            Duration: ${Math.round((Date.now() - tx.startTime) / 1000)}s
                        </div>
                    `).join('')}
                ` : ''}
                
                ${recentHistory.length > 0 ? `
                    <h4>Recent History</h4>
                    ${recentHistory.map(tx => `
                        <div class="log-entry ${tx.state === 'committed' ? 'log-success' : 'log-error'}" 
                             onclick="showTransactionDetails('${tx.transaction_id}')">
                            <strong>${tx.transaction_id.substring(0, 8)}...</strong><br>
                            ${tx.state.toUpperCase()}<br>
                            ${new Date(tx.completedAt).toLocaleTimeString()}
                        </div>
                    `).join('')}
                ` : ''}
            `;
        }
        
        function showTransactionDetails(transactionId) {
            const tx = activeTransactions.get(transactionId) || 
                      transactionHistory.find(t => t.transaction_id === transactionId);
            
            if (!tx) return;
            
            const detailsElement = document.getElementById('transaction-details');
            detailsElement.innerHTML = `
                <h4>Transaction: ${transactionId.substring(0, 8)}...</h4>
                <p><strong>State:</strong> ${tx.state || 'starting'}</p>
                <p><strong>Participants:</strong> ${tx.participants ? tx.participants.join(', ') : 'N/A'}</p>
                ${tx.prepare_votes ? `
                    <p><strong>Prepare Votes:</strong></p>
                    <ul>
                        ${Object.entries(tx.prepare_votes).map(([participant, vote]) => 
                            `<li>${participant}: ${vote}</li>`
                        ).join('')}
                    </ul>
                ` : ''}
                ${tx.decision ? `<p><strong>Decision:</strong> ${tx.decision}</p>` : ''}
                ${tx.start_time ? `<p><strong>Started:</strong> ${new Date(tx.start_time).toLocaleString()}</p>` : ''}
            `;
        }
        
        function updateTransactionDetails(status) {
            showTransactionDetails(status.transaction_id);
        }
        
        function addLogEntry(type, message) {
            const logElement = document.getElementById('transaction-log');
            const timestamp = new Date().toLocaleTimeString();
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            entry.innerHTML = `[${timestamp}] ${message}`;
            
            logElement.insertBefore(entry, logElement.firstChild);
            
            // Keep only last 50 entries
            while (logElement.children.length > 50) {
                logElement.removeChild(logElement.lastChild);
            }
        }
        
        // Test scenarios
        async function runSuccessScenario() {
            addLogEntry('info', 'Running success scenario...');
            document.getElementById('amount').value = '50';
            document.getElementById('quantity').value = '1';
            document.getElementById('transaction-form').dispatchEvent(new Event('submit'));
        }
        
        async function runFailureScenario() {
            addLogEntry('info', 'Running failure scenario (high amount to trigger insufficient funds)...');
            document.getElementById('amount').value = '99999';
            document.getElementById('quantity').value = '100';
            document.getElementById('transaction-form').dispatchEvent(new Event('submit'));
        }
        
        async function runStressTest() {
            addLogEntry('info', 'Running stress test (10 concurrent transactions)...');
            for (let i = 0; i < 10; i++) {
                setTimeout(() => {
                    document.getElementById('amount').value = Math.floor(Math.random() * 500) + 50;
                    document.getElementById('quantity').value = Math.floor(Math.random() * 3) + 1;
                    document.getElementById('transaction-form').dispatchEvent(new Event('submit'));
                }, i * 100);
            }
        }
        
        async function simulateNetworkPartition() {
            addLogEntry('info', 'Simulating network partition (this would require external tools in real deployment)...');
            alert('Network partition simulation requires Docker network tools. Check the demo script for implementation.');
        }
        
        // Real-time status updates
        async function updateSystemStatus() {
            try {
                const response = await fetch('/api/status');
                const status = await response.json();
                
                document.getElementById('active-transactions').textContent = status.active_transactions || 0;
                document.getElementById('participant-count').textContent = status.registered_participants || 0;
                
                document.getElementById('live-status').innerHTML = `
                    Last update: ${new Date().toLocaleTimeString()}<br>
                    Active: ${status.active_transactions || 0} transactions<br>
                    Participants: ${status.registered_participants || 0} services
                `;
            } catch (error) {
                document.getElementById('live-status').innerHTML = `
                    <span style="color: red;">Connection error</span><br>
                    ${new Date().toLocaleTimeString()}
                `;
            }
        }
        
        // Start real-time updates
        setInterval(updateSystemStatus, 2000);
        updateSystemStatus();
        
        // Initialize
        addLogEntry('info', 'Two-Phase Commit Demo UI initialized');
        updateTransactionList();
    </script>
</body>
</html>
EOF

# Create monitoring configuration
echo "📊 Creating monitoring configuration..."
mkdir -p monitoring/grafana

cat > monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'coordinator'
    static_configs:
      - targets: ['coordinator:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'payment-service'
    static_configs:
      - targets: ['payment-service:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'inventory-service'
    static_configs:
      - targets: ['inventory-service:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'shipping-service'
    static_configs:
      - targets: ['shipping-service:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s
EOF

# Create test scripts
echo "🧪 Creating test scripts..."
cat > scripts/test_scenarios.sh << 'EOF'
#!/bin/bash

# Two-Phase Commit Test Scenarios
echo "🧪 Running Two-Phase Commit Test Scenarios"

COORDINATOR_URL="http://localhost:8000"

# Test 1: Successful transaction
echo "📋 Test 1: Successful Transaction"
TRANSACTION_ID=$(curl -s -X POST "$COORDINATOR_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "participants": ["payment-service", "inventory-service", "shipping-service"],
    "operation_data": {
      "amount": 100,
      "product": "laptop",
      "quantity": 1,
      "shipping_address": "123 Test Street"
    }
  }' | jq -r '.transaction_id')

echo "Started transaction: $TRANSACTION_ID"

# Monitor transaction
for i in {1..30}; do
  STATUS=$(curl -s "$COORDINATOR_URL/transaction/$TRANSACTION_ID" | jq -r '.state')
  echo "  Status: $STATUS"
  
  if [ "$STATUS" = "committed" ] || [ "$STATUS" = "aborted" ]; then
    break
  fi
  
  sleep 1
done

echo "Final status: $STATUS"
echo ""

# Test 2: Transaction with high amount (should fail)
echo "📋 Test 2: High Amount Transaction (Expected Failure)"
TRANSACTION_ID=$(curl -s -X POST "$COORDINATOR_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "participants": ["payment-service", "inventory-service", "shipping-service"],
    "operation_data": {
      "amount": 50000,
      "product": "laptop",
      "quantity": 100,
      "shipping_address": "123 Test Street"
    }
  }' | jq -r '.transaction_id')

echo "Started transaction: $TRANSACTION_ID"

# Monitor transaction
for i in {1..30}; do
  STATUS=$(curl -s "$COORDINATOR_URL/transaction/$TRANSACTION_ID" | jq -r '.state')
  echo "  Status: $STATUS"
  
  if [ "$STATUS" = "committed" ] || [ "$STATUS" = "aborted" ]; then
    break
  fi
  
  sleep 1
done

echo "Final status: $STATUS"
echo ""

# Test 3: System status
echo "📋 Test 3: System Status"
curl -s "$COORDINATOR_URL/status" | jq '.'

echo ""
echo "✅ Test scenarios completed!"
EOF

cat > scripts/chaos_testing.sh << 'EOF'
#!/bin/bash

# Chaos Engineering Tests for Two-Phase Commit
echo "🔥 Running Chaos Engineering Tests"

# Function to simulate network partition
simulate_network_partition() {
    echo "🌐 Simulating network partition for payment-service..."
    
    # Block traffic to payment-service (requires docker network manipulation)
    docker exec two-phase-commit-demo_payment-service_1 \
        sh -c "iptables -A INPUT -p tcp --dport 8000 -j DROP" 2>/dev/null || \
        echo "⚠️  Network partition simulation requires privileged container access"
    
    sleep 10
    
    # Restore network
    docker exec two-phase-commit-demo_payment-service_1 \
        sh -c "iptables -F" 2>/dev/null || \
        echo "⚠️  Network restoration requires privileged container access"
}

# Function to simulate coordinator failure
simulate_coordinator_failure() {
    echo "💥 Simulating coordinator failure..."
    
    # Stop coordinator
    docker-compose stop coordinator
    
    sleep 15
    
    # Restart coordinator
    docker-compose start coordinator
    
    # Wait for recovery
    sleep 10
}

# Function to simulate participant failure
simulate_participant_failure() {
    echo "⚡ Simulating participant failure..."
    
    # Stop inventory service during transaction
    docker-compose stop inventory-service &
    
    # Start transaction immediately
    curl -X POST "http://localhost:8000/transaction" \
        -H "Content-Type: application/json" \
        -d '{
            "participants": ["payment-service", "inventory-service", "shipping-service"],
            "operation_data": {
                "amount": 150,
                "product": "phone",
                "quantity": 1,
                "shipping_address": "456 Chaos Lane"
            }
        }'
    
    sleep 5
    
    # Restart inventory service
    docker-compose start inventory-service
}

# Function to run load test
run_load_test() {
    echo "⚡ Running load test..."
    
    # Start 20 concurrent transactions
    for i in {1..20}; do
        curl -X POST "http://localhost:8000/transaction" \
            -H "Content-Type: application/json" \
            -d "{
                \"participants\": [\"payment-service\", \"inventory-service\", \"shipping-service\"],
                \"operation_data\": {
                    \"amount\": $((RANDOM % 500 + 50)),
                    \"product\": \"laptop\",
                    \"quantity\": $((RANDOM % 3 + 1)),
                    \"shipping_address\": \"Load Test Address $i\"
                }
            }" &
    done
    
    wait
    echo "Load test completed"
}

echo "Select chaos test to run:"
echo "1. Network Partition"
echo "2. Coordinator Failure"
echo "3. Participant Failure" 
echo "4. Load Test"
echo "5. All Tests"

read -p "Enter choice (1-5): " choice

case $choice in
    1) simulate_network_partition ;;
    2) simulate_coordinator_failure ;;
    3) simulate_participant_failure ;;
    4) run_load_test ;;
    5) 
        simulate_participant_failure
        sleep 30
        simulate_coordinator_failure
        sleep 30
        run_load_test
        ;;
    *) echo "Invalid choice" ;;
esac

echo "🔥 Chaos testing completed!"
EOF

chmod +x scripts/*.sh

# Create build and run script
cat > build_and_run.sh << 'EOF'
#!/bin/bash

echo "🏗️  Building Two-Phase Commit Demo..."

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker-compose down -v 2>/dev/null || true

# Build and start services
echo "🚀 Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🔍 Checking service health..."
services=("coordinator:8000" "payment-service:8001" "inventory-service:8002" "shipping-service:8003")

for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if curl -s "http://localhost:$port/health" > /dev/null; then
        echo "✅ $name is healthy"
    else
        echo "❌ $name is not responding"
    fi
done

echo ""
echo "🎉 Two-Phase Commit Demo is ready!"
echo ""
echo "📱 Access points:"
echo "  🌐 Web UI:           http://localhost:3000"
echo "  🎯 Coordinator API:  http://localhost:8000"
echo "  💳 Payment Service:  http://localhost:8001"
echo "  📦 Inventory Service: http://localhost:8002"
echo "  🚚 Shipping Service: http://localhost:8003"
echo "  📊 Prometheus:       http://localhost:9090"
echo "  📈 Grafana:          http://localhost:3001 (admin/admin)"
echo ""
echo "🧪 Test commands:"
echo "  ./scripts/test_scenarios.sh"
echo "  ./scripts/chaos_testing.sh"
echo ""
echo "📋 Monitor logs:"
echo "  docker-compose logs -f coordinator"
echo "  docker-compose logs -f payment-service"
echo ""
echo "🛑 To stop:"
echo "  docker-compose down"
EOF

chmod +x build_and_run.sh

echo ""
echo "🎉 Two-Phase Commit Demo Setup Complete!"
echo "=================================================="
echo ""
echo "📁 Project structure created:"
echo "  ├── coordinator/          - Transaction coordinator service"
echo "  ├── participant/          - Participant services (payment, inventory, shipping)"
echo "  ├── web-ui/              - Interactive web interface"
echo "  ├── monitoring/          - Prometheus & Grafana configuration"
echo "  ├── scripts/             - Test and chaos engineering scripts"
echo "  └── docker-compose.yml   - Container orchestration"
echo ""
echo "🚀 To start the demo:"
echo "  ./build_and_run.sh"
echo ""
echo "📚 What you'll see:"
echo "  ✅ Complete 2PC implementation with recovery"
echo "  🎯 Interactive web UI for transaction management"
echo "  📊 Real-time metrics and monitoring"
echo "  🧪 Test scenarios and chaos engineering"
echo "  📈 Performance monitoring with Prometheus/Grafana"
echo "  🔍 Comprehensive logging and observability"
echo ""
echo "🎓 Learning outcomes:"
echo "  - Understand 2PC protocol mechanics"
echo "  - Observe failure modes and recovery patterns"
echo "  - Experience production-grade implementation"
echo "  - Learn observability and chaos testing"
echo ""
echo "Ready to explore distributed transactions! 🚀"


# Make the main script executable
chmod +x two-phase-commit-demo.sh

# Display completion message
echo ""
echo "✅ Two-Phase Commit Protocol Demo Script Created!"
echo "=================================================="
echo ""
echo "📂 Created: two-phase-commit-demo/"
echo "   Complete production-ready 2PC implementation"
echo ""
echo "🚀 To run the demo:"
echo "   cd two-phase-commit-demo"
echo "   ./build_and_run.sh"
echo ""
echo "🎯 Features included:"
echo "   • Full 2PC coordinator with state machine"
echo "   • Multiple participant services with realistic business logic"
echo "   • Interactive web UI for transaction management"
echo "   • Comprehensive monitoring with Prometheus & Grafana"
echo "   • Chaos engineering test scripts"
echo "   • Network partition and failure simulation"
echo "   • Production-grade logging and observability"
echo "   • Recovery and timeout handling"
echo ""
echo "📊 Monitoring endpoints:"
echo "   • Web UI: http://localhost:3000"
echo "   • Coordinator: http://localhost:8000"
echo "   • Prometheus: http://localhost:9090"
echo "   • Grafana: http://localhost:3001"
echo ""
echo "🧪 Test scenarios:"
echo "   • Success and failure transactions"
echo "   • Coordinator failure recovery"
echo "   • Participant failure handling"
echo "   • Network partition simulation"
echo "   • Load and stress testing"
echo ""
echo "Ready to master distributed transactions! 🎓"