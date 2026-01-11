#!/bin/bash

echo "=== Microservice Decomposition Strategies Demo ==="
echo "Setting up demonstration with three architectures..."

# Create directory structure
mkdir -p {monolith,services/{order,payment,inventory},strangler/{gateway,legacy,new-services},shared}

# Generate package.json for each service
cat > monolith/package.json << 'EOF'
{
  "name": "monolith",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "ws": "^8.14.2"
  }
}
EOF

cat > services/order/package.json << 'EOF'
{
  "name": "order-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0"
  }
}
EOF

cat > services/payment/package.json << 'EOF'
{
  "name": "payment-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > services/inventory/package.json << 'EOF'
{
  "name": "inventory-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > strangler/gateway/package.json << 'EOF'
{
  "name": "strangler-gateway",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "http-proxy-middleware": "^2.0.6"
  }
}
EOF

cat > strangler/legacy/package.json << 'EOF'
{
  "name": "legacy-monolith",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > strangler/new-services/package.json << 'EOF'
{
  "name": "new-payment-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

# Generate Monolith Application
cat > monolith/server.js << 'EOF'
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory data stores
const inventory = {
  'PROD-001': { id: 'PROD-001', name: 'Laptop', stock: 50, price: 999.99 },
  'PROD-002': { id: 'PROD-002', name: 'Mouse', stock: 200, price: 29.99 },
  'PROD-003': { id: 'PROD-003', name: 'Keyboard', stock: 150, price: 79.99 }
};

const orders = [];
const payments = [];

let requestCount = 0;
let errorCount = 0;

// Monolithic endpoints - all capabilities in one service
app.post('/api/monolith/order', async (req, res) => {
  const startTime = Date.now();
  requestCount++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Check inventory (internal function call - microseconds)
    if (!inventory[productId] || inventory[productId].stock < quantity) {
      errorCount++;
      return res.status(400).json({ error: 'Insufficient inventory' });
    }
    
    // Create order (internal function call)
    const order = {
      id: `ORD-${Date.now()}`,
      productId,
      quantity,
      total: inventory[productId].price * quantity,
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    orders.push(order);
    
    // Process payment (internal function call)
    const payment = {
      id: `PAY-${Date.now()}`,
      orderId: order.id,
      amount: order.total,
      status: 'completed',
      processedAt: new Date().toISOString()
    };
    payments.push(payment);
    
    // Update inventory (internal function call)
    inventory[productId].stock -= quantity;
    
    order.status = 'completed';
    
    const latency = Date.now() - startTime;
    res.json({ 
      order, 
      payment, 
      architecture: 'monolith',
      latency: `${latency}ms`,
      hops: 0 
    });
  } catch (error) {
    errorCount++;
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/monolith/metrics', (req, res) => {
  res.json({
    architecture: 'monolith',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? ((errorCount / requestCount) * 100).toFixed(2) + '%' : '0%',
    orders: orders.length,
    avgLatency: '2-5ms'
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3001;
app.listen(PORT, () => console.log(`Monolith running on port ${PORT}`));
EOF

# Generate Order Service
cat > services/order/server.js << 'EOF'
import express from 'express';
import cors from 'cors';
import axios from 'axios';

const app = express();
app.use(cors());
app.use(express.json());

const orders = [];
let requestCount = 0;
let errorCount = 0;

// Service-per-subdomain: Order service coordinates but doesn't own inventory/payment data
app.post('/api/orders', async (req, res) => {
  const startTime = Date.now();
  requestCount++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Network call to inventory service (milliseconds, can fail)
    let inventoryCheck;
    try {
      const inventoryResponse = await axios.post('http://inventory-service:3004/api/inventory/check', 
        { productId, quantity },
        { timeout: 2000 }
      );
      inventoryCheck = inventoryResponse.data;
    } catch (error) {
      errorCount++;
      return res.status(503).json({ 
        error: 'Inventory service unavailable', 
        architecture: 'microservices' 
      });
    }
    
    if (!inventoryCheck.available) {
      errorCount++;
      return res.status(400).json({ error: 'Insufficient inventory' });
    }
    
    // Create order
    const order = {
      id: `ORD-${Date.now()}`,
      productId,
      quantity,
      total: inventoryCheck.price * quantity,
      status: 'pending',
      createdAt: new Date().toISOString()
    };
    orders.push(order);
    
    // Network call to payment service (milliseconds, can fail)
    let payment;
    try {
      const paymentResponse = await axios.post('http://payment-service:3003/api/payments', 
        { orderId: order.id, amount: order.total },
        { timeout: 2000 }
      );
      payment = paymentResponse.data;
    } catch (error) {
      errorCount++;
      order.status = 'payment-failed';
      return res.status(503).json({ 
        error: 'Payment service unavailable', 
        order,
        architecture: 'microservices' 
      });
    }
    
    // Network call to reserve inventory (milliseconds, can fail)
    try {
      await axios.post('http://inventory-service:3004/api/inventory/reserve', 
        { productId, quantity },
        { timeout: 2000 }
      );
    } catch (error) {
      errorCount++;
      return res.status(503).json({ 
        error: 'Failed to reserve inventory', 
        architecture: 'microservices' 
      });
    }
    
    order.status = 'completed';
    
    const latency = Date.now() - startTime;
    res.json({ 
      order, 
      payment,
      architecture: 'microservices',
      latency: `${latency}ms`,
      hops: 3
    });
  } catch (error) {
    errorCount++;
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/orders/metrics', (req, res) => {
  res.json({
    service: 'order',
    requests: requestCount,
    errors: errorCount,
    errorRate: requestCount > 0 ? ((errorCount / requestCount) * 100).toFixed(2) + '%' : '0%',
    orders: orders.length
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'order' }));

const PORT = 3002;
app.listen(PORT, () => console.log(`Order Service running on port ${PORT}`));
EOF

# Generate Payment Service
cat > services/payment/server.js << 'EOF'
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const payments = [];
let requestCount = 0;

app.post('/api/payments', (req, res) => {
  requestCount++;
  const { orderId, amount } = req.body;
  
  // Simulate payment processing latency
  setTimeout(() => {
    const payment = {
      id: `PAY-${Date.now()}`,
      orderId,
      amount,
      status: 'completed',
      processedAt: new Date().toISOString()
    };
    payments.push(payment);
    
    res.json(payment);
  }, 20); // 20ms processing time
});

app.get('/api/payments/metrics', (req, res) => {
  res.json({
    service: 'payment',
    requests: requestCount,
    payments: payments.length,
    avgLatency: '20ms'
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'payment' }));

const PORT = 3003;
app.listen(PORT, () => console.log(`Payment Service running on port ${PORT}`));
EOF

# Generate Inventory Service
cat > services/inventory/server.js << 'EOF'
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const inventory = {
  'PROD-001': { id: 'PROD-001', name: 'Laptop', stock: 50, price: 999.99 },
  'PROD-002': { id: 'PROD-002', name: 'Mouse', stock: 200, price: 29.99 },
  'PROD-003': { id: 'PROD-003', name: 'Keyboard', stock: 150, price: 79.99 }
};

let requestCount = 0;

app.post('/api/inventory/check', (req, res) => {
  requestCount++;
  const { productId, quantity } = req.body;
  
  const product = inventory[productId];
  if (!product) {
    return res.json({ available: false });
  }
  
  res.json({
    available: product.stock >= quantity,
    stock: product.stock,
    price: product.price
  });
});

app.post('/api/inventory/reserve', (req, res) => {
  requestCount++;
  const { productId, quantity } = req.body;
  
  if (inventory[productId] && inventory[productId].stock >= quantity) {
    inventory[productId].stock -= quantity;
    res.json({ success: true, remaining: inventory[productId].stock });
  } else {
    res.status(400).json({ success: false });
  }
});

app.get('/api/inventory/metrics', (req, res) => {
  res.json({
    service: 'inventory',
    requests: requestCount,
    products: Object.keys(inventory).length
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'inventory' }));

const PORT = 3004;
app.listen(PORT, () => console.log(`Inventory Service running on port ${PORT}`));
EOF

# Generate Strangler Gateway
cat > strangler/gateway/server.js << 'EOF'
import express from 'express';
import cors from 'cors';
import axios from 'axios';

const app = express();
app.use(cors());
app.use(express.json());

// Feature flags for gradual migration
const featureFlags = {
  useNewPaymentService: 0.5, // 50% traffic to new service
  useNewInventoryService: 0.0  // 0% traffic (not migrated yet)
};

let totalRequests = 0;
let newServiceRequests = 0;
let legacyRequests = 0;

app.post('/api/strangler/order', async (req, res) => {
  const startTime = Date.now();
  totalRequests++;
  
  try {
    const { productId, quantity } = req.body;
    
    // Decision: Route payment to new service or legacy monolith
    const useNewPayment = Math.random() < featureFlags.useNewPaymentService;
    
    if (useNewPayment) {
      // Strangler pattern: New service handles payment
      newServiceRequests++;
      
      // Call legacy for inventory (not yet migrated)
      const inventoryResponse = await axios.post('http://legacy-monolith:3006/api/inventory/check',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      if (!inventoryResponse.data.available) {
        return res.status(400).json({ error: 'Insufficient inventory' });
      }
      
      const order = {
        id: `ORD-${Date.now()}`,
        productId,
        quantity,
        total: inventoryResponse.data.price * quantity,
        status: 'pending'
      };
      
      // NEW: Call new payment service
      const paymentResponse = await axios.post('http://new-payment-service:3007/api/payments',
        { orderId: order.id, amount: order.total },
        { timeout: 2000 }
      );
      
      // Call legacy to reserve inventory
      await axios.post('http://legacy-monolith:3006/api/inventory/reserve',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      order.status = 'completed';
      const latency = Date.now() - startTime;
      
      res.json({
        order,
        payment: paymentResponse.data,
        architecture: 'strangler',
        route: 'new-payment',
        latency: `${latency}ms`,
        migrationProgress: '50%'
      });
    } else {
      // Route to legacy monolith
      legacyRequests++;
      
      const response = await axios.post('http://legacy-monolith:3006/api/order',
        { productId, quantity },
        { timeout: 2000 }
      );
      
      const latency = Date.now() - startTime;
      
      res.json({
        ...response.data,
        architecture: 'strangler',
        route: 'legacy',
        latency: `${latency}ms`,
        migrationProgress: '50%'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/strangler/metrics', (req, res) => {
  res.json({
    architecture: 'strangler',
    totalRequests,
    newServiceRequests,
    legacyRequests,
    migrationProgress: {
      payment: `${featureFlags.useNewPaymentService * 100}%`,
      inventory: `${featureFlags.useNewInventoryService * 100}%`
    },
    trafficSplit: {
      new: ((newServiceRequests / totalRequests) * 100).toFixed(1) + '%',
      legacy: ((legacyRequests / totalRequests) * 100).toFixed(1) + '%'
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'strangler-gateway' }));

const PORT = 3005;
app.listen(PORT, () => console.log(`Strangler Gateway running on port ${PORT}`));
EOF

# Generate Legacy Monolith (for strangler pattern)
cat > strangler/legacy/server.js << 'EOF'
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const inventory = {
  'PROD-001': { id: 'PROD-001', name: 'Laptop', stock: 50, price: 999.99 },
  'PROD-002': { id: 'PROD-002', name: 'Mouse', stock: 200, price: 29.99 },
  'PROD-003': { id: 'PROD-003', name: 'Keyboard', stock: 150, price: 79.99 }
};

const orders = [];
const payments = [];

app.post('/api/order', (req, res) => {
  const { productId, quantity } = req.body;
  
  if (!inventory[productId] || inventory[productId].stock < quantity) {
    return res.status(400).json({ error: 'Insufficient inventory' });
  }
  
  const order = {
    id: `ORD-${Date.now()}`,
    productId,
    quantity,
    total: inventory[productId].price * quantity,
    status: 'pending'
  };
  orders.push(order);
  
  const payment = {
    id: `PAY-${Date.now()}`,
    orderId: order.id,
    amount: order.total,
    status: 'completed'
  };
  payments.push(payment);
  
  inventory[productId].stock -= quantity;
  order.status = 'completed';
  
  res.json({ order, payment });
});

app.post('/api/inventory/check', (req, res) => {
  const { productId, quantity } = req.body;
  const product = inventory[productId];
  
  if (!product) {
    return res.json({ available: false });
  }
  
  res.json({
    available: product.stock >= quantity,
    stock: product.stock,
    price: product.price
  });
});

app.post('/api/inventory/reserve', (req, res) => {
  const { productId, quantity } = req.body;
  
  if (inventory[productId] && inventory[productId].stock >= quantity) {
    inventory[productId].stock -= quantity;
    res.json({ success: true });
  } else {
    res.status(400).json({ success: false });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'legacy-monolith' }));

const PORT = 3006;
app.listen(PORT, () => console.log(`Legacy Monolith running on port ${PORT}`));
EOF

# Generate New Payment Service (for strangler pattern)
cat > strangler/new-services/server.js << 'EOF'
import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const payments = [];

app.post('/api/payments', (req, res) => {
  const { orderId, amount } = req.body;
  
  const payment = {
    id: `PAY-NEW-${Date.now()}`,
    orderId,
    amount,
    status: 'completed',
    processor: 'new-service',
    processedAt: new Date().toISOString()
  };
  payments.push(payment);
  
  res.json(payment);
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'new-payment' }));

const PORT = 3007;
app.listen(PORT, () => console.log(`New Payment Service running on port ${PORT}`));
EOF

# Generate Dashboard
cat > shared/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Microservice Decomposition Strategies</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 30px;
        }
        
        h1 {
            color: #1a202c;
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .subtitle {
            color: #718096;
            font-size: 16px;
        }
        
        .architectures {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .architecture-card {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .arch-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid #e2e8f0;
        }
        
        .arch-title {
            font-size: 20px;
            font-weight: 600;
            color: #2d3748;
        }
        
        .arch-status {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .status-healthy {
            background: #c6f6d5;
            color: #22543d;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .metric {
            background: #f7fafc;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #4299e1;
        }
        
        .metric-label {
            font-size: 12px;
            color: #718096;
            text-transform: uppercase;
            margin-bottom: 5px;
        }
        
        .metric-value {
            font-size: 24px;
            font-weight: 700;
            color: #2d3748;
        }
        
        .metric-unit {
            font-size: 14px;
            color: #a0aec0;
        }
        
        .action-button {
            width: 100%;
            padding: 12px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s;
        }
        
        .action-button:hover {
            transform: translateY(-2px);
        }
        
        .action-button:active {
            transform: translateY(0);
        }
        
        .logs-section {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .logs-header {
            font-size: 18px;
            font-weight: 600;
            color: #2d3748;
            margin-bottom: 15px;
        }
        
        .logs-container {
            background: #1a202c;
            padding: 20px;
            border-radius: 8px;
            max-height: 300px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 13px;
        }
        
        .log-entry {
            padding: 8px 0;
            border-bottom: 1px solid #2d3748;
            color: #e2e8f0;
        }
        
        .log-entry:last-child {
            border-bottom: none;
        }
        
        .log-time {
            color: #4299e1;
        }
        
        .log-arch {
            color: #48bb78;
            font-weight: 600;
        }
        
        .log-latency {
            color: #ed8936;
        }
        
        .comparison-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 10px;
            margin-top: 20px;
        }
        
        .comparison-item {
            background: #f7fafc;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        
        .comparison-label {
            font-size: 12px;
            color: #718096;
            margin-bottom: 5px;
        }
        
        .comparison-value {
            font-size: 18px;
            font-weight: 700;
            color: #2d3748;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏗️ Microservice Decomposition Strategies</h1>
            <p class="subtitle">Compare monolithic, service-per-subdomain, and strangler pattern architectures</p>
        </div>
        
        <div class="architectures">
            <div class="architecture-card">
                <div class="arch-header">
                    <div class="arch-title">Monolithic</div>
                    <div class="arch-status status-healthy">Healthy</div>
                </div>
                <div class="metrics-grid">
                    <div class="metric">
                        <div class="metric-label">Requests</div>
                        <div class="metric-value" id="monolith-requests">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Errors</div>
                        <div class="metric-value" id="monolith-errors">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Avg Latency</div>
                        <div class="metric-value">2-5<span class="metric-unit">ms</span></div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Service Hops</div>
                        <div class="metric-value">0</div>
                    </div>
                </div>
                <button class="action-button" onclick="testArchitecture('monolith')">
                    Create Order (Monolith)
                </button>
            </div>
            
            <div class="architecture-card">
                <div class="arch-header">
                    <div class="arch-title">Microservices</div>
                    <div class="arch-status status-healthy">Healthy</div>
                </div>
                <div class="metrics-grid">
                    <div class="metric">
                        <div class="metric-label">Requests</div>
                        <div class="metric-value" id="microservices-requests">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Errors</div>
                        <div class="metric-value" id="microservices-errors">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Avg Latency</div>
                        <div class="metric-value">30-50<span class="metric-unit">ms</span></div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Service Hops</div>
                        <div class="metric-value">3</div>
                    </div>
                </div>
                <button class="action-button" onclick="testArchitecture('microservices')">
                    Create Order (Microservices)
                </button>
            </div>
            
            <div class="architecture-card">
                <div class="arch-header">
                    <div class="arch-title">Strangler Pattern</div>
                    <div class="arch-status status-healthy">Migrating</div>
                </div>
                <div class="metrics-grid">
                    <div class="metric">
                        <div class="metric-label">Total Requests</div>
                        <div class="metric-value" id="strangler-requests">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Migration Progress</div>
                        <div class="metric-value" id="strangler-progress">50<span class="metric-unit">%</span></div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">New Service</div>
                        <div class="metric-value" id="strangler-new">0</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Legacy</div>
                        <div class="metric-value" id="strangler-legacy">0</div>
                    </div>
                </div>
                <button class="action-button" onclick="testArchitecture('strangler')">
                    Create Order (Strangler)
                </button>
            </div>
        </div>
        
        <div class="logs-section">
            <div class="logs-header">📊 Request Flow Analysis</div>
            <div class="logs-container" id="logs"></div>
            
            <div class="comparison-grid">
                <div class="comparison-item">
                    <div class="comparison-label">Total Requests</div>
                    <div class="comparison-value" id="total-requests">0</div>
                </div>
                <div class="comparison-item">
                    <div class="comparison-label">Avg Latency (All)</div>
                    <div class="comparison-value" id="avg-latency">0ms</div>
                </div>
                <div class="comparison-item">
                    <div class="comparison-label">Success Rate</div>
                    <div class="comparison-value" id="success-rate">100%</div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        const logs = [];
        let totalRequests = 0;
        let totalLatency = 0;
        let successfulRequests = 0;
        
        async function testArchitecture(type) {
            const productId = ['PROD-001', 'PROD-002', 'PROD-003'][Math.floor(Math.random() * 3)];
            const quantity = Math.floor(Math.random() * 3) + 1;
            
            try {
                let response;
                if (type === 'monolith') {
                    response = await fetch('http://localhost:3001/api/monolith/order', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ productId, quantity })
                    });
                } else if (type === 'microservices') {
                    response = await fetch('http://localhost:3002/api/orders', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ productId, quantity })
                    });
                } else if (type === 'strangler') {
                    response = await fetch('http://localhost:3005/api/strangler/order', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ productId, quantity })
                    });
                }
                
                const data = await response.json();
                
                totalRequests++;
                if (response.ok) {
                    successfulRequests++;
                }
                
                const latencyMs = parseInt(data.latency) || 0;
                totalLatency += latencyMs;
                
                addLog(type, data, response.ok);
                updateMetrics(type);
                updateGlobalMetrics();
            } catch (error) {
                console.error('Error:', error);
                addLog(type, { error: error.message }, false);
            }
        }
        
        function addLog(architecture, data, success) {
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = document.createElement('div');
            logEntry.className = 'log-entry';
            
            const status = success ? '✓' : '✗';
            const route = data.route ? ` [${data.route}]` : '';
            const latency = data.latency || 'N/A';
            const hops = data.hops !== undefined ? `${data.hops} hops` : '';
            
            logEntry.innerHTML = `
                <span class="log-time">${timestamp}</span>
                <span class="log-arch">[${architecture.toUpperCase()}]</span>${route}
                ${status} Order ${data.order?.id || 'failed'}
                <span class="log-latency">${latency} ${hops}</span>
            `;
            
            const logsContainer = document.getElementById('logs');
            logsContainer.insertBefore(logEntry, logsContainer.firstChild);
            
            if (logsContainer.children.length > 50) {
                logsContainer.removeChild(logsContainer.lastChild);
            }
        }
        
        async function updateMetrics(type) {
            try {
                if (type === 'monolith') {
                    const response = await fetch('http://localhost:3001/api/monolith/metrics');
                    const data = await response.json();
                    document.getElementById('monolith-requests').textContent = data.requests;
                    document.getElementById('monolith-errors').textContent = data.errors;
                } else if (type === 'microservices') {
                    const response = await fetch('http://localhost:3002/api/orders/metrics');
                    const data = await response.json();
                    document.getElementById('microservices-requests').textContent = data.requests;
                    document.getElementById('microservices-errors').textContent = data.errors;
                } else if (type === 'strangler') {
                    const response = await fetch('http://localhost:3005/api/strangler/metrics');
                    const data = await response.json();
                    document.getElementById('strangler-requests').textContent = data.totalRequests;
                    document.getElementById('strangler-new').textContent = data.newServiceRequests;
                    document.getElementById('strangler-legacy').textContent = data.legacyRequests;
                }
            } catch (error) {
                console.error('Error updating metrics:', error);
            }
        }
        
        function updateGlobalMetrics() {
            document.getElementById('total-requests').textContent = totalRequests;
            
            const avgLatency = totalRequests > 0 ? Math.round(totalLatency / totalRequests) : 0;
            document.getElementById('avg-latency').textContent = avgLatency + 'ms';
            
            const successRate = totalRequests > 0 ? ((successfulRequests / totalRequests) * 100).toFixed(1) : 100;
            document.getElementById('success-rate').textContent = successRate + '%';
        }
        
        // Auto-refresh metrics every 5 seconds
        setInterval(() => {
            ['monolith', 'microservices', 'strangler'].forEach(updateMetrics);
        }, 5000);
    </script>
</body>
</html>
EOF

# Generate Dockerfiles
cat > monolith/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

cat > services/order/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

cat > services/payment/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3003
CMD ["node", "server.js"]
EOF

cat > services/inventory/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3004
CMD ["node", "server.js"]
EOF

cat > strangler/gateway/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3005
CMD ["node", "server.js"]
EOF

cat > strangler/legacy/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3006
CMD ["node", "server.js"]
EOF

cat > strangler/new-services/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3007
CMD ["node", "server.js"]
EOF

# Generate docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  monolith:
    build: ./monolith
    ports:
      - "3001:3001"
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  order-service:
    build: ./services/order
    ports:
      - "3002:3002"
    depends_on:
      - payment-service
      - inventory-service
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  payment-service:
    build: ./services/payment
    ports:
      - "3003:3003"
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3003/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  inventory-service:
    build: ./services/inventory
    ports:
      - "3004:3004"
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3004/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  strangler-gateway:
    build: ./strangler/gateway
    ports:
      - "3005:3005"
    depends_on:
      - legacy-monolith
      - new-payment-service
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3005/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  legacy-monolith:
    build: ./strangler/legacy
    ports:
      - "3006:3006"
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3006/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  new-payment-service:
    build: ./strangler/new-services
    ports:
      - "3007:3007"
    networks:
      - decomposition-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3007/health"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  decomposition-net:
    driver: bridge
EOF

# Build and run
echo ""
echo "Building Docker containers..."
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 15

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "🎯 Access the dashboard: http://localhost:8080"
echo ""
echo "📊 Architecture endpoints:"
echo "   Monolith:     http://localhost:3001"
echo "   Order Service: http://localhost:3002"
echo "   Payment Service: http://localhost:3003"
echo "   Inventory Service: http://localhost:3004"
echo "   Strangler Gateway: http://localhost:3005"
echo ""
echo "🧪 Run tests with: bash test.sh"
echo "🧹 Cleanup with: bash cleanup.sh"
echo ""

# Start simple HTTP server for dashboard
cd shared && python3 -m http.server 8080 &
HTTP_PID=$!
echo $HTTP_PID > ../.http_pid

echo "Dashboard server started (PID: $HTTP_PID)"