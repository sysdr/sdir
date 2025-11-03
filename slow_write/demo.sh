#!/bin/bash

set -e

echo "================================================"
echo "Slow Log Writes Demo - Setup & Execution"
echo "================================================"
echo ""

# Create project structure
echo "📁 Creating project structure..."
PROJECT_DIR="slow-log-demo"
mkdir -p ${PROJECT_DIR}/{app,dashboard}
cd ${PROJECT_DIR}

# Create package.json
echo "📦 Creating package.json..."
cat > package.json << 'EOF'
{
  "name": "slow-log-demo",
  "version": "1.0.0",
  "description": "Demo of synchronous vs asynchronous logging impact",
  "main": "app/server.js",
  "scripts": {
    "start": "node app/server.js",
    "test": "node app/test.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "autocannon": "^7.12.0"
  }
}
EOF

# Create the main application server
echo "🔧 Creating application server..."
cat > app/server.js << 'EOF'
const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

// Configuration
let config = {
  loggingMode: 'sync', // 'sync' or 'async'
  logDelay: 0, // artificial delay in ms
  maxQueueSize: 10000
};

// Metrics
let metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  avgResponseTime: 0,
  currentThreadsBlocked: 0,
  queueSize: 0,
  droppedLogs: 0,
  responseTimes: []
};

// Async logging queue
let logQueue = [];
let isProcessingQueue = false;

// Synchronous logging (blocking)
function logSync(message) {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  const logEntry = `[${timestamp}] ${message}\n`;
  
  // Artificial delay to simulate slow log service
  if (config.logDelay > 0) {
    const until = Date.now() + config.logDelay;
    while (Date.now() < until) {
      // Busy wait - simulates blocking I/O
    }
  }
  
  // Write to file (synchronous)
  try {
    fs.appendFileSync('/tmp/app.log', logEntry);
  } catch (err) {
    console.error('Log write failed:', err.message);
  }
  
  return Date.now() - start;
}

// Asynchronous logging (non-blocking)
function logAsync(message) {
  const timestamp = new Date().toISOString();
  const logEntry = `[${timestamp}] ${message}\n`;
  
  // Add to queue
  if (logQueue.length < config.maxQueueSize) {
    logQueue.push(logEntry);
    metrics.queueSize = logQueue.length;
  } else {
    metrics.droppedLogs++;
  }
  
  // Start processing if not already running
  if (!isProcessingQueue) {
    processLogQueue();
  }
  
  return 0; // Non-blocking, returns immediately
}

// Process log queue asynchronously
async function processLogQueue() {
  if (isProcessingQueue) return;
  isProcessingQueue = true;
  
  while (logQueue.length > 0) {
    const entry = logQueue.shift();
    metrics.queueSize = logQueue.length;
    
    // Artificial delay
    if (config.logDelay > 0) {
      await new Promise(resolve => setTimeout(resolve, config.logDelay));
    }
    
    // Write to file
    try {
      fs.appendFileSync('/tmp/app.log', entry);
    } catch (err) {
      console.error('Log write failed:', err.message);
    }
  }
  
  isProcessingQueue = false;
}

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    metrics.totalRequests++;
    metrics.responseTimes.push(duration);
    
    // Keep only last 100 response times
    if (metrics.responseTimes.length > 100) {
      metrics.responseTimes.shift();
    }
    
    // Calculate average
    const sum = metrics.responseTimes.reduce((a, b) => a + b, 0);
    metrics.avgResponseTime = Math.round(sum / metrics.responseTimes.length);
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      metrics.successfulRequests++;
    } else {
      metrics.failedRequests++;
    }
  });
  
  next();
});

app.use(express.json());
app.use(express.static('dashboard'));

// API endpoint - simulates business logic
app.get('/api/process', (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  
  try {
    // Simulate some processing
    let result = 0;
    for (let i = 0; i < 1000; i++) {
      result += Math.sqrt(i);
    }
    
    // Log the request
    const logTime = config.loggingMode === 'sync' 
      ? logSync(`Processing request ${requestId}`)
      : logAsync(`Processing request ${requestId}`);
    
    if (config.loggingMode === 'sync' && logTime > 100) {
      metrics.currentThreadsBlocked++;
    }
    
    res.json({
      success: true,
      requestId,
      result: Math.round(result),
      logMode: config.loggingMode
    });
    
    if (config.loggingMode === 'sync' && logTime > 100) {
      metrics.currentThreadsBlocked = Math.max(0, metrics.currentThreadsBlocked - 1);
    }
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get current metrics
app.get('/api/metrics', (req, res) => {
  res.json(metrics);
});

// Get current configuration
app.get('/api/config', (req, res) => {
  res.json(config);
});

// Update configuration
app.post('/api/config', (req, res) => {
  const { loggingMode, logDelay } = req.body;
  
  if (loggingMode) {
    config.loggingMode = loggingMode;
  }
  
  if (logDelay !== undefined) {
    config.logDelay = parseInt(logDelay);
  }
  
  // Reset metrics when changing config
  metrics.totalRequests = 0;
  metrics.successfulRequests = 0;
  metrics.failedRequests = 0;
  metrics.avgResponseTime = 0;
  metrics.currentThreadsBlocked = 0;
  metrics.droppedLogs = 0;
  metrics.responseTimes = [];
  
  res.json({ success: true, config });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
  console.log(`📊 Dashboard: http://localhost:${PORT}`);
  console.log(`📝 Logging mode: ${config.loggingMode}`);
});
EOF

# Create the dashboard HTML
echo "🎨 Creating dashboard..."
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Slow Log Writes Demo</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
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
      border-radius: 16px;
      padding: 30px;
      margin-bottom: 20px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
    }

    h1 {
      color: #2d3748;
      font-size: 32px;
      margin-bottom: 10px;
    }

    .subtitle {
      color: #718096;
      font-size: 16px;
    }

    .controls {
      background: white;
      border-radius: 16px;
      padding: 25px;
      margin-bottom: 20px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
    }

    .control-group {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }

    .control-item {
      display: flex;
      flex-direction: column;
    }

    label {
      font-weight: 600;
      color: #4a5568;
      margin-bottom: 8px;
      font-size: 14px;
    }

    select, input[type="range"] {
      padding: 10px;
      border: 2px solid #e2e8f0;
      border-radius: 8px;
      font-size: 14px;
      transition: border-color 0.3s;
    }

    select:focus {
      outline: none;
      border-color: #667eea;
    }

    input[type="range"] {
      -webkit-appearance: none;
      height: 8px;
      background: #e2e8f0;
      border: none;
    }

    input[type="range"]::-webkit-slider-thumb {
      -webkit-appearance: none;
      width: 20px;
      height: 20px;
      background: #667eea;
      border-radius: 50%;
      cursor: pointer;
    }

    .delay-value {
      color: #667eea;
      font-weight: 600;
      font-size: 16px;
    }

    .button-group {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }

    button {
      padding: 12px 24px;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }

    .btn-primary {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }

    .btn-primary:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 12px rgba(102, 126, 234, 0.4);
    }

    .btn-danger {
      background: #f56565;
      color: white;
    }

    .btn-danger:hover {
      background: #e53e3e;
      transform: translateY(-2px);
    }

    .metrics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }

    .metric-card {
      background: white;
      border-radius: 16px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      transition: transform 0.3s;
    }

    .metric-card:hover {
      transform: translateY(-5px);
    }

    .metric-label {
      color: #718096;
      font-size: 14px;
      font-weight: 600;
      text-transform: uppercase;
      margin-bottom: 10px;
    }

    .metric-value {
      font-size: 36px;
      font-weight: 700;
      color: #2d3748;
    }

    .metric-unit {
      font-size: 18px;
      color: #a0aec0;
    }

    .status-indicator {
      display: inline-block;
      width: 12px;
      height: 12px;
      border-radius: 50%;
      margin-right: 8px;
    }

    .status-good { background: #48bb78; }
    .status-warning { background: #ed8936; }
    .status-danger { background: #f56565; }

    .chart-container {
      background: white;
      border-radius: 16px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      margin-bottom: 20px;
    }

    .chart-title {
      font-size: 18px;
      font-weight: 600;
      color: #2d3748;
      margin-bottom: 20px;
    }

    canvas {
      max-width: 100%;
    }

    .mode-badge {
      display: inline-block;
      padding: 6px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
    }

    .mode-sync {
      background: #fed7d7;
      color: #c53030;
    }

    .mode-async {
      background: #c6f6d5;
      color: #2f855a;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }

    .loading {
      animation: pulse 1.5s ease-in-out infinite;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>⚡ Slow Log Writes Demo</h1>
      <p class="subtitle">Real-time demonstration of synchronous vs asynchronous logging impact</p>
    </div>

    <div class="controls">
      <div class="control-group">
        <div class="control-item">
          <label>Logging Mode</label>
          <select id="loggingMode">
            <option value="sync">Synchronous (Blocking)</option>
            <option value="async">Asynchronous (Non-Blocking)</option>
          </select>
        </div>
        
        <div class="control-item">
          <label>Log Write Delay: <span class="delay-value" id="delayValue">0ms</span></label>
          <input type="range" id="logDelay" min="0" max="500" value="0" step="10">
        </div>
      </div>

      <div class="button-group">
        <button class="btn-primary" onclick="applyConfig()">Apply Configuration</button>
        <button class="btn-primary" onclick="startLoad()">Start Load Test (10s)</button>
        <button class="btn-danger" onclick="stopLoad()">Stop Load Test</button>
      </div>
    </div>

    <div class="metrics-grid">
      <div class="metric-card">
        <div class="metric-label">Current Mode</div>
        <div class="metric-value">
          <span id="currentMode" class="mode-badge mode-sync">SYNC</span>
        </div>
      </div>

      <div class="metric-card">
        <div class="metric-label">Total Requests</div>
        <div class="metric-value" id="totalRequests">0</div>
      </div>

      <div class="metric-card">
        <div class="metric-label">Avg Response Time</div>
        <div class="metric-value">
          <span id="avgResponseTime">0</span>
          <span class="metric-unit">ms</span>
        </div>
      </div>

      <div class="metric-card">
        <div class="metric-label">Success Rate</div>
        <div class="metric-value">
          <span id="successRate">100</span>
          <span class="metric-unit">%</span>
        </div>
      </div>

      <div class="metric-card">
        <div class="metric-label">Queue Size</div>
        <div class="metric-value" id="queueSize">0</div>
      </div>

      <div class="metric-card">
        <div class="metric-label">Dropped Logs</div>
        <div class="metric-value" id="droppedLogs">0</div>
      </div>
    </div>

    <div class="chart-container">
      <div class="chart-title">📈 Response Time Trend</div>
      <canvas id="responseChart" width="800" height="300"></canvas>
    </div>
  </div>

  <script>
    let loadTestInterval = null;
    let metricsInterval = null;
    let responseTimeData = [];
    let chartCtx = null;

    // Initialize
    document.addEventListener('DOMContentLoaded', () => {
      document.getElementById('logDelay').addEventListener('input', (e) => {
        document.getElementById('delayValue').textContent = e.target.value + 'ms';
      });

      chartCtx = document.getElementById('responseChart').getContext('2d');
      startMetricsPolling();
      fetchMetrics();
    });

    async function applyConfig() {
      const mode = document.getElementById('loggingMode').value;
      const delay = document.getElementById('logDelay').value;

      try {
        const response = await fetch('/api/config', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            loggingMode: mode,
            logDelay: parseInt(delay)
          })
        });

        if (response.ok) {
          responseTimeData = [];
          fetchMetrics();
          alert('Configuration applied successfully!');
        }
      } catch (error) {
        console.error('Error applying config:', error);
      }
    }

    async function startLoad() {
      stopLoad();
      
      loadTestInterval = setInterval(async () => {
        // Send 10 concurrent requests
        const promises = [];
        for (let i = 0; i < 10; i++) {
          promises.push(fetch('/api/process').catch(e => console.error(e)));
        }
        await Promise.all(promises);
      }, 100);

      setTimeout(() => stopLoad(), 10000);
    }

    function stopLoad() {
      if (loadTestInterval) {
        clearInterval(loadTestInterval);
        loadTestInterval = null;
      }
    }

    async function fetchMetrics() {
      try {
        const response = await fetch('/api/metrics');
        const metrics = await response.json();

        const configResponse = await fetch('/api/config');
        const config = await configResponse.json();

        // Update metrics
        document.getElementById('totalRequests').textContent = metrics.totalRequests;
        document.getElementById('avgResponseTime').textContent = metrics.avgResponseTime;
        document.getElementById('queueSize').textContent = metrics.queueSize;
        document.getElementById('droppedLogs').textContent = metrics.droppedLogs;

        const successRate = metrics.totalRequests > 0 
          ? Math.round((metrics.successfulRequests / metrics.totalRequests) * 100)
          : 100;
        document.getElementById('successRate').textContent = successRate;

        // Update mode badge
        const modeBadge = document.getElementById('currentMode');
        modeBadge.textContent = config.loggingMode.toUpperCase();
        modeBadge.className = config.loggingMode === 'sync' ? 'mode-badge mode-sync' : 'mode-badge mode-async';

        // Update chart
        responseTimeData.push(metrics.avgResponseTime);
        if (responseTimeData.length > 50) responseTimeData.shift();
        drawChart();

      } catch (error) {
        console.error('Error fetching metrics:', error);
      }
    }

    function startMetricsPolling() {
      metricsInterval = setInterval(fetchMetrics, 500);
    }

    function drawChart() {
      if (!chartCtx) return;

      const canvas = chartCtx.canvas;
      const width = canvas.width;
      const height = canvas.height;

      // Clear canvas
      chartCtx.clearRect(0, 0, width, height);

      if (responseTimeData.length < 2) return;

      // Find max value for scaling
      const maxValue = Math.max(...responseTimeData, 100);
      const padding = 40;
      const graphWidth = width - padding * 2;
      const graphHeight = height - padding * 2;

      // Draw axes
      chartCtx.strokeStyle = '#e2e8f0';
      chartCtx.lineWidth = 2;
      chartCtx.beginPath();
      chartCtx.moveTo(padding, padding);
      chartCtx.lineTo(padding, height - padding);
      chartCtx.lineTo(width - padding, height - padding);
      chartCtx.stroke();

      // Draw line
      chartCtx.strokeStyle = '#667eea';
      chartCtx.lineWidth = 3;
      chartCtx.beginPath();

      responseTimeData.forEach((value, index) => {
        const x = padding + (index / (responseTimeData.length - 1)) * graphWidth;
        const y = height - padding - (value / maxValue) * graphHeight;
        
        if (index === 0) {
          chartCtx.moveTo(x, y);
        } else {
          chartCtx.lineTo(x, y);
        }
      });

      chartCtx.stroke();

      // Draw points
      chartCtx.fillStyle = '#667eea';
      responseTimeData.forEach((value, index) => {
        const x = padding + (index / (responseTimeData.length - 1)) * graphWidth;
        const y = height - padding - (value / maxValue) * graphHeight;
        
        chartCtx.beginPath();
        chartCtx.arc(x, y, 4, 0, Math.PI * 2);
        chartCtx.fill();
      });

      // Draw labels
      chartCtx.fillStyle = '#718096';
      chartCtx.font = '12px sans-serif';
      chartCtx.fillText('0ms', 5, height - padding + 5);
      chartCtx.fillText(maxValue + 'ms', 5, padding + 5);
    }
  </script>
</body>
</html>
EOF

# Create test file
echo "🧪 Creating test file..."
cat > app/test.js << 'EOF'
const http = require('http');

async function testEndpoint() {
  return new Promise((resolve, reject) => {
    const req = http.get('http://127.0.0.1:3000/api/process', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`Status: ${res.statusCode}`));
        }
      });
    });
    req.on('error', reject);
  });
}

async function runTests() {
  console.log('🧪 Running tests...\n');
  
  try {
    // Test 1: Basic endpoint
    console.log('Test 1: Basic API endpoint');
    const result1 = await testEndpoint();
    console.log('✅ PASS - Endpoint responds correctly');
    console.log(`   Response: ${JSON.stringify(result1)}\n`);
    
    // Test 2: Multiple concurrent requests
    console.log('Test 2: Concurrent requests');
    const promises = Array(10).fill(null).map(() => testEndpoint());
    const results = await Promise.all(promises);
    console.log(`✅ PASS - Handled ${results.length} concurrent requests\n`);
    
    // Test 3: Metrics endpoint
    console.log('Test 3: Metrics endpoint');
    const metricsReq = await new Promise((resolve, reject) => {
      http.get('http://127.0.0.1:3000/api/metrics', (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(JSON.parse(data)));
      }).on('error', reject);
    });
    console.log('✅ PASS - Metrics endpoint working');
    console.log(`   Total requests: ${metricsReq.totalRequests}\n`);
    
    console.log('✅ All tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

setTimeout(runTests, 5000); // Wait for server to start
EOF

# Create Dockerfile
echo "🐳 Creating Dockerfile..."
cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY app ./app
COPY dashboard ./dashboard

EXPOSE 3000

CMD ["npm", "start"]
EOF

# Create docker-compose.yml
echo "🐳 Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - logs:/tmp
    environment:
      - NODE_ENV=production

volumes:
  logs:
EOF

echo ""
echo "🔨 Building Docker image..."
docker-compose build

echo ""
echo "🚀 Starting application..."
docker-compose up -d

echo ""
echo "⏳ Waiting for application to be ready..."
sleep 5

# Check if app is running
if curl -f http://localhost:3000/health > /dev/null 2>&1; then
  echo "✅ Application is running!"
else
  echo "❌ Application failed to start"
  docker-compose logs
  exit 1
fi

echo ""
echo "🧪 Running tests..."
docker-compose exec -T app npm test

echo ""
echo "================================================"
echo "✅ Demo Setup Complete!"
echo "================================================"
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo ""
echo "📋 Demo Steps:"
echo ""
echo "1. Open http://localhost:3000 in your browser"
echo ""
echo "2. Test SYNCHRONOUS mode:"
echo "   - Keep 'Synchronous (Blocking)' selected"
echo "   - Set 'Log Write Delay' to 200ms"
echo "   - Click 'Apply Configuration'"
echo "   - Click 'Start Load Test (10s)'"
echo "   - Watch response time spike to 200ms+"
echo ""
echo "3. Test ASYNCHRONOUS mode:"
echo "   - Select 'Asynchronous (Non-Blocking)'"
echo "   - Keep 'Log Write Delay' at 200ms"
echo "   - Click 'Apply Configuration'"
echo "   - Click 'Start Load Test (10s)'"
echo "   - Watch response time stay low (~10-20ms)"
echo "   - Notice queue size increases instead of blocking"
echo ""
echo "4. Compare the Results:"
echo "   - Sync mode: High response times, threads blocked"
echo "   - Async mode: Low response times, queue absorbs delay"
echo ""
echo "💡 Key Observation:"
echo "   When logging is slow (200ms delay), synchronous logging"
echo "   makes EVERY request slow. Asynchronous logging isolates"
echo "   the slow logging from request processing."
echo ""
echo "================================================"
EOF

# Create cleanup script (outside project directory)
cd ..
echo "🧹 Creating cleanup.sh..."
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Slow Log Writes Demo..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/slow-log-demo"

if [ ! -d "${PROJECT_DIR}" ]; then
  echo "⚠️  Demo directory not found"
  exit 0
fi

cd "${PROJECT_DIR}" || {
  echo "❌ Failed to enter project directory"
  exit 1
}

echo "🛑 Stopping containers..."
docker-compose down -v 2>/dev/null || true

echo "🗑️  Removing Docker images..."
docker-compose rm -f 2>/dev/null || true
docker rmi slow-log-demo_app 2>/dev/null || true

cd "${SCRIPT_DIR}"
echo "📁 Removing project directory..."
rm -rf "${PROJECT_DIR}"

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

echo ""
echo "================================================"
echo "📝 Files Created Successfully!"
echo "================================================"
echo ""
echo "To run the demo:"
echo "  ./demo.sh"
echo ""
echo "To cleanup:"
echo "  ./cleanup.sh"
echo ""