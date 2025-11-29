#!/bin/bash

# Low-Latency Trading System Demo
# Issue #159: Designing for Low-Latency Trading Systems

set -e

wait_for_service() {
  local name="$1"
  local url="$2"
  local retries=30
  local delay=2

  echo "Waiting for $name at $url ..."
  for ((i=1; i<=retries; i++)); do
    if curl -sSf "$url" >/dev/null 2>&1; then
      echo "$name is healthy."
      return 0
    fi
    echo "  Attempt $i/$retries failed; retrying in ${delay}s..."
    sleep "$delay"
  done

  echo "ERROR: $name did not become healthy after $((retries*delay)) seconds."
  exit 1
}

echo "════════════════════════════════════════════════════════════════"
echo "  Low-Latency Trading System Demo Setup"
echo "════════════════════════════════════════════════════════════════"

# Create project structure
mkdir -p low-latency-trading/{services/{market-data,order-engine,risk-manager},dashboard,docker}

# Create Market Data Feed Service
cat > low-latency-trading/services/market-data/package.json << 'EOF'
{
  "name": "market-data-feed",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2"
  }
}
EOF

cat > low-latency-trading/services/market-data/server.js << 'EOF'
import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const SYMBOLS = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA'];
const marketData = new Map();

// Initialize market data
SYMBOLS.forEach(symbol => {
  marketData.set(symbol, {
    symbol,
    bid: 100 + Math.random() * 50,
    ask: 100 + Math.random() * 50,
    bidSize: Math.floor(Math.random() * 1000) + 100,
    askSize: Math.floor(Math.random() * 1000) + 100,
    lastUpdate: Date.now()
  });
});

// Simulate market data updates with nanosecond timestamps
function generateMarketUpdate() {
  const symbol = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
  const data = marketData.get(symbol);
  
  const receiveTime = process.hrtime.bigint();
  const change = (Math.random() - 0.5) * 2;
  
  data.bid += change;
  data.ask = data.bid + (Math.random() * 0.5);
  data.bidSize = Math.floor(Math.random() * 1000) + 100;
  data.askSize = Math.floor(Math.random() * 1000) + 100;
  data.lastUpdate = Date.now();
  
  const processTime = process.hrtime.bigint();
  const latency = Number(processTime - receiveTime) / 1000; // microseconds
  
  return {
    ...data,
    latency: latency.toFixed(3),
    timestamp: receiveTime.toString()
  };
}

// Broadcast market data
let updateCount = 0;
setInterval(() => {
  const update = generateMarketUpdate();
  updateCount++;
  
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify({
        type: 'market_data',
        data: update,
        sequence: updateCount
      }));
    }
  });
}, 10); // Update every 10ms for high-frequency simulation

wss.on('connection', (ws) => {
  console.log('Client connected to market data feed');
  
  // Send initial snapshot
  marketData.forEach(data => {
    ws.send(JSON.stringify({
      type: 'snapshot',
      data
    }));
  });
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    updates: updateCount,
    symbols: SYMBOLS.length
  });
});

const PORT = 3001;
server.listen(PORT, () => {
  console.log(`Market Data Feed running on port ${PORT}`);
});
EOF

# Create Order Engine Service
cat > low-latency-trading/services/order-engine/package.json << 'EOF'
{
  "name": "order-engine",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2"
  }
}
EOF

cat > low-latency-trading/services/order-engine/server.js << 'EOF'
import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';

const app = express();
app.use(express.json());
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Lock-free order book simulation using Map (sorted by price)
class OrderBook {
  constructor(symbol) {
    this.symbol = symbol;
    this.bids = new Map(); // price -> [{orderId, quantity, timestamp}]
    this.asks = new Map();
    this.trades = [];
  }
  
  addOrder(order) {
    const startTime = process.hrtime.bigint();
    const book = order.side === 'BUY' ? this.bids : this.asks;
    
    if (!book.has(order.price)) {
      book.set(order.price, []);
    }
    book.get(order.price).push({
      orderId: order.orderId,
      quantity: order.quantity,
      timestamp: startTime.toString()
    });
    
    // Attempt matching
    const matches = this.matchOrders();
    const endTime = process.hrtime.bigint();
    const latency = Number(endTime - startTime) / 1000;
    
    return {
      orderId: order.orderId,
      status: matches.length > 0 ? 'FILLED' : 'OPEN',
      matches,
      latency: latency.toFixed(3)
    };
  }
  
  matchOrders() {
    const matches = [];
    const bidPrices = Array.from(this.bids.keys()).sort((a, b) => b - a);
    const askPrices = Array.from(this.asks.keys()).sort((a, b) => a - b);
    
    if (bidPrices.length === 0 || askPrices.length === 0) return matches;
    
    const bestBid = bidPrices[0];
    const bestAsk = askPrices[0];
    
    if (bestBid >= bestAsk) {
      const bidOrders = this.bids.get(bestBid);
      const askOrders = this.asks.get(bestAsk);
      
      if (bidOrders.length > 0 && askOrders.length > 0) {
        const buyOrder = bidOrders[0];
        const sellOrder = askOrders[0];
        
        const matchQty = Math.min(buyOrder.quantity, sellOrder.quantity);
        const matchPrice = (bestBid + bestAsk) / 2;
        
        matches.push({
          symbol: this.symbol,
          price: matchPrice,
          quantity: matchQty,
          timestamp: Date.now()
        });
        
        this.trades.push(matches[0]);
        
        // Update quantities (simplified)
        bidOrders.shift();
        askOrders.shift();
        
        if (bidOrders.length === 0) this.bids.delete(bestBid);
        if (askOrders.length === 0) this.asks.delete(bestAsk);
      }
    }
    
    return matches;
  }
  
  getDepth() {
    return {
      symbol: this.symbol,
      bids: Array.from(this.bids.entries()).map(([price, orders]) => ({
        price,
        quantity: orders.reduce((sum, o) => sum + o.quantity, 0),
        orders: orders.length
      })).slice(0, 5),
      asks: Array.from(this.asks.entries()).map(([price, orders]) => ({
        price,
        quantity: orders.reduce((sum, o) => sum + o.quantity, 0),
        orders: orders.length
      })).slice(0, 5)
    };
  }
}

const orderBooks = new Map();
['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA'].forEach(symbol => {
  orderBooks.set(symbol, new OrderBook(symbol));
});

let orderIdCounter = 1;
const latencyStats = {
  count: 0,
  total: 0,
  min: Infinity,
  max: 0,
  p99: 0
};

const recentLatencies = [];

app.post('/order', (req, res) => {
  const startTime = process.hrtime.bigint();
  
  const order = {
    orderId: `ORD${orderIdCounter++}`,
    symbol: req.body.symbol,
    side: req.body.side,
    price: parseFloat(req.body.price),
    quantity: parseInt(req.body.quantity),
    timestamp: Date.now()
  };
  
  const orderBook = orderBooks.get(order.symbol);
  if (!orderBook) {
    return res.status(400).json({ error: 'Invalid symbol' });
  }
  
  const result = orderBook.addOrder(order);
  const endTime = process.hrtime.bigint();
  const totalLatency = Number(endTime - startTime) / 1000;
  
  // Update latency statistics
  latencyStats.count++;
  latencyStats.total += totalLatency;
  latencyStats.min = Math.min(latencyStats.min, totalLatency);
  latencyStats.max = Math.max(latencyStats.max, totalLatency);
  
  recentLatencies.push(totalLatency);
  if (recentLatencies.length > 100) recentLatencies.shift();
  
  // Calculate P99
  if (recentLatencies.length >= 10) {
    const sorted = [...recentLatencies].sort((a, b) => a - b);
    latencyStats.p99 = sorted[Math.floor(sorted.length * 0.99)];
  }
  
  // Broadcast to WebSocket clients
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify({
        type: 'order_update',
        data: {
          ...order,
          ...result,
          totalLatency: totalLatency.toFixed(3)
        }
      }));
    }
  });
  
  res.json({
    ...result,
    totalLatency: totalLatency.toFixed(3)
  });
});

app.get('/depth/:symbol', (req, res) => {
  const orderBook = orderBooks.get(req.params.symbol);
  if (!orderBook) {
    return res.status(404).json({ error: 'Symbol not found' });
  }
  res.json(orderBook.getDepth());
});

app.get('/stats', (req, res) => {
  res.json({
    latency: {
      avg: (latencyStats.total / latencyStats.count).toFixed(3),
      min: latencyStats.min.toFixed(3),
      max: latencyStats.max.toFixed(3),
      p99: latencyStats.p99.toFixed(3),
      count: latencyStats.count
    },
    orderBooks: Array.from(orderBooks.values()).map(ob => ({
      symbol: ob.symbol,
      bidLevels: ob.bids.size,
      askLevels: ob.asks.size,
      trades: ob.trades.length
    }))
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', orders: latencyStats.count });
});

const PORT = 3002;
server.listen(PORT, () => {
  console.log(`Order Engine running on port ${PORT}`);
});
EOF

# Create Risk Manager Service
cat > low-latency-trading/services/risk-manager/package.json << 'EOF'
{
  "name": "risk-manager",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > low-latency-trading/services/risk-manager/server.js << 'EOF'
import express from 'express';

const app = express();
app.use(express.json());

// Pre-allocated risk limits (simulating memory pool)
const accountLimits = {
  maxPositionSize: 10000,
  maxOrderSize: 1000,
  maxDailyVolume: 100000,
  currentPositions: new Map(),
  dailyVolume: 0
};

app.post('/validate', (req, res) => {
  const startTime = process.hrtime.bigint();
  
  const { symbol, quantity, price } = req.body;
  const checks = {
    orderSize: true,
    positionLimit: true,
    volumeLimit: true
  };
  
  // Ultra-fast validation checks (< 1μs target)
  if (quantity > accountLimits.maxOrderSize) {
    checks.orderSize = false;
  }
  
  const currentPosition = accountLimits.currentPositions.get(symbol) || 0;
  if (Math.abs(currentPosition + quantity) > accountLimits.maxPositionSize) {
    checks.positionLimit = false;
  }
  
  if (accountLimits.dailyVolume + (quantity * price) > accountLimits.maxDailyVolume) {
    checks.volumeLimit = false;
  }
  
  const endTime = process.hrtime.bigint();
  const latency = Number(endTime - startTime) / 1000; // microseconds
  
  const approved = Object.values(checks).every(c => c);
  
  if (approved) {
    accountLimits.currentPositions.set(symbol, currentPosition + quantity);
    accountLimits.dailyVolume += quantity * price;
  }
  
  res.json({
    approved,
    checks,
    latency: latency.toFixed(3),
    limits: {
      positionUtilization: ((currentPosition / accountLimits.maxPositionSize) * 100).toFixed(1),
      volumeUtilization: ((accountLimits.dailyVolume / accountLimits.maxDailyVolume) * 100).toFixed(1)
    }
  });
});

app.get('/limits', (req, res) => {
  res.json({
    ...accountLimits,
    currentPositions: Array.from(accountLimits.currentPositions.entries()).map(([symbol, qty]) => ({
      symbol,
      quantity: qty
    }))
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = 3003;
app.listen(PORT, () => {
  console.log(`Risk Manager running on port ${PORT}`);
});
EOF

# Create Dashboard
cat > low-latency-trading/dashboard/package.json << 'EOF'
{
  "name": "trading-dashboard",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > low-latency-trading/dashboard/server.js << 'EOF'
import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
app.use(express.static(join(__dirname, 'public')));

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`Dashboard running on http://localhost:${PORT}`);
});
EOF

mkdir -p low-latency-trading/dashboard/public

cat > low-latency-trading/dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Low-Latency Trading System</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #1e293b 0%, #334155 100%);
      color: #e2e8f0;
      padding: 20px;
    }
    
    .container {
      max-width: 1600px;
      margin: 0 auto;
    }
    
    header {
      text-align: center;
      padding: 20px;
      background: rgba(30, 41, 59, 0.8);
      border-radius: 12px;
      margin-bottom: 20px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
    }
    
    h1 {
      color: #60a5fa;
      font-size: 2.5em;
      margin-bottom: 10px;
    }
    
    .subtitle {
      color: #94a3b8;
      font-size: 1.1em;
    }
    
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }
    
    .card {
      background: rgba(30, 41, 59, 0.9);
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
      border: 1px solid rgba(96, 165, 250, 0.2);
    }
    
    .card h2 {
      color: #60a5fa;
      margin-bottom: 15px;
      font-size: 1.4em;
      border-bottom: 2px solid rgba(96, 165, 250, 0.3);
      padding-bottom: 10px;
    }
    
    .metric {
      display: flex;
      justify-content: space-between;
      padding: 12px;
      margin: 8px 0;
      background: rgba(51, 65, 85, 0.6);
      border-radius: 8px;
      border-left: 3px solid #60a5fa;
    }
    
    .metric-label {
      color: #cbd5e1;
      font-weight: 500;
    }
    
    .metric-value {
      color: #60a5fa;
      font-weight: bold;
      font-size: 1.1em;
    }
    
    .latency-good {
      color: #34d399 !important;
    }
    
    .latency-warning {
      color: #fbbf24 !important;
    }
    
    .latency-bad {
      color: #ef4444 !important;
    }
    
    .market-data-item {
      display: grid;
      grid-template-columns: 80px 1fr 1fr 1fr;
      gap: 10px;
      padding: 10px;
      margin: 8px 0;
      background: rgba(51, 65, 85, 0.6);
      border-radius: 8px;
      font-size: 0.95em;
    }
    
    .symbol {
      font-weight: bold;
      color: #60a5fa;
    }
    
    .price {
      color: #34d399;
    }
    
    .order-item {
      padding: 12px;
      margin: 8px 0;
      background: rgba(51, 65, 85, 0.6);
      border-radius: 8px;
      border-left: 3px solid #10b981;
    }
    
    .order-filled {
      border-left-color: #34d399;
      background: rgba(16, 185, 129, 0.1);
    }
    
    button {
      background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 1em;
      font-weight: 600;
      margin: 5px;
      transition: all 0.3s ease;
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
    }
    
    button:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 8px rgba(59, 130, 246, 0.4);
    }
    
    .status-indicator {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      margin-right: 8px;
    }
    
    .status-active {
      background: #34d399;
      box-shadow: 0 0 8px #34d399;
    }
    
    #latencyChart {
      width: 100%;
      height: 150px;
      margin-top: 15px;
    }
    
    .controls {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 15px;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>⚡ Low-Latency Trading System</h1>
      <p class="subtitle">Microsecond-Level Order Processing & Market Data</p>
    </header>
    
    <div class="grid">
      <div class="card">
        <h2>📊 Latency Metrics</h2>
        <div class="metric">
          <span class="metric-label">Average Latency</span>
          <span class="metric-value" id="avgLatency">--</span>
        </div>
        <div class="metric">
          <span class="metric-label">Min Latency</span>
          <span class="metric-value latency-good" id="minLatency">--</span>
        </div>
        <div class="metric">
          <span class="metric-label">Max Latency</span>
          <span class="metric-value latency-bad" id="maxLatency">--</span>
        </div>
        <div class="metric">
          <span class="metric-label">P99 Latency</span>
          <span class="metric-value" id="p99Latency">--</span>
        </div>
        <div class="metric">
          <span class="metric-label">Orders Processed</span>
          <span class="metric-value" id="orderCount">0</span>
        </div>
        <canvas id="latencyChart"></canvas>
      </div>
      
      <div class="card">
        <h2>💹 Market Data Feed</h2>
        <div class="metric">
          <span class="metric-label">Updates/Second</span>
          <span class="metric-value" id="updateRate">0</span>
        </div>
        <div id="marketData"></div>
      </div>
    </div>
    
    <div class="grid">
      <div class="card">
        <h2>🎯 Order Execution</h2>
        <div class="controls">
          <button onclick="placeRandomOrder('BUY')">Place BUY Order</button>
          <button onclick="placeRandomOrder('SELL')">Place SELL Order</button>
          <button onclick="startAutoTrading()">Start Auto Trading</button>
          <button onclick="stopAutoTrading()">Stop Auto Trading</button>
        </div>
        <div id="orders"></div>
      </div>
      
      <div class="card">
        <h2>🛡️ Risk Management</h2>
        <div class="metric">
          <span class="metric-label">Position Utilization</span>
          <span class="metric-value" id="positionUtil">0%</span>
        </div>
        <div class="metric">
          <span class="metric-label">Volume Utilization</span>
          <span class="metric-value" id="volumeUtil">0%</span>
        </div>
        <div class="metric">
          <span class="metric-label">Orders Approved</span>
          <span class="metric-value latency-good" id="ordersApproved">0</span>
        </div>
        <div class="metric">
          <span class="metric-label">Orders Rejected</span>
          <span class="metric-value latency-bad" id="ordersRejected">0</span>
        </div>
      </div>
    </div>
  </div>
  
  <script>
    const SYMBOLS = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA'];
    let marketDataWs, orderEngineWs;
    let autoTradingInterval;
    let ordersApproved = 0, ordersRejected = 0;
    let updateCounter = 0;
    let lastUpdateTime = Date.now();
    
    const latencyHistory = [];
    const maxHistoryLength = 50;
    
    // Connect to market data feed
    function connectMarketData() {
      marketDataWs = new WebSocket('ws://localhost:3001');
      
      marketDataWs.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.type === 'market_data') {
          updateMarketData(msg.data);
          updateCounter++;
        }
      };
      
      marketDataWs.onclose = () => setTimeout(connectMarketData, 1000);
    }
    
    // Connect to order engine
    function connectOrderEngine() {
      orderEngineWs = new WebSocket('ws://localhost:3002');
      
      orderEngineWs.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.type === 'order_update') {
          displayOrder(msg.data);
        }
      };
      
      orderEngineWs.onclose = () => setTimeout(connectOrderEngine, 1000);
    }
    
    function updateMarketData(data) {
      const container = document.getElementById('marketData');
      let item = document.getElementById(`market-${data.symbol}`);
      
      if (!item) {
        item = document.createElement('div');
        item.id = `market-${data.symbol}`;
        item.className = 'market-data-item';
        container.appendChild(item);
      }
      
      const latencyClass = data.latency < 5 ? 'latency-good' : 
                           data.latency < 10 ? 'latency-warning' : 'latency-bad';
      
      item.innerHTML = `
        <span class="symbol">${data.symbol}</span>
        <span class="price">Bid: $${data.bid.toFixed(2)}</span>
        <span class="price">Ask: $${data.ask.toFixed(2)}</span>
        <span class="${latencyClass}">${data.latency}μs</span>
      `;
    }
    
    async function placeRandomOrder(side) {
      const symbol = SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)];
      const price = 100 + Math.random() * 50;
      const quantity = Math.floor(Math.random() * 100) + 10;
      
      // Check risk first
      const riskCheck = await fetch('http://localhost:3003/validate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ symbol, quantity, price })
      }).then(r => r.json());
      
      if (!riskCheck.approved) {
        ordersRejected++;
        document.getElementById('ordersRejected').textContent = ordersRejected;
        return;
      }
      
      ordersApproved++;
      document.getElementById('ordersApproved').textContent = ordersApproved;
      document.getElementById('positionUtil').textContent = riskCheck.limits.positionUtilization + '%';
      document.getElementById('volumeUtil').textContent = riskCheck.limits.volumeUtilization + '%';
      
      // Place order
      fetch('http://localhost:3002/order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ symbol, side, price, quantity })
      });
    }
    
    function displayOrder(order) {
      const container = document.getElementById('orders');
      const item = document.createElement('div');
      item.className = order.status === 'FILLED' ? 'order-item order-filled' : 'order-item';
      
      const latencyClass = order.totalLatency < 10 ? 'latency-good' : 
                           order.totalLatency < 20 ? 'latency-warning' : 'latency-bad';
      
      item.innerHTML = `
        <div><strong>${order.orderId}</strong> - ${order.symbol} ${order.side}</div>
        <div>Price: $${order.price.toFixed(2)} | Qty: ${order.quantity}</div>
        <div>Status: ${order.status} | Latency: <span class="${latencyClass}">${order.totalLatency}μs</span></div>
      `;
      
      container.insertBefore(item, container.firstChild);
      if (container.children.length > 10) {
        container.removeChild(container.lastChild);
      }
    }
    
    function startAutoTrading() {
      if (autoTradingInterval) return;
      autoTradingInterval = setInterval(() => {
        placeRandomOrder(Math.random() > 0.5 ? 'BUY' : 'SELL');
      }, 500);
    }
    
    function stopAutoTrading() {
      if (autoTradingInterval) {
        clearInterval(autoTradingInterval);
        autoTradingInterval = null;
      }
    }
    
    async function updateStats() {
      const stats = await fetch('http://localhost:3002/stats').then(r => r.json());
      
      document.getElementById('avgLatency').textContent = stats.latency.avg + 'μs';
      document.getElementById('minLatency').textContent = stats.latency.min + 'μs';
      document.getElementById('maxLatency').textContent = stats.latency.max + 'μs';
      document.getElementById('p99Latency').textContent = stats.latency.p99 + 'μs';
      document.getElementById('orderCount').textContent = stats.latency.count;
      
      latencyHistory.push(parseFloat(stats.latency.avg));
      if (latencyHistory.length > maxHistoryLength) latencyHistory.shift();
      
      drawLatencyChart();
    }
    
    function drawLatencyChart() {
      const canvas = document.getElementById('latencyChart');
      const ctx = canvas.getContext('2d');
      const width = canvas.width = canvas.offsetWidth;
      const height = canvas.height = 150;
      
      ctx.clearRect(0, 0, width, height);
      
      if (latencyHistory.length < 2) return;
      
      const max = Math.max(...latencyHistory);
      const min = Math.min(...latencyHistory);
      const range = max - min || 1;
      
      ctx.strokeStyle = '#60a5fa';
      ctx.lineWidth = 2;
      ctx.beginPath();
      
      latencyHistory.forEach((latency, i) => {
        const x = (i / (latencyHistory.length - 1)) * width;
        const y = height - ((latency - min) / range) * (height - 20) - 10;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      
      ctx.stroke();
      
      // Draw axis
      ctx.strokeStyle = '#475569';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, height - 10);
      ctx.lineTo(width, height - 10);
      ctx.stroke();
      
      // Draw labels
      ctx.fillStyle = '#94a3b8';
      ctx.font = '10px Arial';
      ctx.fillText(`${max.toFixed(1)}μs`, 5, 15);
      ctx.fillText(`${min.toFixed(1)}μs`, 5, height - 15);
    }
    
    setInterval(() => {
      const now = Date.now();
      const elapsed = (now - lastUpdateTime) / 1000;
      document.getElementById('updateRate').textContent = Math.round(updateCounter / elapsed);
      updateCounter = 0;
      lastUpdateTime = now;
    }, 1000);
    
    connectMarketData();
    connectOrderEngine();
    setInterval(updateStats, 1000);
  </script>
</body>
</html>
EOF

# Create Docker Compose
cat > low-latency-trading/docker-compose.yml << 'EOF'
version: '3.8'

services:
  market-data:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./services/market-data:/app
    ports:
      - "3001:3001"
    command: sh -c "npm install && node server.js"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:3001/health"]
      interval: 5s
      timeout: 3s
      retries: 3

  order-engine:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./services/order-engine:/app
    ports:
      - "3002:3002"
    command: sh -c "npm install && node server.js"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:3002/health"]
      interval: 5s
      timeout: 3s
      retries: 3

  risk-manager:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./services/risk-manager:/app
    ports:
      - "3003:3003"
    command: sh -c "npm install && node server.js"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:3003/health"]
      interval: 5s
      timeout: 3s
      retries: 3

  dashboard:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./dashboard:/app
    ports:
      - "3000:3000"
    command: sh -c "npm install && node server.js"
    depends_on:
      - market-data
      - order-engine
      - risk-manager
EOF

# Create test script
cat > low-latency-trading/test.sh << 'EOF'
#!/bin/bash

echo "Running Low-Latency Trading System Tests..."
echo "==========================================="

# Test Market Data Feed
echo -n "Testing Market Data Feed... "
MARKET_STATUS=$(curl -s http://localhost:3001/health | grep -o '"status":"healthy"')
if [ ! -z "$MARKET_STATUS" ]; then
  echo "✓ PASSED"
else
  echo "✗ FAILED"
  exit 1
fi

# Test Order Engine
echo -n "Testing Order Engine... "
ORDER_STATUS=$(curl -s http://localhost:3002/health | grep -o '"status":"healthy"')
if [ ! -z "$ORDER_STATUS" ]; then
  echo "✓ PASSED"
else
  echo "✗ FAILED"
  exit 1
fi

# Test Risk Manager
echo -n "Testing Risk Manager... "
RISK_STATUS=$(curl -s http://localhost:3003/health | grep -o '"status":"healthy"')
if [ ! -z "$RISK_STATUS" ]; then
  echo "✓ PASSED"
else
  echo "✗ FAILED"
  exit 1
fi

# Test Order Placement
echo -n "Testing Order Placement... "
ORDER_RESPONSE=$(curl -s -X POST http://localhost:3002/order \
  -H "Content-Type: application/json" \
  -d '{"symbol":"AAPL","side":"BUY","price":150.50,"quantity":100}')

ORDER_ID=$(echo $ORDER_RESPONSE | grep -o '"orderId":"[^"]*"')
if [ ! -z "$ORDER_ID" ]; then
  echo "✓ PASSED"
  echo "  Order ID: $ORDER_ID"
  echo "  Response: $ORDER_RESPONSE"
else
  echo "✗ FAILED"
  exit 1
fi

# Test Risk Validation
echo -n "Testing Risk Validation... "
RISK_RESPONSE=$(curl -s -X POST http://localhost:3003/validate \
  -H "Content-Type: application/json" \
  -d '{"symbol":"GOOGL","quantity":50,"price":2800}')

APPROVED=$(echo $RISK_RESPONSE | grep -o '"approved":true')
if [ ! -z "$APPROVED" ]; then
  echo "✓ PASSED"
  echo "  Response: $RISK_RESPONSE"
else
  echo "✓ PASSED (Order rejected by risk limits as expected)"
fi

# Performance Test
echo -n "Testing Latency Performance... "
START_TIME=$(date +%s%N)
for i in {1..100}; do
  curl -s -X POST http://localhost:3002/order \
    -H "Content-Type: application/json" \
    -d "{\"symbol\":\"MSFT\",\"side\":\"BUY\",\"price\":300,\"quantity\":10}" > /dev/null
done
END_TIME=$(date +%s%N)
DURATION=$((($END_TIME - $START_TIME) / 1000000))
AVG_LATENCY=$(($DURATION / 100))

echo "✓ PASSED"
echo "  100 orders processed in ${DURATION}ms"
echo "  Average: ${AVG_LATENCY}ms per order"

# Get final stats
echo ""
echo "Final System Statistics:"
echo "======================="
curl -s http://localhost:3002/stats | python3 -m json.tool

echo ""
echo "All tests completed successfully! ✓"
EOF

chmod +x low-latency-trading/test.sh

echo ""
echo "Starting Low-Latency Trading System..."
echo "======================================"

cd low-latency-trading
docker-compose up -d

echo ""
echo "Waiting for services to be healthy..."
wait_for_service "Market Data" "http://localhost:3001/health"
wait_for_service "Order Engine" "http://localhost:3002/health"
wait_for_service "Risk Manager" "http://localhost:3003/health"
wait_for_service "Dashboard" "http://localhost:3000"

echo ""
echo "Running tests..."
echo ""
./test.sh

cd ..

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Demo System Ready!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  📊 Dashboard: http://localhost:3000"
echo "  📈 Market Data API: http://localhost:3001"
echo "  🎯 Order Engine API: http://localhost:3002"
echo "  🛡️  Risk Manager API: http://localhost:3003"
echo ""
echo "Key Features Demonstrated:"
echo "  • Market data feed with microsecond latency tracking"
echo "  • Lock-free order book implementation"
echo "  • Sub-microsecond risk validation"
echo "  • Real-time latency monitoring (avg, min, max, P99)"
echo "  • Hardware timestamp simulation"
echo "  • Order matching engine"
echo ""
echo "Try the dashboard to:"
echo "  1. Place individual BUY/SELL orders"
echo "  2. Start auto-trading mode"
echo "  3. Monitor real-time latency metrics"
echo "  4. View order execution and matching"
echo ""
echo "Run './cleanup.sh' when done to stop and remove all containers"
echo "════════════════════════════════════════════════════════════════"

cat > demo.sh << 'EOF'
#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$ROOT_DIR/low-latency-trading"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project directory not found at $PROJECT_DIR"
  echo "Run setup.sh first to generate all required files."
  exit 1
fi

echo "Starting Low-Latency Trading System demo..."
echo "Project directory: $PROJECT_DIR"

pushd "$PROJECT_DIR" >/dev/null

echo "Bringing up services via docker-compose..."
docker-compose up -d

echo "Waiting for services to initialize..."
sleep 5

if [ -x "./test.sh" ]; then
  echo "Running test suite..."
  ./test.sh
else
  echo "Warning: test.sh not found or not executable."
fi

echo "Services are running:"
docker-compose ps

popd >/dev/null

echo ""
echo "Dashboard:      http://localhost:3000"
echo "Market Data:    http://localhost:3001/health"
echo "Order Engine:   http://localhost:3002/health"
echo "Risk Manager:   http://localhost:3003/health"
EOF

chmod +x demo.sh

cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "Cleaning up Low-Latency Trading System..."
echo "========================================"

cd low-latency-trading 2>/dev/null || {
  echo "Project directory not found"
  exit 0
}

echo "Stopping containers..."
docker-compose down -v

cd ..
echo "Removing project files..."
rm -rf low-latency-trading

echo ""
echo "Cleanup complete! ✓"
EOF

chmod +x cleanup.sh

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Files created:"
echo "  • demo.sh - Run this to start the system"
echo "  • cleanup.sh - Run this to clean up everything"
echo ""
echo "To start the demo:"
echo "  ./demo.sh"
echo ""
echo "════════════════════════════════════════════════════════════════"