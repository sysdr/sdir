#!/bin/bash

# Zero-Trust Security Architecture Demo
# This script creates a complete zero-trust system with identity provider,
# policy engine, access proxy, and protected services

set -e

echo "=================================="
echo "Zero-Trust Architecture Demo Setup"
echo "=================================="

# Create project structure
mkdir -p zero-trust-demo/{identity-provider,policy-engine,access-proxy,protected-service,dashboard,shared}

# Create shared certificate generation script
cat > zero-trust-demo/shared/generate-certs.sh << 'EOF'
#!/bin/bash
mkdir -p certs

# Generate CA
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout certs/ca-key.pem -out certs/ca-cert.pem \
  -subj "/CN=Zero-Trust-CA"

# Generate service certificates
for service in identity policy proxy service; do
  openssl req -newkey rsa:2048 -nodes \
    -keyout certs/${service}-key.pem \
    -out certs/${service}-req.pem \
    -subj "/CN=${service}"
  
  openssl x509 -req -in certs/${service}-req.pem \
    -CA certs/ca-cert.pem -CAkey certs/ca-key.pem \
    -CAcreateserial -out certs/${service}-cert.pem \
    -days 365
done
EOF
chmod +x zero-trust-demo/shared/generate-certs.sh

# Generate certificates
cd zero-trust-demo/shared && ./generate-certs.sh && cd ../..

# ==================== Identity Provider ====================
cat > zero-trust-demo/identity-provider/package.json << 'EOF'
{
  "name": "identity-provider",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.2",
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "uuid": "^9.0.1"
  }
}
EOF

cat > zero-trust-demo/identity-provider/server.js << 'EOF'
const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(express.json());
app.use(cors());

const JWT_SECRET = 'zero-trust-secret-key-2024';
const REFRESH_SECRET = 'zero-trust-refresh-key-2024';

// Mock user database with device fingerprints
const users = new Map([
  ['alice@company.com', {
    id: '1',
    email: 'alice@company.com',
    password: bcrypt.hashSync('password123', 10),
    role: 'engineer',
    department: 'platform',
    devices: new Set(['device-001'])
  }],
  ['bob@company.com', {
    id: '2',
    email: 'bob@company.com',
    password: bcrypt.hashSync('password456', 10),
    role: 'admin',
    department: 'security',
    devices: new Set(['device-002'])
  }]
]);

// Active sessions tracking
const activeSessions = new Map();

// Device posture checks
function checkDevicePosture(deviceId) {
  const devicePosture = {
    'device-001': { secure: true, osPatched: true, encryptionEnabled: true, score: 95 },
    'device-002': { secure: true, osPatched: true, encryptionEnabled: true, score: 98 },
    'device-003': { secure: false, osPatched: false, encryptionEnabled: true, score: 45 }
  };
  return devicePosture[deviceId] || { secure: false, osPatched: false, encryptionEnabled: false, score: 0 };
}

// Authentication endpoint
app.post('/auth/login', (req, res) => {
  const { email, password, deviceId, location } = req.body;
  
  console.log(`[Identity] Login attempt: ${email} from device ${deviceId}`);
  
  const user = users.get(email);
  if (!user || !bcrypt.compareSync(password, user.password)) {
    console.log(`[Identity] Authentication failed for ${email}`);
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  
  // Check device posture
  const devicePosture = checkDevicePosture(deviceId);
  if (!devicePosture.secure || devicePosture.score < 70) {
    console.log(`[Identity] Device posture check failed for ${deviceId}: score ${devicePosture.score}`);
    return res.status(403).json({ 
      error: 'Device security posture insufficient',
      posture: devicePosture
    });
  }
  
  // Generate session
  const sessionId = uuidv4();
  const accessToken = jwt.sign({
    userId: user.id,
    email: user.email,
    role: user.role,
    department: user.department,
    deviceId,
    sessionId,
    devicePosture: devicePosture.score
  }, JWT_SECRET, { expiresIn: '15m' });
  
  const refreshToken = jwt.sign({
    userId: user.id,
    sessionId
  }, REFRESH_SECRET, { expiresIn: '7d' });
  
  activeSessions.set(sessionId, {
    userId: user.id,
    email: user.email,
    deviceId,
    location,
    loginTime: new Date(),
    lastActivity: new Date()
  });
  
  console.log(`[Identity] Authentication successful for ${email}, session: ${sessionId}`);
  
  res.json({
    accessToken,
    refreshToken,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      department: user.department
    },
    devicePosture
  });
});

// Token validation endpoint
app.post('/auth/validate', (req, res) => {
  const { token } = req.body;
  
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const session = activeSessions.get(decoded.sessionId);
    
    if (!session) {
      return res.status(401).json({ valid: false, error: 'Session not found' });
    }
    
    // Update last activity
    session.lastActivity = new Date();
    
    console.log(`[Identity] Token validated for ${decoded.email}`);
    res.json({ valid: true, claims: decoded });
  } catch (error) {
    console.log(`[Identity] Token validation failed: ${error.message}`);
    res.status(401).json({ valid: false, error: error.message });
  }
});

// Session management
app.get('/auth/sessions', (req, res) => {
  const sessions = Array.from(activeSessions.entries()).map(([id, session]) => ({
    sessionId: id,
    ...session,
    age: Math.floor((Date.now() - session.loginTime) / 1000)
  }));
  res.json({ sessions, count: sessions.length });
});

app.delete('/auth/sessions/:sessionId', (req, res) => {
  const { sessionId } = req.params;
  if (activeSessions.delete(sessionId)) {
    console.log(`[Identity] Session ${sessionId} terminated`);
    res.json({ success: true });
  } else {
    res.status(404).json({ error: 'Session not found' });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'identity-provider', 
    status: 'healthy',
    activeSessions: activeSessions.size
  });
});

const PORT = 3001;
app.listen(PORT, () => {
  console.log(`[Identity Provider] Running on port ${PORT}`);
});
EOF

cat > zero-trust-demo/identity-provider/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# ==================== Policy Engine ====================
cat > zero-trust-demo/policy-engine/package.json << 'EOF'
{
  "name": "policy-engine",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "uuid": "^9.0.1"
  }
}
EOF

cat > zero-trust-demo/policy-engine/server.js << 'EOF'
const express = require('express');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Policy definitions
const policies = [
  {
    id: 'pol-001',
    name: 'Production Database Access',
    resource: '/api/database',
    conditions: {
      roles: ['admin', 'engineer'],
      departments: ['platform', 'security'],
      minDeviceScore: 90,
      timeWindow: { start: 6, end: 22 }
    }
  },
  {
    id: 'pol-002',
    name: 'User Data Access',
    resource: '/api/users',
    conditions: {
      roles: ['admin'],
      minDeviceScore: 95
    }
  },
  {
    id: 'pol-003',
    name: 'Public API',
    resource: '/api/public',
    conditions: {
      roles: ['engineer', 'admin'],
      minDeviceScore: 70
    }
  }
];

// Decision log
const decisionLog = [];

// Policy evaluation
function evaluatePolicy(claims, resource, context) {
  console.log(`[Policy] Evaluating access to ${resource} for ${claims.email}`);
  
  // Find matching policy
  const policy = policies.find(p => resource.startsWith(p.resource));
  if (!policy) {
    console.log(`[Policy] No policy found for ${resource}, defaulting to deny`);
    return { allowed: false, reason: 'No matching policy', policy: null };
  }
  
  // Check role
  if (policy.conditions.roles && !policy.conditions.roles.includes(claims.role)) {
    console.log(`[Policy] Role check failed: ${claims.role} not in ${policy.conditions.roles}`);
    return { allowed: false, reason: 'Insufficient role', policy: policy.id };
  }
  
  // Check department
  if (policy.conditions.departments && !policy.conditions.departments.includes(claims.department)) {
    console.log(`[Policy] Department check failed: ${claims.department}`);
    return { allowed: false, reason: 'Department not authorized', policy: policy.id };
  }
  
  // Check device security score
  if (policy.conditions.minDeviceScore && claims.devicePosture < policy.conditions.minDeviceScore) {
    console.log(`[Policy] Device score too low: ${claims.devicePosture} < ${policy.conditions.minDeviceScore}`);
    return { allowed: false, reason: 'Device security score insufficient', policy: policy.id };
  }
  
  // Check time window
  if (policy.conditions.timeWindow) {
    const hour = new Date().getHours();
    const { start, end } = policy.conditions.timeWindow;
    if (hour < start || hour >= end) {
      console.log(`[Policy] Outside allowed time window: ${hour}:00`);
      return { allowed: false, reason: 'Outside allowed time window', policy: policy.id };
    }
  }
  
  // Check location risk (mock implementation)
  if (context.location && context.location.risk === 'high') {
    console.log(`[Policy] High-risk location detected`);
    return { allowed: false, reason: 'High-risk location', policy: policy.id };
  }
  
  console.log(`[Policy] Access granted to ${resource} for ${claims.email}`);
  return { allowed: true, reason: 'All checks passed', policy: policy.id };
}

// Policy evaluation endpoint
app.post('/policy/evaluate', (req, res) => {
  const { claims, resource, context = {} } = req.body;
  
  const startTime = Date.now();
  const decision = evaluatePolicy(claims, resource, context);
  const latency = Date.now() - startTime;
  
  const logEntry = {
    timestamp: new Date(),
    userId: claims.userId,
    email: claims.email,
    resource,
    decision: decision.allowed ? 'ALLOW' : 'DENY',
    reason: decision.reason,
    policy: decision.policy,
    latency
  };
  
  decisionLog.push(logEntry);
  if (decisionLog.length > 1000) decisionLog.shift();
  
  res.json({ ...decision, latency });
});

// Get policies
app.get('/policy/list', (req, res) => {
  res.json({ policies });
});

// Get decision log
app.get('/policy/decisions', (req, res) => {
  const recent = decisionLog.slice(-50).reverse();
  const stats = {
    total: decisionLog.length,
    allowed: decisionLog.filter(d => d.decision === 'ALLOW').length,
    denied: decisionLog.filter(d => d.decision === 'DENY').length
  };
  res.json({ decisions: recent, stats });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'policy-engine', 
    status: 'healthy',
    policiesLoaded: policies.length
  });
});

const PORT = 3002;
app.listen(PORT, () => {
  console.log(`[Policy Engine] Running on port ${PORT}`);
});
EOF

cat > zero-trust-demo/policy-engine/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

# ==================== Access Proxy ====================
cat > zero-trust-demo/access-proxy/package.json << 'EOF'
{
  "name": "access-proxy",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > zero-trust-demo/access-proxy/server.js << 'EOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const IDENTITY_SERVICE = 'http://identity-provider:3001';
const POLICY_SERVICE = 'http://policy-engine:3002';
const PROTECTED_SERVICE = 'http://protected-service:3004';

// Request log
const requestLog = [];

// Middleware to validate and authorize requests
async function zeroTrustMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    console.log('[Proxy] No authorization header');
    return res.status(401).json({ error: 'No authorization token' });
  }
  
  const token = authHeader.substring(7);
  const startTime = Date.now();
  
  try {
    // Step 1: Validate identity
    console.log('[Proxy] Step 1: Validating identity...');
    const identityStart = Date.now();
    const identityResponse = await axios.post(`${IDENTITY_SERVICE}/auth/validate`, { token });
    const identityLatency = Date.now() - identityStart;
    
    if (!identityResponse.data.valid) {
      console.log('[Proxy] Identity validation failed');
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    const claims = identityResponse.data.claims;
    console.log(`[Proxy] Identity validated: ${claims.email}`);
    
    // Step 2: Evaluate policy
    console.log('[Proxy] Step 2: Evaluating policy...');
    const policyStart = Date.now();
    // Use originalUrl to get the full path including /api prefix
    const resourcePath = req.originalUrl || req.path;
    const policyResponse = await axios.post(`${POLICY_SERVICE}/policy/evaluate`, {
      claims,
      resource: resourcePath,
      context: {
        method: req.method,
        location: { risk: 'low' }
      }
    });
    const policyLatency = Date.now() - policyStart;
    
    if (!policyResponse.data.allowed) {
      console.log(`[Proxy] Policy denied: ${policyResponse.data.reason}`);
      const logEntry = {
        timestamp: new Date(),
        user: claims.email,
        resource: resourcePath,
        decision: 'DENY',
        reason: policyResponse.data.reason,
        totalLatency: Date.now() - startTime
      };
      requestLog.push(logEntry);
      if (requestLog.length > 500) requestLog.shift();
      
      return res.status(403).json({ 
        error: 'Access denied', 
        reason: policyResponse.data.reason 
      });
    }
    
    console.log('[Proxy] Policy allowed access');
    
    // Log successful request
    const logEntry = {
      timestamp: new Date(),
      user: claims.email,
      resource: resourcePath,
      decision: 'ALLOW',
      identityLatency,
      policyLatency,
      totalLatency: Date.now() - startTime
    };
    requestLog.push(logEntry);
    if (requestLog.length > 500) requestLog.shift();
    
    req.claims = claims;
    next();
  } catch (error) {
    console.error('[Proxy] Error in zero-trust flow:', error.message);
    res.status(500).json({ error: 'Internal proxy error' });
  }
}

// Proxy routes
app.use('/api/*', zeroTrustMiddleware);

app.all('/api/*', async (req, res) => {
  try {
    const targetPath = req.path.replace('/api', '');
    const targetUrl = `${PROTECTED_SERVICE}${targetPath}`;
    
    console.log(`[Proxy] Forwarding ${req.method} ${req.path} to ${targetUrl}`);
    
    const response = await axios({
      method: req.method,
      url: targetUrl,
      data: req.body,
      headers: {
        'X-User-Email': req.claims.email,
        'X-User-Role': req.claims.role
      }
    });
    
    res.json(response.data);
  } catch (error) {
    console.error('[Proxy] Error forwarding request:', error.message);
    res.status(500).json({ error: 'Failed to forward request' });
  }
});

// Proxy stats
app.get('/proxy/stats', (req, res) => {
  const stats = {
    totalRequests: requestLog.length,
    allowed: requestLog.filter(r => r.decision === 'ALLOW').length,
    denied: requestLog.filter(r => r.decision === 'DENY').length,
    avgLatency: requestLog.length > 0 
      ? Math.round(requestLog.reduce((sum, r) => sum + r.totalLatency, 0) / requestLog.length)
      : 0,
    recentRequests: requestLog.slice(-20).reverse()
  };
  res.json(stats);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'access-proxy', 
    status: 'healthy',
    requestsProcessed: requestLog.length
  });
});

const PORT = 3003;
app.listen(PORT, () => {
  console.log(`[Access Proxy] Running on port ${PORT}`);
});
EOF

cat > zero-trust-demo/access-proxy/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
EXPOSE 3003
CMD ["node", "server.js"]
EOF

# ==================== Protected Service ====================
cat > zero-trust-demo/protected-service/package.json << 'EOF'
{
  "name": "protected-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > zero-trust-demo/protected-service/server.js << 'EOF'
const express = require('express');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Mock databases
const databases = {
  users: [
    { id: 1, name: 'John Doe', email: 'john@example.com', role: 'user' },
    { id: 2, name: 'Jane Smith', email: 'jane@example.com', role: 'admin' }
  ],
  transactions: [
    { id: 1, amount: 1250.50, status: 'completed', timestamp: new Date() },
    { id: 2, amount: 899.99, status: 'pending', timestamp: new Date() }
  ]
};

// Access log
const accessLog = [];

function logAccess(user, resource, action) {
  const entry = {
    timestamp: new Date(),
    user: user || 'anonymous',
    resource,
    action
  };
  accessLog.push(entry);
  if (accessLog.length > 200) accessLog.shift();
  console.log(`[Service] Access: ${user} -> ${resource} (${action})`);
}

// Protected endpoints
app.get('/database', (req, res) => {
  const user = req.headers['x-user-email'];
  logAccess(user, '/database', 'READ');
  
  res.json({
    message: 'Database access granted',
    data: databases,
    accessedBy: user,
    timestamp: new Date()
  });
});

app.get('/users', (req, res) => {
  const user = req.headers['x-user-email'];
  logAccess(user, '/users', 'READ');
  
  res.json({
    users: databases.users,
    count: databases.users.length,
    accessedBy: user
  });
});

app.get('/public', (req, res) => {
  const user = req.headers['x-user-email'] || 'anonymous';
  logAccess(user, '/public', 'READ');
  
  res.json({
    message: 'Public API endpoint',
    version: '1.0.0',
    timestamp: new Date()
  });
});

app.get('/access-log', (req, res) => {
  res.json({
    log: accessLog.slice(-50).reverse(),
    total: accessLog.length
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'protected-service', 
    status: 'healthy',
    accessEvents: accessLog.length
  });
});

const PORT = 3004;
app.listen(PORT, () => {
  console.log(`[Protected Service] Running on port ${PORT}`);
});
EOF

cat > zero-trust-demo/protected-service/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
EXPOSE 3004
CMD ["node", "server.js"]
EOF

# ==================== Dashboard ====================
cat > zero-trust-demo/dashboard/package.json << 'EOF'
{
  "name": "dashboard",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > zero-trust-demo/dashboard/server.js << 'EOF'
const express = require('express');
const path = require('path');

const app = express();
app.use(express.static('public'));

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`[Dashboard] Running on http://localhost:${PORT}`);
});
EOF

mkdir -p zero-trust-demo/dashboard/public

cat > zero-trust-demo/dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Zero-Trust Security Architecture Dashboard</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: #333;
      padding: 20px;
    }

    .container {
      max-width: 1400px;
      margin: 0 auto;
    }

    h1 {
      color: white;
      text-align: center;
      margin-bottom: 30px;
      font-size: 2.5em;
      text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(450px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }

    .card {
      background: white;
      border-radius: 12px;
      padding: 25px;
      box-shadow: 0 8px 16px rgba(0,0,0,0.2);
    }

    .card h2 {
      color: #667eea;
      margin-bottom: 15px;
      font-size: 1.4em;
      border-bottom: 3px solid #667eea;
      padding-bottom: 10px;
    }

    .auth-section {
      margin-bottom: 20px;
    }

    .form-group {
      margin-bottom: 15px;
    }

    label {
      display: block;
      margin-bottom: 5px;
      font-weight: 600;
      color: #555;
    }

    input, select {
      width: 100%;
      padding: 10px;
      border: 2px solid #ddd;
      border-radius: 6px;
      font-size: 14px;
    }

    input:focus, select:focus {
      outline: none;
      border-color: #667eea;
    }

    button {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 600;
      transition: transform 0.2s;
      margin-right: 10px;
      margin-top: 10px;
    }

    button:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 8px rgba(0,0,0,0.2);
    }

    button:disabled {
      background: #ccc;
      cursor: not-allowed;
      transform: none;
    }

    .status {
      padding: 8px 15px;
      border-radius: 6px;
      font-weight: 600;
      display: inline-block;
      margin-bottom: 15px;
    }

    .status.authenticated {
      background: #d1fae5;
      color: #065f46;
    }

    .status.unauthenticated {
      background: #fee2e2;
      color: #991b1b;
    }

    .stat-box {
      background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
      padding: 20px;
      border-radius: 8px;
      color: white;
      margin-bottom: 15px;
    }

    .stat-box h3 {
      font-size: 2em;
      margin-bottom: 5px;
    }

    .stat-box p {
      opacity: 0.9;
    }

    .log-entry {
      padding: 12px;
      border-left: 4px solid #667eea;
      background: #f9fafb;
      margin-bottom: 10px;
      border-radius: 4px;
      font-size: 0.9em;
    }

    .log-entry.denied {
      border-left-color: #ef4444;
      background: #fef2f2;
    }

    .log-entry .timestamp {
      color: #6b7280;
      font-size: 0.85em;
    }

    .log-entry .decision {
      font-weight: 600;
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      margin-left: 10px;
    }

    .log-entry .decision.allow {
      background: #d1fae5;
      color: #065f46;
    }

    .log-entry .decision.deny {
      background: #fee2e2;
      color: #991b1b;
    }

    .session-item {
      padding: 15px;
      background: #f9fafb;
      border-radius: 8px;
      margin-bottom: 10px;
      border: 1px solid #e5e7eb;
    }

    .session-item strong {
      color: #667eea;
    }

    .metrics {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 15px;
      margin-top: 15px;
    }

    .metric-card {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      padding: 15px;
      border-radius: 8px;
      text-align: center;
      color: white;
    }

    .metric-card h4 {
      font-size: 1.8em;
      margin-bottom: 5px;
    }

    .metric-card p {
      font-size: 0.9em;
      opacity: 0.9;
    }

    .policy-item {
      padding: 12px;
      background: #eff6ff;
      border-radius: 6px;
      margin-bottom: 10px;
      border-left: 4px solid #3b82f6;
    }

    .policy-item strong {
      color: #1e40af;
    }

    .alert {
      padding: 15px;
      border-radius: 8px;
      margin-bottom: 15px;
      font-weight: 500;
    }

    .alert.success {
      background: #d1fae5;
      color: #065f46;
      border: 1px solid #6ee7b7;
    }

    .alert.error {
      background: #fee2e2;
      color: #991b1b;
      border: 1px solid #fca5a5;
    }

    .info-text {
      color: #6b7280;
      font-size: 0.9em;
      margin-top: 10px;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔒 Zero-Trust Security Architecture</h1>

    <div class="grid">
      <!-- Authentication Section -->
      <div class="card">
        <h2>1. Identity Provider</h2>
        <div class="status" id="authStatus">Unauthenticated</div>
        
        <div class="auth-section">
          <div class="form-group">
            <label>Email:</label>
            <select id="email">
              <option value="alice@company.com">alice@company.com (Engineer)</option>
              <option value="bob@company.com">bob@company.com (Admin)</option>
            </select>
          </div>

          <div class="form-group">
            <label>Password:</label>
            <input type="password" id="password" value="password123">
          </div>

          <div class="form-group">
            <label>Device ID:</label>
            <select id="deviceId">
              <option value="device-001">device-001 (Secure, Score: 95)</option>
              <option value="device-002">device-002 (Secure, Score: 98)</option>
              <option value="device-003">device-003 (Insecure, Score: 45)</option>
            </select>
          </div>

          <button onclick="login()">Authenticate</button>
          <button onclick="logout()" id="logoutBtn" disabled>Logout</button>
        </div>

        <div id="userInfo"></div>
        <p class="info-text">Try different devices to see security posture checks in action</p>
      </div>

      <!-- Policy Engine -->
      <div class="card">
        <h2>2. Policy Engine</h2>
        <div id="policyStats"></div>
        <div id="policyList"></div>
      </div>

      <!-- Request Testing -->
      <div class="card">
        <h2>3. Test Protected Resources</h2>
        <p class="info-text">All requests go through: Identity → Policy → Access Proxy → Service</p>
        
        <button onclick="testEndpoint('/api/database')">Access Database</button>
        <button onclick="testEndpoint('/api/users')">Access Users</button>
        <button onclick="testEndpoint('/api/public')">Access Public API</button>
        
        <div id="requestResult" style="margin-top: 15px;"></div>
      </div>

      <!-- Proxy Statistics -->
      <div class="card">
        <h2>4. Access Proxy Stats</h2>
        <div id="proxyStats"></div>
      </div>

      <!-- Active Sessions -->
      <div class="card">
        <h2>5. Active Sessions</h2>
        <button onclick="loadSessions()">Refresh Sessions</button>
        <div id="sessionList" style="margin-top: 15px;"></div>
      </div>

      <!-- Decision Log -->
      <div class="card">
        <h2>6. Policy Decisions Log</h2>
        <div id="decisionLog"></div>
      </div>
    </div>
  </div>

  <script>
    let accessToken = null;
    let refreshInterval = null;

    async function login() {
      const email = document.getElementById('email').value;
      const password = document.getElementById('password').value;
      const deviceId = document.getElementById('deviceId').value;

      try {
        const response = await fetch('http://localhost:3001/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password, deviceId, location: { city: 'San Francisco' } })
        });

        const data = await response.json();

        if (response.ok) {
          accessToken = data.accessToken;
          document.getElementById('authStatus').className = 'status authenticated';
          document.getElementById('authStatus').textContent = 'Authenticated';
          document.getElementById('logoutBtn').disabled = false;
          
          document.getElementById('userInfo').innerHTML = `
            <div class="alert success">
              ✓ Login successful!<br>
              User: ${data.user.email}<br>
              Role: ${data.user.role}<br>
              Device Score: ${data.devicePosture.score}
            </div>
          `;

          loadDashboard();
          startAutoRefresh();
        } else {
          document.getElementById('userInfo').innerHTML = `
            <div class="alert error">✗ ${data.error}</div>
          `;
        }
      } catch (error) {
        document.getElementById('userInfo').innerHTML = `
          <div class="alert error">✗ Connection error: ${error.message}</div>
        `;
      }
    }

    function logout() {
      accessToken = null;
      document.getElementById('authStatus').className = 'status unauthenticated';
      document.getElementById('authStatus').textContent = 'Unauthenticated';
      document.getElementById('logoutBtn').disabled = true;
      document.getElementById('userInfo').innerHTML = '';
      document.getElementById('requestResult').innerHTML = '';
      stopAutoRefresh();
    }

    async function testEndpoint(path) {
      if (!accessToken) {
        document.getElementById('requestResult').innerHTML = `
          <div class="alert error">✗ Please login first</div>
        `;
        return;
      }

      try {
        const response = await fetch(`http://localhost:3003${path}`, {
          headers: { 'Authorization': `Bearer ${accessToken}` }
        });

        const data = await response.json();

        if (response.ok) {
          document.getElementById('requestResult').innerHTML = `
            <div class="alert success">
              ✓ Access granted to ${path}<br>
              <pre style="margin-top: 10px; overflow-x: auto;">${JSON.stringify(data, null, 2)}</pre>
            </div>
          `;
        } else {
          document.getElementById('requestResult').innerHTML = `
            <div class="alert error">
              ✗ Access denied to ${path}<br>
              Reason: ${data.reason || data.error}
            </div>
          `;
        }
        
        loadProxyStats();
        loadDecisionLog();
      } catch (error) {
        document.getElementById('requestResult').innerHTML = `
          <div class="alert error">✗ Request failed: ${error.message}</div>
        `;
      }
    }

    async function loadPolicies() {
      try {
        const response = await fetch('http://localhost:3002/policy/list');
        const data = await response.json();

        let html = '<div style="margin-top: 15px;">';
        data.policies.forEach(policy => {
          html += `
            <div class="policy-item">
              <strong>${policy.name}</strong><br>
              Resource: ${policy.resource}<br>
              Roles: ${policy.conditions.roles?.join(', ') || 'Any'}<br>
              Min Device Score: ${policy.conditions.minDeviceScore || 'None'}
            </div>
          `;
        });
        html += '</div>';

        document.getElementById('policyList').innerHTML = html;
      } catch (error) {
        console.error('Failed to load policies:', error);
      }
    }

    async function loadProxyStats() {
      try {
        const response = await fetch('http://localhost:3003/proxy/stats');
        const data = await response.json();

        document.getElementById('proxyStats').innerHTML = `
          <div class="metrics">
            <div class="metric-card">
              <h4>${data.totalRequests}</h4>
              <p>Total Requests</p>
            </div>
            <div class="metric-card">
              <h4>${data.allowed}</h4>
              <p>Allowed</p>
            </div>
            <div class="metric-card">
              <h4>${data.denied}</h4>
              <p>Denied</p>
            </div>
          </div>
          <div class="stat-box" style="margin-top: 15px;">
            <h3>${data.avgLatency}ms</h3>
            <p>Average Latency (Identity + Policy Check)</p>
          </div>
        `;
      } catch (error) {
        console.error('Failed to load proxy stats:', error);
      }
    }

    async function loadSessions() {
      try {
        const response = await fetch('http://localhost:3001/auth/sessions');
        const data = await response.json();

        let html = '<div style="margin-top: 15px;">';
        if (data.sessions.length === 0) {
          html += '<p class="info-text">No active sessions</p>';
        } else {
          data.sessions.forEach(session => {
            html += `
              <div class="session-item">
                <strong>${session.email}</strong><br>
                Device: ${session.deviceId}<br>
                Location: ${session.location.city}<br>
                Age: ${session.age}s
              </div>
            `;
          });
        }
        html += '</div>';

        document.getElementById('sessionList').innerHTML = html;
      } catch (error) {
        console.error('Failed to load sessions:', error);
      }
    }

    async function loadDecisionLog() {
      try {
        const response = await fetch('http://localhost:3002/policy/decisions');
        const data = await response.json();

        let html = `
          <div class="metrics" style="margin: 15px 0;">
            <div class="metric-card">
              <h4>${data.stats.total}</h4>
              <p>Total Decisions</p>
            </div>
            <div class="metric-card">
              <h4>${data.stats.allowed}</h4>
              <p>Allowed</p>
            </div>
            <div class="metric-card">
              <h4>${data.stats.denied}</h4>
              <p>Denied</p>
            </div>
          </div>
        `;

        data.decisions.slice(0, 10).forEach(decision => {
          const deniedClass = decision.decision === 'DENY' ? 'denied' : '';
          const decisionClass = decision.decision === 'ALLOW' ? 'allow' : 'deny';
          html += `
            <div class="log-entry ${deniedClass}">
              <span class="timestamp">${new Date(decision.timestamp).toLocaleTimeString()}</span>
              <span class="decision ${decisionClass}">${decision.decision}</span><br>
              User: ${decision.email} → ${decision.resource}<br>
              ${decision.reason} (${decision.latency}ms)
            </div>
          `;
        });

        document.getElementById('decisionLog').innerHTML = html;
      } catch (error) {
        console.error('Failed to load decision log:', error);
      }
    }

    async function loadPolicyStats() {
      try {
        const response = await fetch('http://localhost:3002/policy/decisions');
        const data = await response.json();

        document.getElementById('policyStats').innerHTML = `
          <div class="stat-box">
            <h3>${data.stats.total}</h3>
            <p>Total Policy Evaluations</p>
          </div>
        `;
      } catch (error) {
        console.error('Failed to load policy stats:', error);
      }
    }

    function loadDashboard() {
      loadPolicies();
      loadProxyStats();
      loadSessions();
      loadDecisionLog();
      loadPolicyStats();
    }

    function startAutoRefresh() {
      refreshInterval = setInterval(() => {
        if (accessToken) {
          loadProxyStats();
          loadDecisionLog();
          loadPolicyStats();
        }
      }, 3000);
    }

    function stopAutoRefresh() {
      if (refreshInterval) {
        clearInterval(refreshInterval);
        refreshInterval = null;
      }
    }

    // Auto-update password field based on selected user
    document.getElementById('email').addEventListener('change', function() {
      const passwords = {
        'alice@company.com': 'password123',
        'bob@company.com': 'password456'
      };
      document.getElementById('password').value = passwords[this.value];
    });

    // Initial load
    loadPolicies();
    loadPolicyStats();
  </script>
</body>
</html>
EOF

cat > zero-trust-demo/dashboard/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
COPY public ./public
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# ==================== Docker Compose ====================
cat > zero-trust-demo/docker-compose.yml << 'EOF'
version: '3.8'

services:
  identity-provider:
    build: ./identity-provider
    ports:
      - "3001:3001"
    networks:
      - zero-trust-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3001/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  policy-engine:
    build: ./policy-engine
    ports:
      - "3002:3002"
    networks:
      - zero-trust-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  access-proxy:
    build: ./access-proxy
    ports:
      - "3003:3003"
    depends_on:
      - identity-provider
      - policy-engine
      - protected-service
    networks:
      - zero-trust-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3003/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  protected-service:
    build: ./protected-service
    ports:
      - "3004:3004"
    networks:
      - zero-trust-net
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3004/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  dashboard:
    build: ./dashboard
    ports:
      - "3000:3000"
    depends_on:
      - identity-provider
      - policy-engine
      - access-proxy
    networks:
      - zero-trust-net

networks:
  zero-trust-net:
    driver: bridge
EOF

# ==================== Tests ====================
cat > zero-trust-demo/run-tests.sh << 'EOF'
#!/bin/bash

echo "=================================="
echo "Running Zero-Trust Architecture Tests"
echo "=================================="

# Wait for services
echo "Waiting for services to be ready..."
sleep 15

# Test 1: Identity Provider
echo -e "\n[Test 1] Testing Identity Provider authentication..."
response=$(curl -s -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@company.com","password":"password123","deviceId":"device-001","location":{"city":"SF"}}')

if echo "$response" | grep -q "accessToken"; then
  echo "✓ Identity authentication successful"
  token=$(echo "$response" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
else
  echo "✗ Identity authentication failed"
  exit 1
fi

# Test 2: Token validation
echo -e "\n[Test 2] Testing token validation..."
response=$(curl -s -X POST http://localhost:3001/auth/validate \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$token\"}")

if echo "$response" | grep -q '"valid":true'; then
  echo "✓ Token validation successful"
else
  echo "✗ Token validation failed"
  exit 1
fi

# Test 3: Policy evaluation
echo -e "\n[Test 3] Testing policy engine..."
response=$(curl -s http://localhost:3002/policy/list)

if echo "$response" | grep -q "policies"; then
  echo "✓ Policy engine responding"
else
  echo "✗ Policy engine failed"
  exit 1
fi

# Test 4: Access proxy with valid auth
echo -e "\n[Test 4] Testing access proxy with authentication..."
response=$(curl -s -w "\n%{http_code}" http://localhost:3003/api/public \
  -H "Authorization: Bearer $token")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  echo "✓ Access proxy granted access"
else
  echo "✗ Access proxy test failed (HTTP $http_code)"
  exit 1
fi

# Test 5: Access proxy without auth
echo -e "\n[Test 5] Testing access proxy without authentication..."
response=$(curl -s -w "\n%{http_code}" http://localhost:3003/api/public)

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "401" ]; then
  echo "✓ Access proxy correctly denied unauthenticated request"
else
  echo "✗ Access proxy should have denied request"
  exit 1
fi

# Test 6: Device posture check
echo -e "\n[Test 6] Testing device posture check (insecure device)..."
response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@company.com","password":"password123","deviceId":"device-003","location":{"city":"SF"}}')

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "403" ]; then
  echo "✓ Insecure device correctly rejected"
else
  echo "✗ Device posture check failed"
  exit 1
fi

# Test 7: Policy decision logging
echo -e "\n[Test 7] Testing policy decision logging..."
response=$(curl -s http://localhost:3002/policy/decisions)

if echo "$response" | grep -q "decisions"; then
  echo "✓ Policy decisions being logged"
else
  echo "✗ Policy logging failed"
  exit 1
fi

# Test 8: Active sessions tracking
echo -e "\n[Test 8] Testing active sessions..."
response=$(curl -s http://localhost:3001/auth/sessions)

if echo "$response" | grep -q "sessions"; then
  echo "✓ Session tracking operational"
else
  echo "✗ Session tracking failed"
  exit 1
fi

echo -e "\n=================================="
echo "All tests passed! ✓"
echo "=================================="
echo ""
echo "Access the dashboard at: http://localhost:3000"
echo ""
echo "Try these scenarios:"
echo "1. Login with alice@company.com using device-001 (secure)"
echo "2. Access different endpoints (/api/database, /api/users, /api/public)"
echo "3. Try device-003 (insecure) and observe rejection"
echo "4. Watch policy decisions and proxy statistics update in real-time"
EOF

chmod +x zero-trust-demo/run-tests.sh

echo ""
echo "Building Docker images..."
cd zero-trust-demo && docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 20

echo ""
echo "Running tests..."
./run-tests.sh

echo ""
echo "=================================="
echo "Demo is running!"
echo "=================================="
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
echo "Services:"
echo "- Identity Provider: http://localhost:3001"
echo "- Policy Engine: http://localhost:3002"
echo "- Access Proxy: http://localhost:3003"
echo "- Protected Service: http://localhost:3004"
echo ""
echo "Try these test scenarios in the dashboard:"
echo "1. Login as alice@company.com with device-001 (secure, score 95)"
echo "2. Access /api/database - Should be allowed (engineer role)"
echo "3. Access /api/users - Should be denied (requires admin role)"
echo "4. Change to device-003 (insecure, score 45) and try to login"
echo "5. Observe policy decisions and latency metrics"
echo ""
echo "The system demonstrates:"
echo "- Identity verification with JWT tokens"
echo "- Device posture assessment"
echo "- Policy-based access control"
echo "- Request flow: Identity → Policy → Proxy → Service"
echo "- Real-time monitoring and logging"
echo ""