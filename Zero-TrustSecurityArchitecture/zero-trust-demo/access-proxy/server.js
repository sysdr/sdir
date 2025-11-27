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
