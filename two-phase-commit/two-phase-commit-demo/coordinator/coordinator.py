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
