const express = require('express');
const cors = require('cors');
// const helmet = require('helmet'); // Disabled for demo
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const { register, Counter, Histogram } = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3000;

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/api.log' })
  ]
});

// Metrics
const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'version', 'status_code']
});

const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route', 'version']
});

// Middleware - Helmet disabled for demo to allow inline scripts
app.use(cors());

app.use(express.json());

// Compression middleware (skip for metrics)
app.use((req, res, next) => {
  if (req.path === '/metrics') {
    return next();
  }
  compression()(req, res, next);
});

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100
});
app.use(limiter);

// Version detection middleware
const detectVersion = (req, res, next) => {
  // URI path versioning
  const pathMatch = req.path.match(/^\/api\/v(\d+)/);
  if (pathMatch) {
    req.apiVersion = pathMatch[1];
    return next();
  }
  
  // Header versioning
  const headerVersion = req.headers['api-version'];
  if (headerVersion) {
    req.apiVersion = headerVersion;
    return next();
  }
  
  // Content negotiation
  const accept = req.headers.accept || '';
  const versionMatch = accept.match(/version=(\d+)/);
  if (versionMatch) {
    req.apiVersion = versionMatch[1];
    return next();
  }
  
  // Default to v1
  req.apiVersion = '1';
  next();
};

// Metrics middleware
const metricsMiddleware = (req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    
    httpRequests.inc({
      method: req.method,
      route: req.route?.path || req.path,
      version: req.apiVersion,
      status_code: res.statusCode
    });
    
    httpDuration.observe({
      method: req.method,
      route: req.route?.path || req.path,
      version: req.apiVersion
    }, duration);
    
    logger.info('API Request', {
      method: req.method,
      path: req.path,
      version: req.apiVersion,
      statusCode: res.statusCode,
      duration: `${duration}s`
    });
  });
  
  next();
};

app.use(detectVersion);
app.use(metricsMiddleware);

// Remove all security headers after all middleware
app.use((req, res, next) => {
  // Override the end method to remove headers before sending
  const originalEnd = res.end;
  res.end = function(chunk, encoding) {
    // Remove all security headers before sending response
    res.removeHeader('Content-Security-Policy');
    res.removeHeader('Content-Security-Policy-Report-Only');
    res.removeHeader('X-Content-Type-Options');
    res.removeHeader('X-Frame-Options');
    res.removeHeader('X-XSS-Protection');
    res.removeHeader('Strict-Transport-Security');
    res.removeHeader('X-DNS-Prefetch-Control');
    res.removeHeader('X-Download-Options');
    res.removeHeader('X-Permitted-Cross-Domain-Policies');
    res.removeHeader('Cross-Origin-Opener-Policy');
    res.removeHeader('Cross-Origin-Resource-Policy');
    res.removeHeader('Origin-Agent-Cluster');
    res.removeHeader('Referrer-Policy');
    originalEnd.call(this, chunk, encoding);
  };
  next();
});

// Sample data
const users = [
  { id: 1, name: 'Alice Johnson', email: 'alice@example.com', age: 28 },
  { id: 2, name: 'Bob Smith', email: 'bob@example.com', age: 34 },
  { id: 3, name: 'Carol Davis', email: 'carol@example.com', age: 29 }
];

// Version-specific response transformers
const transformUserV1 = (user) => ({
  id: user.id,
  name: user.name,
  email: user.email
});

const transformUserV2 = (user) => ({
  id: user.id,
  full_name: user.name,
  email_address: user.email,
  age: user.age,
  created_at: '2024-01-01T00:00:00Z'
});

const transformUserV3 = (user) => ({
  user_id: user.id,
  profile: {
    display_name: user.name,
    contact: {
      email: user.email
    },
    demographics: {
      age: user.age
    }
  },
  metadata: {
    version: 3,
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z'
  }
});

// API Routes - URI Path Versioning
app.get('/api/v1/users', (req, res) => {
  const transformedUsers = users.map(transformUserV1);
  res.json({ users: transformedUsers, version: '1.0' });
});

app.get('/api/v2/users', (req, res) => {
  const transformedUsers = users.map(transformUserV2);
  res.json({ users: transformedUsers, version: '2.0' });
});

app.get('/api/v3/users', (req, res) => {
  const transformedUsers = users.map(transformUserV3);
  res.json({ data: transformedUsers, version: '3.0', format: 'extended' });
});

// Generic endpoint with version detection
app.get('/api/users', (req, res) => {
  let transformedUsers;
  let response;
  
  switch(req.apiVersion) {
    case '1':
      transformedUsers = users.map(transformUserV1);
      response = { users: transformedUsers, version: '1.0' };
      break;
    case '2':
      transformedUsers = users.map(transformUserV2);
      response = { users: transformedUsers, version: '2.0' };
      break;
    case '3':
      transformedUsers = users.map(transformUserV3);
      response = { data: transformedUsers, version: '3.0', format: 'extended' };
      break;
    default:
      transformedUsers = users.map(transformUserV1);
      response = { users: transformedUsers, version: '1.0' };
  }
  
  res.json(response);
});

// Version info endpoint
app.get('/api/version', (req, res) => {
  res.json({
    detected_version: req.apiVersion,
    supported_versions: ['1', '2', '3'],
    deprecation_notices: {
      'v1': 'Deprecated. Migrate to v2 by 2024-06-01',
      'v2': 'Current stable version',
      'v3': 'Latest with enhanced features'
    }
  });
});

// Circuit breaker simulation
let v3FailureRate = 0;

app.post('/api/admin/failure-rate', (req, res) => {
  v3FailureRate = req.body.rate || 0;
  res.json({ message: `V3 failure rate set to ${v3FailureRate}%` });
});

// Simulate circuit breaker behavior
app.use('/api/v3/*', (req, res, next) => {
  if (Math.random() < v3FailureRate / 100) {
    return res.status(503).json({ 
      error: 'Service temporarily unavailable',
      fallback_version: 'v2'
    });
  }
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.npm_package_version || '1.0.0'
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    const metrics = await register.metrics();
    res.end(metrics);
  } catch (error) {
    res.status(500).end('Error generating metrics');
  }
});

// Dashboard - Interactive version with metrics
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>API Versioning Demo</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .container { max-width: 1200px; margin: 0 auto; }
            .demo-links {
                margin: 20px 0;
                padding: 20px;
                background: #e8f5e8;
                border-radius: 8px;
            }
            .demo-links h3 { margin-top: 0; }
            .demo-links a {
                display: inline-block;
                margin: 5px 10px 5px 0;
                padding: 10px 15px;
                background: #4caf50;
                color: white;
                text-decoration: none;
                border-radius: 4px;
            }
            .demo-links a:hover { background: #45a049; }
            .endpoint { 
                background: #e3f2fd; 
                padding: 10px; 
                border-radius: 4px; 
                margin: 10px 0; 
                font-family: monospace;
            }
            .metrics-section {
                background: #f5f5f5;
                padding: 20px;
                border-radius: 8px;
                margin: 20px 0;
            }
            .metric-item {
                display: inline-block;
                margin: 10px;
                padding: 10px;
                background: white;
                border-radius: 4px;
                border-left: 4px solid #4caf50;
            }
            .test-button {
                background: #2196F3;
                color: white;
                border: none;
                padding: 10px 15px;
                border-radius: 4px;
                cursor: pointer;
                margin: 5px;
            }
            .test-button:hover { background: #1976D2; }
            .response-area {
                background: #f9f9f9;
                border: 1px solid #ddd;
                border-radius: 4px;
                padding: 10px;
                margin: 10px 0;
                min-height: 100px;
                font-family: monospace;
                white-space: pre-wrap;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 API Versioning Strategies Demo</h1>
            
            <div class="demo-links">
                <h3>🎯 Interactive Demo Links</h3>
                <p>Click these links to test different API versions:</p>
                <a href="/api/v1/users" target="_blank">Test V1 Users</a>
                <a href="/api/v2/users" target="_blank">Test V2 Users</a>
                <a href="/api/v3/users" target="_blank">Test V3 Users</a>
                <a href="/api/version" target="_blank">Version Info</a>
                <a href="/health" target="_blank">Health Check</a>
                <a href="/metrics" target="_blank">View Metrics</a>
            </div>
            
            <div class="metrics-section">
                <h3>📊 Live Metrics Dashboard</h3>
                <div class="metric-item">
                    <strong>Total Requests:</strong> <span id="totalRequests">0</span>
                </div>
                <div class="metric-item">
                    <strong>V1 Requests:</strong> <span id="v1Requests">0</span>
                </div>
                <div class="metric-item">
                    <strong>V2 Requests:</strong> <span id="v2Requests">0</span>
                </div>
                <div class="metric-item">
                    <strong>V3 Requests:</strong> <span id="v3Requests">0</span>
                </div>
                <div class="metric-item">
                    <strong>Last Updated:</strong> <span id="lastUpdated">Never</span>
                </div>
            </div>
            
            <div class="metrics-section">
                <h3>🧪 Interactive Testing</h3>
                <button class="test-button" onclick="testAPI('/api/v1/users')">Test V1 API</button>
                <button class="test-button" onclick="testAPI('/api/v2/users')">Test V2 API</button>
                <button class="test-button" onclick="testAPI('/api/v3/users')">Test V3 API</button>
                <button class="test-button" onclick="testAPI('/api/users', {'API-Version': '2'})">Test Header Versioning</button>
                <button class="test-button" onclick="testAPI('/api/users', {'Accept': 'application/json;version=3'})">Test Content Negotiation</button>
                <button class="test-button" onclick="loadMetrics()">Refresh Metrics</button>
                <div class="response-area" id="responseArea">Click a button above to test the API...</div>
            </div>
            
            <h3>🔧 Testing Commands</h3>
            <div class="endpoint">
                curl http://localhost:3000/api/v1/users<br>
                curl http://localhost:3000/api/v2/users<br>
                curl http://localhost:3000/api/v3/users<br>
                curl -H 'API-Version: 2' http://localhost:3000/api/users<br>
                curl -H 'Accept: application/json;version=3' http://localhost:3000/api/users
            </div>
        </div>
        
        <script>
            async function testAPI(url, headers = {}) {
                const responseArea = document.getElementById('responseArea');
                responseArea.textContent = 'Loading...';
                
                try {
                    const response = await fetch(url, { headers });
                    const data = await response.json();
                    responseArea.textContent = JSON.stringify(data, null, 2);
                    loadMetrics(); // Refresh metrics after API call
                } catch (error) {
                    responseArea.textContent = 'Error: ' + error.message;
                }
            }
            
            async function loadMetrics() {
                try {
                    const response = await fetch('/metrics');
                    const text = await response.text();
                    
                    // Parse Prometheus metrics
                    const lines = text.split('\\n');
                    let totalRequests = 0;
                    let v1Requests = 0;
                    let v2Requests = 0;
                    let v3Requests = 0;
                    
                    lines.forEach(line => {
                        if (line.startsWith('http_requests_total{')) {
                            const match = line.match(/version="(\\d+)"/);
                            if (match) {
                                const version = match[1];
                                const countMatch = line.match(/\\s+(\\d+)$/);
                                if (countMatch) {
                                    const count = parseInt(countMatch[1]);
                                    totalRequests += count;
                                    if (version === '1') v1Requests += count;
                                    else if (version === '2') v2Requests += count;
                                    else if (version === '3') v3Requests += count;
                                }
                            }
                        }
                    });
                    
                    document.getElementById('totalRequests').textContent = totalRequests;
                    document.getElementById('v1Requests').textContent = v1Requests;
                    document.getElementById('v2Requests').textContent = v2Requests;
                    document.getElementById('v3Requests').textContent = v3Requests;
                    document.getElementById('lastUpdated').textContent = new Date().toLocaleTimeString();
                } catch (error) {
                    console.error('Error loading metrics:', error);
                }
            }
            
            // Load metrics on page load
            loadMetrics();
            
            // Auto-refresh metrics every 5 seconds
            setInterval(loadMetrics, 5000);
        </script>
    </body>
    </html>
  `);
});

// Create logs directory
const fs = require('fs');
if (!fs.existsSync('logs')) {
  fs.mkdirSync('logs');
}

app.listen(PORT, () => {
  logger.info(`API Versioning Demo running on port ${PORT}`);
  console.log(`🌐 Dashboard: http://localhost:${PORT}`);
  console.log(`📊 Metrics: http://localhost:${PORT}/metrics`);
});

module.exports = app;
