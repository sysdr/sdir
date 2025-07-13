#!/bin/bash
# demo.sh - Idempotency in Distributed Systems Demo
# Creates complete payment processing system with idempotency guarantees

set -e
PROJECT_NAME="idempotency-demo"

echo "🚀 Building Idempotency in Distributed Systems Demo"
echo "=================================================="

# Create project structure
mkdir -p $PROJECT_NAME/{app,templates,static,tests,config}
cd $PROJECT_NAME

# Create requirements.txt with latest compatible versions
cat > requirements.txt << 'EOF'
flask==3.0.0
redis==5.0.1
psycopg2-binary==2.9.9
requests==2.31.0
pytest==7.4.3
sqlalchemy==2.0.23
flask-sqlalchemy==3.1.1
gunicorn==21.2.0
python-dotenv==1.0.0
EOF

# Create Docker Compose configuration
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - REDIS_URL=redis://redis:6379
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/idempotency_db
    depends_on:
      - redis
      - postgres
    volumes:
      - .:/app
    command: gunicorn --bind 0.0.0.0:8080 --workers 1 app:app

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=idempotency_db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "app:app"]
EOF

# Create main Flask application
cat > app.py << 'EOF'
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
EOF

# Create HTML template with Google Cloud Skills Boost styling
mkdir -p templates
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Idempotency in Distributed Systems - Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Google Sans', 'Roboto', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #202124;
        }

        .header {
            background: white;
            padding: 16px 24px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .logo {
            font-size: 24px;
            font-weight: 500;
            color: #1a73e8;
        }

        .container {
            max-width: 1200px;
            margin: 24px auto;
            padding: 0 24px;
        }

        .card {
            background: white;
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 24px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }

        .card-title {
            font-size: 20px;
            font-weight: 500;
            margin-bottom: 16px;
            color: #1a73e8;
        }

        .form-group {
            margin-bottom: 16px;
        }

        label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: #5f6368;
        }

        input, select {
            width: 100%;
            padding: 12px 16px;
            border: 2px solid #dadce0;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.2s;
        }

        input:focus, select:focus {
            outline: none;
            border-color: #1a73e8;
        }

        .btn {
            background: #1a73e8;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: background-color 0.2s;
            margin-right: 12px;
            margin-bottom: 12px;
        }

        .btn:hover {
            background: #1557b0;
        }

        .btn-secondary {
            background: #f8f9fa;
            color: #5f6368;
            border: 2px solid #dadce0;
        }

        .btn-secondary:hover {
            background: #e8eaed;
        }

        .results {
            margin-top: 24px;
        }

        .result-item {
            background: #f8f9fa;
            border-left: 4px solid #34a853;
            padding: 16px;
            margin-bottom: 12px;
            border-radius: 4px;
        }

        .result-item.error {
            border-left-color: #ea4335;
        }

        .result-item.cached {
            border-left-color: #fbbc04;
        }

        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 16px;
            margin-top: 24px;
        }

        .status-card {
            background: #f8f9fa;
            padding: 16px;
            border-radius: 8px;
            text-align: center;
        }

        .status-number {
            font-size: 32px;
            font-weight: 500;
            color: #1a73e8;
        }

        .status-label {
            font-size: 14px;
            color: #5f6368;
            margin-top: 4px;
        }

        .scenario-buttons {
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            margin-top: 16px;
        }

        .loading {
            opacity: 0.6;
            pointer-events: none;
        }

        .highlight {
            background: #e3f2fd;
            padding: 16px;
            border-radius: 8px;
            margin: 16px 0;
            border-left: 4px solid #1a73e8;
        }

        .code {
            background: #263238;
            color: #ffffff;
            padding: 16px;
            border-radius: 8px;
            font-family: 'Roboto Mono', monospace;
            font-size: 14px;
            overflow-x: auto;
            margin: 16px 0;
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">🔄 Idempotency Demo</div>
        <div>System Design Interview Roadmap - Issue #94</div>
    </div>

    <div class="container">
        <div class="card">
            <div class="card-title">Understanding Idempotency in Action</div>
            <div class="highlight">
                <strong>Idempotency Guarantee:</strong> No matter how many times you retry the same operation, 
                the result will be identical. This prevents duplicate charges, double processing, 
                and maintains system consistency during network failures.
            </div>
        </div>

        <div class="card">
            <div class="card-title">Payment Processing Demo</div>
            
            <div class="form-group">
                <label>Amount (USD)</label>
                <input type="number" id="amount" value="100.00" step="0.01" min="0">
            </div>
            
            <div class="form-group">
                <label>Customer ID</label>
                <input type="text" id="customerId" value="customer_123">
            </div>
            
            <div class="form-group">
                <label>Currency</label>
                <select id="currency">
                    <option value="USD">USD</option>
                    <option value="EUR">EUR</option>
                    <option value="GBP">GBP</option>
                </select>
            </div>
            
            <div class="form-group">
                <label>
                    <input type="checkbox" id="simulateFailure"> 
                    Simulate payment failure (for amounts > $1000)
                </label>
            </div>

            <div class="scenario-buttons">
                <button class="btn" onclick="processPayment()">Process Payment</button>
                <button class="btn btn-secondary" onclick="simulateRetry()">Simulate Network Retry (3x)</button>
                <button class="btn btn-secondary" onclick="simulateDoubleClick()">Simulate Double-Click</button>
                <button class="btn btn-secondary" onclick="demonstrateTimeWindow()">Time Window Test</button>
            </div>

            <div id="results" class="results"></div>
        </div>

        <div class="status-grid">
            <div class="status-card">
                <div class="status-number" id="totalPayments">0</div>
                <div class="status-label">Total Payments</div>
            </div>
            <div class="status-card">
                <div class="status-number" id="cachedOperations">0</div>
                <div class="status-label">Cached Operations</div>
            </div>
            <div class="status-card">
                <div class="status-number" id="redisKeys">0</div>
                <div class="status-label">Redis Keys</div>
            </div>
        </div>

        <div class="card">
            <div class="card-title">Recent Payments</div>
            <div id="paymentsList"></div>
        </div>
    </div>

    <script>
        let requestCount = 0;

        async function makeRequest(url, data) {
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data)
            });
            return response.json();
        }

        async function processPayment() {
            const amount = parseFloat(document.getElementById('amount').value);
            const customerId = document.getElementById('customerId').value;
            const currency = document.getElementById('currency').value;
            const simulateFailure = document.getElementById('simulateFailure').checked;

            const data = {
                amount,
                customer_id: customerId,
                currency,
                simulate_failure: simulateFailure
            };

            try {
                showLoading();
                const result = await makeRequest('/api/payment', data);
                displayResult('Single Payment', [result]);
                await updateStats();
                await loadPayments();
            } catch (error) {
                displayError('Payment processing failed: ' + error.message);
            } finally {
                hideLoading();
            }
        }

        async function simulateRetry() {
            const amount = parseFloat(document.getElementById('amount').value);
            const customerId = document.getElementById('customerId').value;
            const currency = document.getElementById('currency').value;
            const simulateFailure = document.getElementById('simulateFailure').checked;

            const data = {
                amount,
                customer_id: customerId,
                currency,
                simulate_failure: simulateFailure,
                retry_count: 3
            };

            try {
                showLoading();
                const result = await makeRequest('/api/simulate-retry', data);
                displayResult('Network Retry Simulation', result.results, result.all_identical);
                await updateStats();
                await loadPayments();
            } catch (error) {
                displayError('Retry simulation failed: ' + error.message);
            } finally {
                hideLoading();
            }
        }

        async function simulateDoubleClick() {
            const amount = parseFloat(document.getElementById('amount').value);
            const customerId = document.getElementById('customerId').value;
            const currency = document.getElementById('currency').value;

            const data = {
                amount,
                customer_id: customerId,
                currency,
                idempotency_key: 'double-click-' + Date.now()
            };

            try {
                showLoading();
                // Simulate rapid double-click
                const promises = [
                    makeRequest('/api/payment', data),
                    makeRequest('/api/payment', data)
                ];
                
                const results = await Promise.all(promises);
                displayResult('Double-Click Simulation', results, 
                    results[0].payment_id === results[1].payment_id);
                await updateStats();
                await loadPayments();
            } catch (error) {
                displayError('Double-click simulation failed: ' + error.message);
            } finally {
                hideLoading();
            }
        }

        async function demonstrateTimeWindow() {
            const amount = parseFloat(document.getElementById('amount').value);
            const customerId = document.getElementById('customerId').value;
            const currency = document.getElementById('currency').value;

            try {
                showLoading();
                
                // First payment
                const result1 = await makeRequest('/api/payment', {
                    amount,
                    customer_id: customerId,
                    currency
                });

                // Wait a moment, then try the same payment (should be idempotent)
                await new Promise(resolve => setTimeout(resolve, 1000));
                
                const result2 = await makeRequest('/api/payment', {
                    amount,
                    customer_id: customerId,
                    currency
                });

                displayResult('Time Window Test', [result1, result2], 
                    result1.payment_id === result2.payment_id);
                await updateStats();
                await loadPayments();
            } catch (error) {
                displayError('Time window test failed: ' + error.message);
            } finally {
                hideLoading();
            }
        }

        function displayResult(title, results, allIdentical = null) {
            const resultsDiv = document.getElementById('results');
            
            let html = `<h3>${title}</h3>`;
            
            if (allIdentical !== null) {
                html += `<div class="highlight">
                    <strong>Idempotency Check:</strong> ${allIdentical ? '✅ All results identical' : '❌ Results differ'}
                </div>`;
            }

            results.forEach((result, index) => {
                const isCached = result.was_cached || index > 0;
                const cssClass = result.status === 'failed' ? 'error' : (isCached ? 'cached' : '');
                
                html += `<div class="result-item ${cssClass}">
                    <strong>Attempt ${index + 1}:</strong><br>
                    Status: ${result.status}<br>
                    ${result.payment_id ? `Payment ID: ${result.payment_id}<br>` : ''}
                    ${result.amount ? `Amount: $${result.amount}<br>` : ''}
                    ${result.error ? `Error: ${result.error}<br>` : ''}
                    Idempotency Key: ${result.idempotency_key}<br>
                    ${isCached ? '<em>🔄 Returned from cache (idempotent)</em>' : '<em>✨ New operation processed</em>'}
                </div>`;
            });

            resultsDiv.innerHTML = html;
        }

        function displayError(message) {
            const resultsDiv = document.getElementById('results');
            resultsDiv.innerHTML = `<div class="result-item error">${message}</div>`;
        }

        function showLoading() {
            document.body.classList.add('loading');
        }

        function hideLoading() {
            document.body.classList.remove('loading');
        }

        async function updateStats() {
            try {
                const response = await fetch('/api/stats');
                const stats = await response.json();
                
                document.getElementById('totalPayments').textContent = stats.total_payments;
                document.getElementById('cachedOperations').textContent = stats.cached_operations;
                document.getElementById('redisKeys').textContent = stats.redis_keys;
            } catch (error) {
                console.error('Failed to update stats:', error);
            }
        }

        async function loadPayments() {
            try {
                const response = await fetch('/api/payments');
                const payments = await response.json();
                
                const paymentsDiv = document.getElementById('paymentsList');
                let html = '';
                
                payments.slice(0, 5).forEach(payment => {
                    html += `<div class="result-item">
                        <strong>Payment ${payment.id.substring(0, 8)}...</strong><br>
                        Amount: $${payment.amount} ${payment.currency}<br>
                        Customer: ${payment.customer_id}<br>
                        Status: ${payment.status}<br>
                        Created: ${new Date(payment.created_at).toLocaleString()}
                    </div>`;
                });
                
                paymentsDiv.innerHTML = html || '<p>No payments yet</p>';
            } catch (error) {
                console.error('Failed to load payments:', error);
            }
        }

        // Initialize page
        document.addEventListener('DOMContentLoaded', function() {
            updateStats();
            loadPayments();
            
            // Auto-refresh stats every 10 seconds
            setInterval(() => {
                updateStats();
                loadPayments();
            }, 10000);
        });
    </script>
</body>
</html>
EOF

# Create test file
cat > tests/test_idempotency.py << 'EOF'
import pytest
import json
import uuid
from app import app, db, Payment, IdempotencyRecord

@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    
    with app.test_client() as client:
        with app.app_context():
            db.create_all()
            yield client

def test_idempotent_payment_processing(client):
    """Test that identical payments return the same result"""
    payment_data = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'test_key_' + str(uuid.uuid4())
    }
    
    # First request
    response1 = client.post('/api/payment', 
                           data=json.dumps(payment_data),
                           content_type='application/json')
    
    # Second identical request
    response2 = client.post('/api/payment',
                           data=json.dumps(payment_data),
                           content_type='application/json')
    
    assert response1.status_code == 200
    assert response2.status_code == 200
    
    data1 = json.loads(response1.data)
    data2 = json.loads(response2.data)
    
    # Should have same payment ID
    assert data1['payment_id'] == data2['payment_id']
    assert data1['status'] == data2['status']

def test_different_idempotency_keys_create_different_payments(client):
    """Test that different idempotency keys create separate payments"""
    payment_data1 = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'key1_' + str(uuid.uuid4())
    }
    
    payment_data2 = {
        'amount': 100.00,
        'currency': 'USD',
        'customer_id': 'test_customer',
        'idempotency_key': 'key2_' + str(uuid.uuid4())
    }
    
    response1 = client.post('/api/payment',
                           data=json.dumps(payment_data1),
                           content_type='application/json')
    
    response2 = client.post('/api/payment',
                           data=json.dumps(payment_data2),
                           content_type='application/json')
    
    assert response1.status_code == 200
    assert response2.status_code == 200
    
    data1 = json.loads(response1.data)
    data2 = json.loads(response2.data)
    
    # Should have different payment IDs
    assert data1['payment_id'] != data2['payment_id']

def test_retry_simulation(client):
    """Test retry simulation returns consistent results"""
    retry_data = {
        'amount': 50.00,
        'currency': 'USD',
        'customer_id': 'retry_customer',
        'retry_count': 3
    }
    
    response = client.post('/api/simulate-retry',
                          data=json.dumps(retry_data),
                          content_type='application/json')
    
    assert response.status_code == 200
    data = json.loads(response.data)
    
    assert data['all_identical'] == True
    assert len(data['results']) == 3
    
    # All payment IDs should be the same
    payment_ids = [result['payment_id'] for result in data['results']]
    assert len(set(payment_ids)) == 1

if __name__ == '__main__':
    pytest.main([__file__])
EOF

# Create environment file
cat > .env << 'EOF'
FLASK_ENV=development
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgresql://postgres:password@localhost:5432/idempotency_db
EOF

# Build and run
echo "📦 Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check if services are running
echo "🔍 Checking service health..."
if curl -f http://localhost:8080/api/stats > /dev/null 2>&1; then
    echo "✅ Application is running successfully!"
else
    echo "❌ Application failed to start. Checking logs..."
    docker-compose logs app
    exit 1
fi

# Run tests
echo "🧪 Running tests..."
docker-compose exec app python -m pytest tests/ -v

echo ""
echo "🎉 Idempotency Demo is ready!"
echo "========================================"
echo "🌐 Web Interface: http://localhost:8080"
echo "📊 API Stats: http://localhost:8080/api/stats"
echo "🔧 Redis: localhost:6379"
echo "🗄️  PostgreSQL: localhost:5432"
echo ""
echo "Demo Scenarios to Try:"
echo "1. Process a payment normally"
echo "2. Simulate network retries (same result 3 times)"
echo "3. Simulate double-click (rapid requests)"
echo "4. Test time window behavior"
echo "5. Try failure simulation with amounts > $1000"
echo ""
echo "📝 Check logs: docker-compose logs -f app"
echo "🛑 Stop demo: ./cleanup.sh"
EOF

chmod +x demo.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash
echo "🧹 Cleaning up Idempotency Demo..."

# Stop and remove containers
docker-compose down -v

# Remove project directory
cd ..
rm -rf idempotency-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

echo "✅ Demo script created successfully!"
echo "📁 Generated files:"
echo "   - demo.sh (main setup and run script)"
echo "   - cleanup.sh (cleanup script)"
echo ""
echo "🚀 To run the demo:"
echo "   ./demo.sh"
echo ""
echo "🛑 To cleanup:"
echo "   ./cleanup.sh"