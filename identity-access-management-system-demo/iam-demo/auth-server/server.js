const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const { Pool } = require('pg');
const redis = require('redis');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Configuration
const JWT_SECRET = process.env.JWT_SECRET;
const JWT_ACCESS_EXPIRY = parseInt(process.env.JWT_ACCESS_EXPIRY) || 300; // 5 minutes
const JWT_REFRESH_EXPIRY = parseInt(process.env.JWT_REFRESH_EXPIRY) || 86400; // 1 day

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// Redis connection for session/revocation store
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
    service: 'IAM Auth Server',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      oauth: {
        authorize: '/oauth/authorize',
        token: '/oauth/token',
        revoke: '/oauth/revoke',
        introspect: '/oauth/introspect',
        userinfo: '/oauth/userinfo'
      },
      policy: {
        evaluate: '/policy/evaluate'
      }
    },
    documentation: 'See README.md for usage examples'
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'auth-server' });
});

// OAuth2 Authorization Endpoint - Step 1: Request authorization code
app.get('/oauth/authorize', async (req, res) => {
  const { client_id, redirect_uri, response_type, scope, state } = req.query;

  // Validate client
  const clientResult = await pool.query(
    'SELECT * FROM oauth_clients WHERE client_id = $1',
    [client_id]
  );

  if (clientResult.rows.length === 0) {
    return res.status(400).json({ error: 'invalid_client' });
  }

  const client = clientResult.rows[0];

  // Validate redirect_uri
  if (!client.redirect_uris.includes(redirect_uri)) {
    return res.status(400).json({ error: 'invalid_redirect_uri' });
  }

  if (response_type !== 'code') {
    return res.status(400).json({ error: 'unsupported_response_type' });
  }

  // In production, show consent screen. For demo, auto-approve with dummy user
  // Simulate user authentication - use 'alice' for demo
  const userResult = await pool.query(
    'SELECT id FROM users WHERE username = $1',
    ['alice']
  );

  if (userResult.rows.length === 0) {
    return res.status(400).json({ error: 'user_not_found' });
  }

  const userId = userResult.rows[0].id;

  // Generate authorization code
  const authCode = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + 600000); // 10 minutes

  await pool.query(
    'INSERT INTO auth_codes (code, client_id, user_id, redirect_uri, scope, expires_at) VALUES ($1, $2, $3, $4, $5, $6)',
    [authCode, client_id, userId, redirect_uri, scope || '', expiresAt]
  );

  // Redirect with code and state
  const redirectUrl = new URL(redirect_uri);
  redirectUrl.searchParams.set('code', authCode);
  if (state) redirectUrl.searchParams.set('state', state);

  res.json({
    message: 'Authorization successful',
    redirect_to: redirectUrl.toString(),
    note: 'In browser, user would be redirected to this URL'
  });
});

// OAuth2 Token Endpoint - Step 2: Exchange code for tokens
app.post('/oauth/token', async (req, res) => {
  const { grant_type, code, client_id, client_secret, redirect_uri, refresh_token } = req.body;

  // Validate client credentials
  const clientResult = await pool.query(
    'SELECT * FROM oauth_clients WHERE client_id = $1 AND client_secret = $2',
    [client_id, client_secret]
  );

  if (clientResult.rows.length === 0) {
    return res.status(401).json({ error: 'invalid_client' });
  }

  if (grant_type === 'authorization_code') {
    // Exchange authorization code for tokens
    const codeResult = await pool.query(
      'SELECT * FROM auth_codes WHERE code = $1 AND client_id = $2 AND expires_at > NOW()',
      [code, client_id]
    );

    if (codeResult.rows.length === 0) {
      return res.status(400).json({ error: 'invalid_grant' });
    }

    const authCode = codeResult.rows[0];

    if (authCode.redirect_uri !== redirect_uri) {
      return res.status(400).json({ error: 'invalid_redirect_uri' });
    }

    // Get user and roles
    const userResult = await pool.query(`
      SELECT u.id, u.username, u.email, array_agg(r.name) as roles
      FROM users u
      LEFT JOIN user_roles ur ON u.id = ur.user_id
      LEFT JOIN roles r ON ur.role_id = r.id
      WHERE u.id = $1
      GROUP BY u.id
    `, [authCode.user_id]);

    const user = userResult.rows[0];

    // Generate tokens
    const accessToken = jwt.sign(
      { 
        sub: user.id, 
        username: user.username, 
        email: user.email,
        roles: user.roles,
        type: 'access'
      },
      JWT_SECRET,
      { expiresIn: JWT_ACCESS_EXPIRY }
    );

    const refreshTokenValue = crypto.randomBytes(32).toString('hex');
    const refreshExpiresAt = new Date(Date.now() + JWT_REFRESH_EXPIRY * 1000);

    // Store refresh token
    await pool.query(
      'INSERT INTO refresh_tokens (token, user_id, client_id, expires_at) VALUES ($1, $2, $3, $4)',
      [refreshTokenValue, user.id, client_id, refreshExpiresAt]
    );

    // Delete used authorization code
    await pool.query('DELETE FROM auth_codes WHERE code = $1', [code]);

    // Store session in Redis for hybrid validation
    await redisClient.setEx(
      `session:${user.id}`,
      JWT_ACCESS_EXPIRY,
      JSON.stringify({ userId: user.id, username: user.username })
    );

    res.json({
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: JWT_ACCESS_EXPIRY,
      refresh_token: refreshTokenValue,
      scope: authCode.scope
    });

  } else if (grant_type === 'refresh_token') {
    // Refresh token flow
    const tokenResult = await pool.query(
      'SELECT * FROM refresh_tokens WHERE token = $1 AND client_id = $2 AND expires_at > NOW()',
      [refresh_token, client_id]
    );

    if (tokenResult.rows.length === 0) {
      return res.status(400).json({ error: 'invalid_grant' });
    }

    const token = tokenResult.rows[0];

    // Get user and roles
    const userResult = await pool.query(`
      SELECT u.id, u.username, u.email, array_agg(r.name) as roles
      FROM users u
      LEFT JOIN user_roles ur ON u.id = ur.user_id
      LEFT JOIN roles r ON ur.role_id = r.id
      WHERE u.id = $1
      GROUP BY u.id
    `, [token.user_id]);

    const user = userResult.rows[0];

    // Generate new access token
    const accessToken = jwt.sign(
      { 
        sub: user.id, 
        username: user.username, 
        email: user.email,
        roles: user.roles,
        type: 'access'
      },
      JWT_SECRET,
      { expiresIn: JWT_ACCESS_EXPIRY }
    );

    res.json({
      access_token: accessToken,
      token_type: 'Bearer',
      expires_in: JWT_ACCESS_EXPIRY
    });

  } else {
    res.status(400).json({ error: 'unsupported_grant_type' });
  }
});

// Token Revocation Endpoint
app.post('/oauth/revoke', async (req, res) => {
  const { token, token_type_hint } = req.body;

  if (token_type_hint === 'refresh_token' || !token_type_hint) {
    // Revoke refresh token
    await pool.query('DELETE FROM refresh_tokens WHERE token = $1', [token]);
  }

  // Add access token to revocation list in Redis
  // In production, decode JWT to get expiry and set Redis TTL accordingly
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const ttl = decoded.exp - Math.floor(Date.now() / 1000);
    if (ttl > 0) {
      await redisClient.setEx(`revoked:${token}`, ttl, '1');
      // Also invalidate session
      await redisClient.del(`session:${decoded.sub}`);
    }
  } catch (err) {
    // Token invalid or expired, ignore
  }

  res.json({ message: 'Token revoked successfully' });
});

// Token Introspection Endpoint (for resource servers)
app.post('/oauth/introspect', async (req, res) => {
  const { token } = req.body;

  try {
    // Check if token is revoked
    const isRevoked = await redisClient.get(`revoked:${token}`);
    if (isRevoked) {
      return res.json({ active: false });
    }

    // Verify JWT
    const decoded = jwt.verify(token, JWT_SECRET);

    // Hybrid validation: check session exists in Redis
    const session = await redisClient.get(`session:${decoded.sub}`);
    if (!session) {
      return res.json({ active: false, reason: 'session_expired' });
    }

    // Get current permissions
    const permResult = await pool.query(`
      SELECT DISTINCT p.resource, p.action
      FROM users u
      JOIN user_roles ur ON u.id = ur.user_id
      JOIN role_permissions rp ON ur.role_id = rp.role_id
      JOIN permissions p ON rp.permission_id = p.id
      WHERE u.id = $1
    `, [decoded.sub]);

    const permissions = permResult.rows.map(p => `${p.action}:${p.resource}`);

    res.json({
      active: true,
      sub: decoded.sub,
      username: decoded.username,
      email: decoded.email,
      roles: decoded.roles,
      permissions: permissions,
      exp: decoded.exp,
      iat: decoded.iat
    });

  } catch (err) {
    res.json({ active: false, error: err.message });
  }
});

// User info endpoint
app.get('/oauth/userinfo', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const token = authHeader.substring(7);

  try {
    const decoded = jwt.verify(token, JWT_SECRET);

    const userResult = await pool.query(
      'SELECT id, username, email, created_at FROM users WHERE id = $1',
      [decoded.sub]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'user_not_found' });
    }

    res.json(userResult.rows[0]);
  } catch (err) {
    res.status(401).json({ error: 'invalid_token' });
  }
});

// ABAC policy evaluation (example)
app.post('/policy/evaluate', async (req, res) => {
  const { user_id, resource_type, action, context } = req.body;

  // Get ABAC policies for resource type
  const policies = await pool.query(
    'SELECT * FROM abac_policies WHERE resource_type = $1 ORDER BY priority DESC',
    [resource_type]
  );

  // Simple time-based policy evaluation
  let allowed = false;
  for (const policy of policies.rows) {
    const conditions = policy.conditions;
    
    // Example: check time of day
    if (conditions.time_of_day && context.current_time) {
      const currentHour = new Date(context.current_time).getHours();
      const startHour = parseInt(conditions.time_of_day.start.split(':')[0]);
      const endHour = parseInt(conditions.time_of_day.end.split(':')[0]);
      
      if (currentHour >= startHour && currentHour < endHour) {
        allowed = policy.effect === 'allow';
      }
    }
  }

  res.json({ allowed, evaluated_policies: policies.rows.length });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`✓ Auth Server running on port ${PORT}`);
});
