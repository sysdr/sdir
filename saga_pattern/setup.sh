#!/bin/bash

# SAGA Pattern Demo - Complete Working Version
set -e

DEMO_DIR="saga-pattern-demo"
echo "🚀 Creating SAGA Pattern Demo..."

mkdir -p $DEMO_DIR/{order-service,payment-service,inventory-service,shipping-service,web-ui,shared}
cd $DEMO_DIR

# Shared utilities
cat > shared/saga_utils.py << 'EOF'
import asyncio
import redis.asyncio as redis
import json
import logging
import uuid
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional
import httpx

class SAGAStatus(Enum):
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    COMPENSATING = "COMPENSATING"
    COMPENSATED = "COMPENSATED"

class SAGAStep:
    def __init__(self, service: str, action: str, compensation_action: str, data: Dict):
        self.service = service
        self.action = action
        self.compensation_action = compensation_action
        self.data = data
        self.status = SAGAStatus.PENDING
        self.result = None
        self.error = None
        self.timestamp = datetime.utcnow().isoformat()

class SAGAOrchestrator:
    def __init__(self, redis_url: str = "redis://redis:6379"):
        self.redis_url = redis_url
        self.redis = None
        
    async def init_redis(self):
        self.redis = redis.from_url(self.redis_url, decode_responses=True)
        await self.redis.ping()
        
    async def create_saga(self, transaction_id: str, steps: List[SAGAStep]) -> str:
        saga_data = {
            "transaction_id": transaction_id,
            "status": SAGAStatus.IN_PROGRESS.value,
            "steps": [self._step_to_dict(step) for step in steps],
            "created_at": datetime.utcnow().isoformat(),
            "current_step": 0
        }
        await self.redis.set(f"saga:{transaction_id}", json.dumps(saga_data))
        return transaction_id
        
    async def execute_saga(self, transaction_id: str) -> Dict:
        saga_data = await self.get_saga(transaction_id)
        if not saga_data:
            raise Exception(f"SAGA {transaction_id} not found")
            
        steps = saga_data["steps"]
        current_step = saga_data["current_step"]
        
        # Execute forward steps
        for i in range(current_step, len(steps)):
            step = steps[i]
            try:
                result = await self._execute_step(step)
                steps[i]["status"] = SAGAStatus.COMPLETED.value
                steps[i]["result"] = result
                saga_data["current_step"] = i + 1
                await self._update_saga(transaction_id, saga_data)
                
            except Exception as e:
                steps[i]["status"] = SAGAStatus.FAILED.value
                steps[i]["error"] = str(e)
                
                # Start compensation
                saga_data["status"] = SAGAStatus.COMPENSATING.value
                await self._update_saga(transaction_id, saga_data)
                
                # Compensate completed steps in reverse order
                for j in range(i - 1, -1, -1):
                    await self._compensate_step(steps[j])
                    
                saga_data["status"] = SAGAStatus.COMPENSATED.value
                await self._update_saga(transaction_id, saga_data)
                return saga_data
                
        saga_data["status"] = SAGAStatus.COMPLETED.value
        await self._update_saga(transaction_id, saga_data)
        return saga_data
        
    async def _execute_step(self, step: Dict) -> Dict:
        service_urls = {
            "payment": "http://payment-service:8001",
            "inventory": "http://inventory-service:8002", 
            "shipping": "http://shipping-service:8003"
        }
        
        url = f"{service_urls[step['service']]}/{step['action']}"
        timeout = httpx.Timeout(10.0, read=30.0)
        
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(url, json=step['data'])
            if response.status_code != 200:
                raise Exception(f"Step failed: {response.text}")
            return response.json()
            
    async def _compensate_step(self, step: Dict):
        if step["status"] != SAGAStatus.COMPLETED.value:
            return
            
        service_urls = {
            "payment": "http://payment-service:8001",
            "inventory": "http://inventory-service:8002",
            "shipping": "http://shipping-service:8003"
        }
        
        url = f"{service_urls[step['service']]}/{step['compensation_action']}"
        timeout = httpx.Timeout(10.0, read=30.0)
        
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                compensation_data = {**step['data'], **step.get('result', {})}
                response = await client.post(url, json=compensation_data)
                step["compensation_status"] = "COMPLETED"
            except Exception as e:
                step["compensation_status"] = f"FAILED: {str(e)}"
                
    async def get_saga(self, transaction_id: str) -> Optional[Dict]:
        data = await self.redis.get(f"saga:{transaction_id}")
        return json.loads(data) if data else None
        
    async def _update_saga(self, transaction_id: str, saga_data: Dict):
        await self.redis.set(f"saga:{transaction_id}", json.dumps(saga_data))
        
    def _step_to_dict(self, step: SAGAStep) -> Dict:
        return {
            "service": step.service,
            "action": step.action,
            "compensation_action": step.compensation_action,
            "data": step.data,
            "status": step.status.value,
            "result": step.result,
            "error": step.error,
            "timestamp": step.timestamp
        }

def setup_logging(service_name: str):
    logging.basicConfig(
        level=logging.INFO,
        format=f'%(asctime)s - {service_name} - %(levelname)s - %(message)s'
    )
    return logging.getLogger(service_name)
EOF

# Order Service
cat > order-service/main.py << 'EOF'
import sys
import os
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import asyncio
import uuid
from saga_utils import SAGAOrchestrator, SAGAStep, setup_logging

app = FastAPI(title="Order Service")
logger = setup_logging("order-service")

class OrderRequest(BaseModel):
    customer_id: str
    product_id: str
    quantity: int
    amount: float
    should_fail: str = "none"

orchestrator = None

@app.on_event("startup")
async def startup():
    global orchestrator
    orchestrator = SAGAOrchestrator()
    
    # Retry Redis connection
    for attempt in range(30):
        try:
            await orchestrator.init_redis()
            logger.info("Order Service ready")
            break
        except Exception as e:
            logger.error(f"Redis connection attempt {attempt + 1}: {e}")
            await asyncio.sleep(2)
    else:
        raise Exception("Failed to connect to Redis")

@app.post("/create-order")
async def create_order(order: OrderRequest):
    transaction_id = str(uuid.uuid4())
    logger.info(f"Creating order {transaction_id}")
    
    steps = [
        SAGAStep("inventory", "reserve", "release", {
            "transaction_id": transaction_id,
            "product_id": order.product_id,
            "quantity": order.quantity,
            "should_fail": order.should_fail == "inventory"
        }),
        SAGAStep("payment", "charge", "refund", {
            "transaction_id": transaction_id,
            "customer_id": order.customer_id,
            "amount": order.amount,
            "should_fail": order.should_fail == "payment"
        }),
        SAGAStep("shipping", "allocate", "cancel", {
            "transaction_id": transaction_id,
            "customer_id": order.customer_id,
            "product_id": order.product_id,
            "quantity": order.quantity,
            "should_fail": order.should_fail == "shipping"
        })
    ]
    
    await orchestrator.create_saga(transaction_id, steps)
    result = await orchestrator.execute_saga(transaction_id)
    
    return {"transaction_id": transaction_id, "saga_result": result}

@app.get("/saga/{transaction_id}")
async def get_saga_status(transaction_id: str):
    saga = await orchestrator.get_saga(transaction_id)
    if not saga:
        raise HTTPException(status_code=404, detail="SAGA not found")
    return saga

@app.get("/health")
async def health():
    return {"status": "healthy"}
EOF

# Payment Service
cat > payment-service/main.py << 'EOF'
import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Payment Service")
logger = setup_logging("payment-service")
payments = {}

class PaymentRequest(BaseModel):
    transaction_id: str
    customer_id: str
    amount: float
    should_fail: bool = False

class RefundRequest(BaseModel):
    transaction_id: str
    customer_id: str = None
    amount: float = None
    payment_id: str = None

@app.post("/charge")
async def charge_payment(payment: PaymentRequest):
    logger.info(f"Processing payment {payment.transaction_id}")
    await asyncio.sleep(random.uniform(0.5, 1.5))
    
    if payment.should_fail:
        raise HTTPException(status_code=400, detail="Payment failed")
    
    payment_id = f"pay_{payment.transaction_id[:8]}"
    payments[payment_id] = {
        "transaction_id": payment.transaction_id,
        "customer_id": payment.customer_id,
        "amount": payment.amount,
        "status": "charged"
    }
    
    return {"payment_id": payment_id, "status": "charged", "amount": payment.amount}

@app.post("/refund")
async def refund_payment(refund: RefundRequest):
    logger.info(f"Processing refund {refund.transaction_id}")
    
    payment_id = refund.payment_id or f"pay_{refund.transaction_id[:8]}"
    if payment_id in payments:
        payments[payment_id]["status"] = "refunded"
        return {"payment_id": payment_id, "status": "refunded"}
    
    return {"status": "not_found"}

@app.get("/health")
async def health():
    return {"status": "healthy"}
EOF

# Inventory Service
cat > inventory-service/main.py << 'EOF'
import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Inventory Service")
logger = setup_logging("inventory-service")

inventory = {"product-1": 100, "product-2": 50, "product-3": 25}
reservations = {}

class InventoryRequest(BaseModel):
    transaction_id: str
    product_id: str
    quantity: int
    should_fail: bool = False

class ReleaseRequest(BaseModel):
    transaction_id: str
    product_id: str = None
    quantity: int = None
    reservation_id: str = None

@app.post("/reserve")
async def reserve_inventory(request: InventoryRequest):
    logger.info(f"Reserving {request.quantity} of {request.product_id}")
    await asyncio.sleep(random.uniform(0.3, 1.0))
    
    if request.should_fail:
        raise HTTPException(status_code=400, detail="Inventory unavailable")
    
    if request.product_id not in inventory:
        raise HTTPException(status_code=404, detail="Product not found")
    
    if inventory[request.product_id] < request.quantity:
        raise HTTPException(status_code=400, detail="Insufficient inventory")
    
    inventory[request.product_id] -= request.quantity
    reservation_id = f"res_{request.transaction_id[:8]}"
    reservations[reservation_id] = {
        "transaction_id": request.transaction_id,
        "product_id": request.product_id,
        "quantity": request.quantity,
        "status": "reserved"
    }
    
    return {"reservation_id": reservation_id, "status": "reserved"}

@app.post("/release")
async def release_inventory(request: ReleaseRequest):
    logger.info(f"Releasing inventory {request.transaction_id}")
    
    reservation_id = request.reservation_id or f"res_{request.transaction_id[:8]}"
    if reservation_id in reservations:
        reservation = reservations[reservation_id]
        inventory[reservation["product_id"]] += reservation["quantity"]
        reservation["status"] = "released"
        return {"reservation_id": reservation_id, "status": "released"}
    
    return {"status": "not_found"}

@app.get("/inventory")
async def get_inventory():
    return {"inventory": inventory, "reservations": reservations}

@app.get("/health")
async def health():
    return {"status": "healthy"}
EOF

# Shipping Service
cat > shipping-service/main.py << 'EOF'
import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Shipping Service")
logger = setup_logging("shipping-service")
shipments = {}

class ShippingRequest(BaseModel):
    transaction_id: str
    customer_id: str
    product_id: str
    quantity: int
    should_fail: bool = False

class CancelRequest(BaseModel):
    transaction_id: str
    shipment_id: str = None

@app.post("/allocate")
async def allocate_shipping(request: ShippingRequest):
    logger.info(f"Allocating shipping {request.transaction_id}")
    await asyncio.sleep(random.uniform(0.8, 2.0))
    
    if request.should_fail:
        raise HTTPException(status_code=500, detail="Shipping unavailable")
    
    shipment_id = f"ship_{request.transaction_id[:8]}"
    shipments[shipment_id] = {
        "transaction_id": request.transaction_id,
        "customer_id": request.customer_id,
        "product_id": request.product_id,
        "quantity": request.quantity,
        "status": "allocated",
        "tracking_number": f"TRK{random.randint(100000, 999999)}"
    }
    
    return {"shipment_id": shipment_id, "status": "allocated"}

@app.post("/cancel")
async def cancel_shipping(request: CancelRequest):
    logger.info(f"Cancelling shipping {request.transaction_id}")
    
    shipment_id = request.shipment_id or f"ship_{request.transaction_id[:8]}"
    if shipment_id in shipments:
        shipments[shipment_id]["status"] = "cancelled"
        return {"shipment_id": shipment_id, "status": "cancelled"}
    
    return {"status": "not_found"}

@app.get("/health")
async def health():
    return {"status": "healthy"}
EOF

# Web UI
cat > web-ui/app.py << 'EOF'
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
import httpx
import asyncio

app = FastAPI()
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

@app.post("/create-order")
async def create_order(request: Request):
    data = await request.json()
    
    # Use localhost instead of service names from web UI
    timeout = httpx.Timeout(10.0, read=60.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post("http://order-service:8000/create-order", json=data)
            if response.status_code == 200:
                return response.json()
            else:
                return {"error": f"HTTP {response.status_code}: {response.text}"}
        except Exception as e:
            return {"error": str(e)}

@app.get("/saga-status/{transaction_id}")
async def saga_status(transaction_id: str):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(f"http://order-service:8000/saga/{transaction_id}")
            return response.json()
        except Exception as e:
            return {"error": str(e)}

@app.get("/inventory")
async def inventory():
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get("http://inventory-service:8002/inventory")
            return response.json()
        except Exception as e:
            return {"error": str(e)}
EOF

# Web UI Template
mkdir -p web-ui/templates
cat > web-ui/templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>SAGA Pattern Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .demo-section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
        button { background-color: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; margin: 5px; }
        button:hover { background-color: #0056b3; }
        button.danger { background-color: #dc3545; }
        button.danger:hover { background-color: #c82333; }
        .log-area { background-color: #f8f9fa; border: 1px solid #dee2e6; padding: 15px; border-radius: 4px; height: 300px; overflow-y: auto; font-family: monospace; white-space: pre-wrap; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .success { background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
        .error { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
        .warning { background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .form-group { margin: 10px 0; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input, select { width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 SAGA Pattern Demo</h1>
        
        <div class="demo-section">
            <h2>Create Order (SAGA Transaction)</h2>
            <div class="grid">
                <div>
                    <div class="form-group">
                        <label>Customer ID:</label>
                        <input type="text" id="customer_id" value="customer-123">
                    </div>
                    <div class="form-group">
                        <label>Product ID:</label>
                        <select id="product_id">
                            <option value="product-1">Product 1</option>
                            <option value="product-2">Product 2</option>
                            <option value="product-3">Product 3</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Quantity:</label>
                        <input type="number" id="quantity" value="2" min="1">
                    </div>
                    <div class="form-group">
                        <label>Amount ($):</label>
                        <input type="number" id="amount" value="99.99" step="0.01">
                    </div>
                    <div class="form-group">
                        <label>Failure Scenario:</label>
                        <select id="should_fail">
                            <option value="none">✅ Success</option>
                            <option value="inventory">❌ Inventory Failure</option>
                            <option value="payment">❌ Payment Failure</option>
                            <option value="shipping">❌ Shipping Failure</option>
                        </select>
                    </div>
                </div>
                <div>
                    <h3>Test Scenarios:</h3>
                    <button onclick="runSuccess()">🎯 Success</button>
                    <button onclick="runPaymentFailure()" class="danger">💳 Payment Fail</button>
                    <button onclick="runInventoryFailure()" class="danger">📦 Inventory Fail</button>
                    <button onclick="runShippingFailure()" class="danger">🚚 Shipping Fail</button>
                    <br><br>
                    <button onclick="createOrder()">🚀 Create Order</button>
                    <button onclick="checkInventory()">📊 Check Inventory</button>
                    <button onclick="clearLogs()">🧹 Clear</button>
                </div>
            </div>
        </div>

        <div class="demo-section">
            <h2>🔍 SAGA Execution Logs</h2>
            <div id="logs" class="log-area">Ready...\n</div>
        </div>

        <div class="demo-section">
            <h2>📈 Status</h2>
            <div id="status" class="status success">System ready</div>
        </div>
    </div>

    <script>
        function log(message) {
            const logs = document.getElementById('logs');
            const timestamp = new Date().toLocaleTimeString();
            logs.textContent += `[${timestamp}] ${message}\n`;
            logs.scrollTop = logs.scrollHeight;
        }

        function updateStatus(message, type = 'success') {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = `status ${type}`;
        }

        function clearLogs() {
            document.getElementById('logs').textContent = '';
        }

        async function createOrder() {
            const orderData = {
                customer_id: document.getElementById('customer_id').value,
                product_id: document.getElementById('product_id').value,
                quantity: parseInt(document.getElementById('quantity').value),
                amount: parseFloat(document.getElementById('amount').value),
                should_fail: document.getElementById('should_fail').value
            };

            log(`🚀 Creating order: ${JSON.stringify(orderData)}`);
            updateStatus('Creating order...', 'warning');

            try {
                const response = await fetch('/create-order', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(orderData)
                });

                const result = await response.json();

                if (result.error) {
                    updateStatus(`❌ Error: ${result.error}`, 'error');
                    log(`❌ Error: ${result.error}`);
                    return;
                }

                const saga = result.saga_result;
                if (saga.status === 'COMPLETED') {
                    updateStatus(`✅ SAGA completed: ${result.transaction_id}`, 'success');
                    log('✅ All steps completed');
                } else {
                    updateStatus(`❌ SAGA failed: ${result.transaction_id}`, 'error');
                    log('❌ SAGA failed - compensation executed');
                }

                saga.steps.forEach((step, index) => {
                    log(`  Step ${index + 1} (${step.service}): ${step.status}`);
                    if (step.error) log(`    Error: ${step.error}`);
                    if (step.compensation_status) log(`    Compensation: ${step.compensation_status}`);
                });

            } catch (error) {
                log(`❌ Network error: ${error.message}`);
                updateStatus('Network error', 'error');
            }
        }

        async function checkInventory() {
            try {
                const response = await fetch('/inventory');
                const result = await response.json();
                
                if (result.error) {
                    log(`❌ Error: ${result.error}`);
                } else {
                    log(`📦 Inventory: ${JSON.stringify(result.inventory)}`);
                    updateStatus('Inventory retrieved', 'success');
                }
            } catch (error) {
                log(`❌ Error: ${error.message}`);
            }
        }

        function runSuccess() {
            document.getElementById('should_fail').value = 'none';
            log('🎯 Running SUCCESS scenario');
            createOrder();
        }

        function runPaymentFailure() {
            document.getElementById('should_fail').value = 'payment';
            log('💳 Running PAYMENT FAILURE scenario');
            createOrder();
        }

        function runInventoryFailure() {
            document.getElementById('should_fail').value = 'inventory';
            log('📦 Running INVENTORY FAILURE scenario');
            createOrder();
        }

        function runShippingFailure() {
            document.getElementById('should_fail').value = 'shipping';
            log('🚚 Running SHIPPING FAILURE scenario');
            createOrder();
        }

        log('🔄 SAGA Pattern Demo ready');
    </script>
</body>
</html>
EOF

# Requirements files
cat > order-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
httpx==0.25.2
pydantic==2.5.0
EOF

cat > payment-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
httpx==0.25.2
pydantic==2.5.0
EOF

cat > inventory-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
httpx==0.25.2
pydantic==2.5.0
EOF

cat > shipping-service/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
httpx==0.25.2
pydantic==2.5.0
EOF

cat > web-ui/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
httpx==0.25.2
jinja2==3.1.2
python-multipart==0.0.6
EOF

# Docker Compose with proper networking
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10

  order-service:
    build:
      context: .
      dockerfile: order-service/Dockerfile
    ports:
      - "8000:8000"
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - ./shared:/app/shared
    environment:
      - PYTHONPATH=/app/shared

  payment-service:
    build:
      context: .
      dockerfile: payment-service/Dockerfile
    ports:
      - "8001:8001"
    volumes:
      - ./shared:/app/shared
    environment:
      - PYTHONPATH=/app/shared

  inventory-service:
    build:
      context: .
      dockerfile: inventory-service/Dockerfile
    ports:
      - "8002:8002"
    volumes:
      - ./shared:/app/shared
    environment:
      - PYTHONPATH=/app/shared

  shipping-service:
    build:
      context: .
      dockerfile: shipping-service/Dockerfile
    ports:
      - "8003:8003"
    volumes:
      - ./shared:/app/shared
    environment:
      - PYTHONPATH=/app/shared

  web-ui:
    build:
      context: .
      dockerfile: web-ui/Dockerfile
    ports:
      - "5000:5000"
    depends_on:
      - order-service
      - payment-service
      - inventory-service
      - shipping-service
    
EOF

# Dockerfiles
cat > order-service/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY order-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY order-service/ .
COPY shared/ /app/shared/
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

cat > payment-service/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY payment-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY payment-service/ .
COPY shared/ /app/shared/
EXPOSE 8001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
EOF

cat > inventory-service/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY inventory-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY inventory-service/ .
COPY shared/ /app/shared/
EXPOSE 8002
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
EOF

cat > shipping-service/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY shipping-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY shipping-service/ .
COPY shared/ /app/shared/
EXPOSE 8003
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
EOF

cat > web-ui/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY web-ui/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY web-ui/ .
EXPOSE 5000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"]
EOF

# Test script
cat > test_saga.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import httpx
import time

async def test_services():
    """Test all SAGA scenarios"""
    print("🧪 Testing SAGA Pattern...")
    
    # Wait for services
    await asyncio.sleep(10)
    
    base_url = "http://localhost:8000"
    
    # Test 1: Success
    print("🎯 Testing success scenario...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-1",
            "product_id": "product-1",
            "quantity": 2,
            "amount": 50.0,
            "should_fail": "none"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPLETED"
        print("✅ Success test passed")
    
    # Test 2: Payment failure
    print("💳 Testing payment failure...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-2",
            "product_id": "product-2",
            "quantity": 1,
            "amount": 100.0,
            "should_fail": "payment"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPENSATED"
        print("✅ Payment failure test passed")
    
    # Test 3: Shipping failure  
    print("🚚 Testing shipping failure...")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url}/create-order", json={
            "customer_id": "test-3",
            "product_id": "product-3",
            "quantity": 1,
            "amount": 150.0,
            "should_fail": "shipping"
        })
        result = response.json()
        assert result["saga_result"]["status"] == "COMPENSATED"
        print("✅ Shipping failure test passed")
    
    print("🎉 All tests passed!")
    return True

if __name__ == "__main__":
    success = asyncio.run(test_services())
    exit(0 if success else 1)
EOF

chmod +x test_saga.py

# README
cat > README.md << 'EOF'
# SAGA Pattern Demo - Working Version

Complete SAGA pattern implementation with latest compatible libraries.

## Quick Start

```bash
cd saga-pattern-demo
docker-compose up --build
```

**Web UI**: http://localhost:5000
**Tests**: `python test_saga.py`

## Features

- ✅ All services working correctly
- ✅ SAGA orchestration & compensation
- ✅ Interactive web interface  
- ✅ Complete test scenarios
- ✅ Real-time logging & monitoring

Test all 4 scenarios: Success, Payment Failure, Inventory Failure, Shipping Failure
EOF

echo "✅ SAGA Demo Created Successfully!"
echo ""
echo "Start: cd $DEMO_DIR && docker-compose up --build"
echo "Web: http://localhost:5000" 
echo "Test: python test_saga.py"