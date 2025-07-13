from flask import Flask, request, jsonify, render_template
from flask_sqlalchemy import SQLAlchemy
import redis
import uuid
import hashlib
import json
import time
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/idempotency_db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Initialize extensions
db = SQLAlchemy(app)
redis_client = redis.from_url(os.getenv('REDIS_URL', 'redis://localhost:6379'), decode_responses=True)

# Database Models
class Payment(db.Model):
    id = db.Column(db.String(36), primary_key=True)
    amount = db.Column(db.Float, nullable=False)
    currency = db.Column(db.String(3), nullable=False)
    customer_id = db.Column(db.String(100), nullable=False)
    status = db.Column(db.String(20), nullable=False)
    idempotency_key = db.Column(db.String(100), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    processed_at = db.Column(db.DateTime)

class IdempotencyRecord(db.Model):
    key = db.Column(db.String(100), primary_key=True)
    response_data = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)

# Idempotency Service
class IdempotencyService:
    def __init__(self, redis_client, db, ttl_hours=24):
        self.redis = redis_client
        self.db = db
        self.ttl_seconds = ttl_hours * 3600
        
    def generate_key(self, client_id, operation, params):
        """Generate idempotency key from client and operation context"""
        content_hash = hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()[:16]
        return f"idem:{client_id}:{operation}:{content_hash}"
    
    def get_cached_response(self, key):
        """Check if operation was already processed"""
        try:
            # Try Redis first (fast path)
            cached = self.redis.get(key)
            if cached:
                logger.info(f"Found cached response in Redis for key: {key}")
                return json.loads(cached)
            
            # Fallback to database
            record = IdempotencyRecord.query.filter_by(key=key).first()
            if record and record.expires_at > datetime.utcnow():
                response_data = json.loads(record.response_data)
                # Cache back to Redis
                self.redis.setex(key, self.ttl_seconds, record.response_data)
                logger.info(f"Found cached response in DB for key: {key}")
                return response_data
                
            return None
        except Exception as e:
            logger.error(f"Error checking cache for key {key}: {e}")
            return None
    
    def store_response(self, key, response_data):
        """Store operation response for future idempotency checks"""
        try:
            response_json = json.dumps(response_data)
            expires_at = datetime.utcnow() + timedelta(seconds=self.ttl_seconds)
            
            # Store in Redis
            self.redis.setex(key, self.ttl_seconds, response_json)
            
            # Store in database for durability
            record = IdempotencyRecord(
                key=key,
                response_data=response_json,
                expires_at=expires_at
            )
            self.db.session.merge(record)
            self.db.session.commit()
            
            logger.info(f"Stored response for key: {key}")
        except Exception as e:
            logger.error(f"Error storing response for key {key}: {e}")

# Initialize idempotency service
idempotency_service = IdempotencyService(redis_client, db)

# Payment Processing Service
class PaymentService:
    def __init__(self, idempotency_service):
        self.idempotency_service = idempotency_service
    
    def process_payment(self, amount, currency, customer_id, idempotency_key, simulate_failure=False):
        """Process payment with idempotency guarantees"""
        
        # Check for existing operation
        cached_response = self.idempotency_service.get_cached_response(idempotency_key)
        if cached_response:
            logger.info(f"Returning cached payment response for key: {idempotency_key}")
            return cached_response
        
        # Simulate network delay
        time.sleep(0.1)
        
        # Simulate failure if requested
        if simulate_failure and amount > 1000:
            response = {
                'status': 'failed',
                'error': 'Insufficient funds',
                'payment_id': None,
                'processed_at': datetime.utcnow().isoformat()
            }
        else:
            # Create new payment
            payment_id = str(uuid.uuid4())
            payment = Payment(
                id=payment_id,
                amount=amount,
                currency=currency,
                customer_id=customer_id,
                status='completed',
                idempotency_key=idempotency_key,
                processed_at=datetime.utcnow()
            )
            
            db.session.add(payment)
            db.session.commit()
            
            response = {
                'status': 'completed',
                'payment_id': payment_id,
                'amount': amount,
                'currency': currency,
                'processed_at': datetime.utcnow().isoformat()
            }
        
        # Store response for future idempotency checks
        self.idempotency_service.store_response(idempotency_key, response)
        
        logger.info(f"Processed new payment with key: {idempotency_key}")
        return response

payment_service = PaymentService(idempotency_service)

# Routes
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/payment', methods=['POST'])
def create_payment():
    """Create payment with idempotency support"""
    data = request.get_json()
    
    required_fields = ['amount', 'currency', 'customer_id']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing required field: {field}'}), 400
    
    # Generate or use provided idempotency key
    idempotency_key = data.get('idempotency_key')
    if not idempotency_key:
        # Generate key based on operation parameters
        idempotency_key = idempotency_service.generate_key(
            data['customer_id'], 
            'payment', 
            {
                'amount': data['amount'],
                'currency': data['currency'],
                'timestamp_window': int(time.time() // 300)  # 5-minute windows
            }
        )
    
    simulate_failure = data.get('simulate_failure', False)
    
    try:
        result = payment_service.process_payment(
            data['amount'],
            data['currency'],
            data['customer_id'],
            idempotency_key,
            simulate_failure
        )
        
        # Add idempotency key to response for debugging
        result['idempotency_key'] = idempotency_key
        result['was_cached'] = idempotency_service.get_cached_response(idempotency_key) is not None
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Payment processing error: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/payments', methods=['GET'])
def list_payments():
    """List all payments"""
    payments = Payment.query.order_by(Payment.created_at.desc()).limit(20).all()
    return jsonify([{
        'id': p.id,
        'amount': p.amount,
        'currency': p.currency,
        'customer_id': p.customer_id,
        'status': p.status,
        'idempotency_key': p.idempotency_key,
        'created_at': p.created_at.isoformat() if p.created_at else None,
        'processed_at': p.processed_at.isoformat() if p.processed_at else None
    } for p in payments])

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get system statistics"""
    total_payments = Payment.query.count()
    total_cached = IdempotencyRecord.query.count()
    
    return jsonify({
        'total_payments': total_payments,
        'cached_operations': total_cached,
        'redis_keys': len(redis_client.keys('idem:*')),
        'uptime': time.time()
    })

@app.route('/api/simulate-retry', methods=['POST'])
def simulate_retry():
    """Simulate retry scenario with same idempotency key"""
    data = request.get_json()
    
    # Process payment multiple times with same key
    results = []
    idempotency_key = str(uuid.uuid4())
    
    for i in range(data.get('retry_count', 3)):
        result = payment_service.process_payment(
            data['amount'],
            data['currency'],
            data['customer_id'],
            idempotency_key,
            data.get('simulate_failure', False)
        )
        result['attempt'] = i + 1
        result['idempotency_key'] = idempotency_key
        results.append(result)
        
        # Small delay between retries
        time.sleep(0.05)
    
    return jsonify({
        'scenario': 'retry_simulation',
        'results': results,
        'all_identical': all(r['status'] == results[0]['status'] for r in results)
    })

# Initialize database
def create_tables():
    with app.app_context():
        db.create_all()

# Initialize database on startup
create_tables()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
