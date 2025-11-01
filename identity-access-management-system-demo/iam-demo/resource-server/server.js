const express = require('express');
const jwt = require('jsonwebtoken');
const axios = require('axios');
const redis = require('redis');

const app = express();
app.use(express.json());

const JWT_SECRET = process.env.JWT_SECRET;
const AUTH_SERVER_URL = process.env.AUTH_SERVER_URL;

// Redis connection for checking revocation
let redisClient;
(async () => {
  redisClient = redis.createClient({
    socket: { host: process.env.REDIS_HOST, port: process.env.REDIS_PORT }
  });
  await redisClient.connect();
  console.log('✓ Redis connected');
})();

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'IAM Resource Server',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      public: {
        info: '/api/public/info'
      },
      protected: {
        documents: {
          list: 'GET /api/documents',
          create: 'POST /api/documents',
          delete: 'DELETE /api/documents/:id'
        }
      }
    },
    note: 'Protected endpoints require Bearer token in Authorization header',
    documentation: 'See README.md for usage examples'
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'resource-server' });
});

// Middleware to validate JWT and check revocation
async function authenticateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided' });
  }

  const token = authHeader.substring(7);

  try {
    // First, check if token is revoked (fast Redis lookup)
    const isRevoked = await redisClient.get(`revoked:${token}`);
    if (isRevoked) {
      return res.status(401).json({ error: 'Token has been revoked' });
    }

    // Verify JWT signature and expiry
    const decoded = jwt.verify(token, JWT_SECRET);

    // Hybrid validation: check session in Redis
    const session = await redisClient.get(`session:${decoded.sub}`);
    if (!session) {
      return res.status(401).json({ error: 'Session expired or invalid' });
    }

    // Optional: Call auth server introspection for detailed validation
    // This demonstrates the hybrid pattern: local JWT + optional remote validation
    
    req.user = decoded;
    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid token', details: err.message });
  }
}

// Middleware to check permissions (RBAC)
function requirePermission(resource, action) {
  return async (req, res, next) => {
    // Call auth server to get current permissions
    try {
      const introspectResponse = await axios.post(
        `${AUTH_SERVER_URL}/oauth/introspect`,
        { token: req.headers.authorization.substring(7) }
      );

      const { active, permissions } = introspectResponse.data;

      if (!active) {
        return res.status(401).json({ error: 'Token not active' });
      }

      const requiredPermission = `${action}:${resource}`;
      if (!permissions.includes(requiredPermission)) {
        return res.status(403).json({ 
          error: 'Insufficient permissions',
          required: requiredPermission,
          has: permissions
        });
      }

      next();
    } catch (err) {
      res.status(500).json({ error: 'Permission check failed', details: err.message });
    }
  };
}

// Protected resource endpoints
app.get('/api/documents', authenticateToken, requirePermission('documents', 'read'), (req, res) => {
  res.json({
    message: 'Document list',
    documents: [
      { id: 1, title: 'Q4 Report', owner: 'alice' },
      { id: 2, title: 'Architecture Design', owner: 'bob' },
      { id: 3, title: 'IAM Strategy', owner: 'admin' }
    ],
    accessed_by: req.user.username,
    roles: req.user.roles
  });
});

app.post('/api/documents', authenticateToken, requirePermission('documents', 'write'), (req, res) => {
  res.json({
    message: 'Document created successfully',
    document: { id: 4, title: req.body.title || 'New Document', owner: req.user.username }
  });
});

app.delete('/api/documents/:id', authenticateToken, requirePermission('documents', 'delete'), (req, res) => {
  res.json({
    message: 'Document deleted successfully',
    document_id: req.params.id,
    deleted_by: req.user.username
  });
});

// Simple public endpoint (no auth required)
app.get('/api/public/info', (req, res) => {
  res.json({
    message: 'Public information - no authentication required',
    service: 'IAM Demo Resource Server',
    timestamp: new Date().toISOString()
  });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`✓ Resource Server running on port ${PORT}`);
});
