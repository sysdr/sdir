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
