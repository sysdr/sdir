'use strict';

const express = require('express');
const http    = require('http');
const WebSocket = require('ws');
const vault   = require('node-vault');
const { Pool } = require('pg');
const path    = require('path');
const { v4: uuidv4 } = require('uuid');

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocket.Server({ server });

app.use(express.json());

// Chrome DevTools requests this; serve empty JSON to avoid 404 and CSP noise in console
app.get('/.well-known/appspecific/com.chrome.devtools.json', (req, res) => {
  res.type('application/json').status(200).send('{}');
});

app.use(express.static(path.join(__dirname, 'frontend')));

// ── Vault client ────────────────────────────────────────────
const vc = vault({
  apiVersion: 'v1',
  endpoint:   process.env.VAULT_ADDR   || 'http://localhost:8200',
  token:      process.env.VAULT_TOKEN  || 'dev-root-token',
});

// ── State ────────────────────────────────────────────────────
const activeLeases   = new Map(); // leaseId → { username, password, issuedAt, ttl, expiresAt, path }
const auditLog       = [];
const MAX_AUDIT      = 50;

let vaultInitialized = false;
let pgAdminPool      = null;

// ── Broadcast helper ─────────────────────────────────────────
function broadcast(type, payload) {
  const msg = JSON.stringify({ type, payload, ts: Date.now() });
  wss.clients.forEach(c => { if (c.readyState === WebSocket.OPEN) c.send(msg); });
}

function addAudit(action, detail, level = 'info') {
  const entry = { id: uuidv4().slice(0,8), ts: Date.now(), action, detail, level };
  auditLog.unshift(entry);
  if (auditLog.length > MAX_AUDIT) auditLog.pop();
  broadcast('audit', entry);
  console.log(`[AUDIT][${level.toUpperCase()}] ${action}: ${detail}`);
}

// ── Vault initialization ─────────────────────────────────────
async function initVault() {
  console.log('[INIT] Waiting for Vault...');
  for (let i = 0; i < 30; i++) {
    try {
      const status = await vc.status();
      if (status.initialized) break;
    } catch (_) {
      await new Promise(r => setTimeout(r, 1000));
    }
  }

  // Enable KV v2
  try {
    await vc.mount({ mount_point: 'secret', type: 'kv', description: 'KV v2 store', config: { options: { version: '2' } }});
    addAudit('vault.mount', 'Mounted KV v2 at secret/', 'info');
  } catch (e) {
    if (!e.message.includes('path is already in use')) {
      console.warn('[INIT] KV mount warning:', e.message);
    }
    addAudit('vault.mount', 'KV v2 already mounted at secret/', 'info');
  }

  // Seed demo KV secrets
  const demoSecrets = [
    { path: 'secret/data/app/database', data: { host: 'postgres', port: '5432', db: 'appdb' }},
    { path: 'secret/data/app/stripe',   data: { api_key: 'REPLACE_WITH_YOUR_STRIPE_KEY', webhook_secret: 'REPLACE_WITH_YOUR_WEBHOOK_SECRET' }},
    { path: 'secret/data/app/redis',    data: { host: 'redis', port: '6379', password: 'r3dis_s3cr3t' }},
  ];
  for (const s of demoSecrets) {
    try {
      await vc.write(s.path, { data: s.data });
      addAudit('kv.write', `Seeded ${s.path}`, 'info');
    } catch (e) { console.warn('[INIT] KV seed warning:', e.message); }
  }

  // Enable Database secrets engine
  try {
    await vc.mount({ mount_point: 'database', type: 'database', description: 'Dynamic DB creds' });
    addAudit('vault.mount', 'Mounted database engine at database/', 'info');
  } catch (e) {
    if (!e.message.includes('path is already in use')) console.warn('[INIT] DB mount warning:', e.message);
    addAudit('vault.mount', 'Database engine already mounted', 'info');
  }

  // Configure PostgreSQL connection
  try {
    await vc.write('database/config/postgresql', {
      plugin_name:          'postgresql-database-plugin',
      allowed_roles:        'app-role,readonly-role',
      connection_url:       'postgresql://{{username}}:{{password}}@postgres:5432/appdb?sslmode=disable',
      username:             'postgres',
      password:             'postgres_root',
      max_open_connections: 5,
      max_idle_connections: 2,
    });
    addAudit('vault.config', 'Configured PostgreSQL connection', 'info');
  } catch (e) { console.warn('[INIT] DB config warning:', e.message); }

  // Create DB role — short TTL for demo visibility
  try {
    await vc.write('database/roles/app-role', {
      db_name:               'postgresql',
      creation_statements:   [
        `CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';`,
        `GRANT CONNECT ON DATABASE appdb TO "{{name}}";`,
        `GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO "{{name}}";`,
      ],
      revocation_statements: [`DROP ROLE IF EXISTS "{{name}}";`],
      default_ttl:           '120s',   // 2 min for demo visibility
      max_ttl:               '300s',
    });
    addAudit('vault.role', 'Created DB role: app-role (TTL 120s)', 'info');
  } catch (e) { console.warn('[INIT] DB role warning:', e.message); }

  try {
    await vc.write('database/roles/readonly-role', {
      db_name:               'postgresql',
      creation_statements:   [
        `CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';`,
        `GRANT CONNECT ON DATABASE appdb TO "{{name}}";`,
        `GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";`,
      ],
      revocation_statements: [`DROP ROLE IF EXISTS "{{name}}";`],
      default_ttl:           '60s',
      max_ttl:               '180s',
    });
    addAudit('vault.role', 'Created DB role: readonly-role (TTL 60s)', 'info');
  } catch (e) { console.warn('[INIT] readonly role warning:', e.message); }

  // Admin PG pool for verification
  pgAdminPool = new Pool({
    host:     process.env.PG_HOST     || 'localhost',
    port:     parseInt(process.env.PG_PORT || '5432'),
    database: process.env.PG_DB       || 'appdb',
    user:     process.env.PG_ADMIN_USER || 'postgres',
    password: process.env.PG_ADMIN_PASS || 'postgres_root',
  });

  vaultInitialized = true;
  addAudit('vault.init', 'Vault initialization complete', 'success');
  broadcast('status', { vaultInitialized: true, message: 'Vault ready' });
  console.log('[INIT] Vault initialization complete');
}

// ── Lease expiry watcher ─────────────────────────────────────
setInterval(async () => {
  const now = Date.now();
  for (const [id, lease] of activeLeases.entries()) {
    const remaining = Math.max(0, Math.floor((lease.expiresAt - now) / 1000));
    lease.remainingSec = remaining;

    if (remaining <= 0 && !lease.expired) {
      lease.expired = true;
      addAudit('lease.expired', `Lease ${id.slice(0,8)} expired — credentials revoked`, 'warn');
      // Attempt Vault revocation
      try {
        await vc.write('sys/leases/revoke', { lease_id: lease.vaultLeaseId });
      } catch (_) { /* may already be revoked */ }
      activeLeases.delete(id);
    }
  }
  broadcast('leases', Array.from(activeLeases.values()).map(l => ({
    id:           l.id,
    role:         l.role,
    username:     l.username,
    issuedAt:     l.issuedAt,
    expiresAt:    l.expiresAt,
    remainingSec: l.remainingSec || 0,
    expired:      l.expired || false,
  })));
}, 2000);

// ═══════════════════════════════════════════════════════════
// API ROUTES
// ═══════════════════════════════════════════════════════════

// ── GET /api/status ─────────────────────────────────────────
app.get('/api/status', async (req, res) => {
  try {
    const status = await vc.status();
    res.json({ ok: true, vault: status, initialized: vaultInitialized });
  } catch (e) {
    res.status(503).json({ ok: false, error: e.message });
  }
});

// ── GET /api/secrets ────────────────────────────────────────
app.get('/api/secrets', async (req, res) => {
  try {
    const listResult = await vc.list('secret/metadata/app');
    const keys = listResult.data.keys || [];
    const secrets = [];
    for (const key of keys) {
      try {
        const r = await vc.read(`secret/data/app/${key}`);
        secrets.push({
          path:    `app/${key}`,
          data:    r.data.data,
          version: r.data.metadata.version,
          created: r.data.metadata.created_time,
        });
      } catch (_) {}
    }
    res.json({ ok: true, secrets });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── POST /api/secrets ───────────────────────────────────────
app.post('/api/secrets', async (req, res) => {
  const { path: sPath, key, value } = req.body;
  if (!sPath || !key || !value) return res.status(400).json({ error: 'path, key, value required' });
  try {
    // Read existing, merge, write back
    let existing = {};
    try {
      const r = await vc.read(`secret/data/${sPath}`);
      existing = r.data.data;
    } catch (_) {}
    existing[key] = value;
    await vc.write(`secret/data/${sPath}`, { data: existing });
    addAudit('kv.write', `Updated secret at ${sPath} key=${key}`, 'info');
    res.json({ ok: true, message: `Secret written to ${sPath}` });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── POST /api/creds/dynamic ─────────────────────────────────
app.post('/api/creds/dynamic', async (req, res) => {
  const role = req.body.role || 'app-role';
  if (!['app-role', 'readonly-role'].includes(role)) {
    return res.status(400).json({ error: 'Invalid role' });
  }
  try {
    const result = await vc.read(`database/creds/${role}`);
    const { username, password } = result.data;
    const vaultLeaseId = result.lease_id;
    const ttlSec       = result.lease_duration;
    const now          = Date.now();
    const id           = uuidv4();

    const lease = {
      id,
      vaultLeaseId,
      role,
      username,
      password,
      issuedAt:     now,
      expiresAt:    now + ttlSec * 1000,
      remainingSec: ttlSec,
      expired:      false,
    };
    activeLeases.set(id, lease);
    addAudit('creds.issued', `Dynamic cred issued: ${username} (role=${role}, TTL=${ttlSec}s)`, 'success');

    res.json({
      ok:           true,
      id,
      username,
      password,
      role,
      ttlSeconds:   ttlSec,
      expiresAt:    new Date(now + ttlSec * 1000).toISOString(),
    });
  } catch (e) {
    addAudit('creds.error', `Failed to issue cred for ${role}: ${e.message}`, 'error');
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── DELETE /api/creds/:id ────────────────────────────────────
app.delete('/api/creds/:id', async (req, res) => {
  const lease = activeLeases.get(req.params.id);
  if (!lease) return res.status(404).json({ error: 'Lease not found' });
  try {
    await vc.write('sys/leases/revoke', { lease_id: lease.vaultLeaseId });
    addAudit('creds.revoked', `Manually revoked lease for ${lease.username}`, 'warn');
    activeLeases.delete(req.params.id);
    res.json({ ok: true, message: `Revoked ${lease.username}` });
  } catch (e) {
    // Remove from tracking even if Vault revoke fails
    activeLeases.delete(req.params.id);
    addAudit('creds.revoked', `Revoked (forced) lease for ${lease.username}`, 'warn');
    res.json({ ok: true, message: `Removed ${lease.username} from tracking` });
  }
});

// ── GET /api/leases ─────────────────────────────────────────
app.get('/api/leases', (req, res) => {
  res.json({
    ok:     true,
    leases: Array.from(activeLeases.values()).map(l => ({
      id:           l.id,
      role:         l.role,
      username:     l.username,
      issuedAt:     l.issuedAt,
      expiresAt:    l.expiresAt,
      remainingSec: Math.max(0, Math.floor((l.expiresAt - Date.now()) / 1000)),
      expired:      l.expired || false,
    })),
  });
});

// ── POST /api/rotate ─────────────────────────────────────────
app.post('/api/rotate', async (req, res) => {
  const { path: sPath, key } = req.body;
  if (!sPath || !key) return res.status(400).json({ error: 'path and key required' });
  try {
    const r        = await vc.read(`secret/data/${sPath}`);
    const existing = r.data.data;
    const version  = r.data.metadata.version;
    const chars    = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%';
    const newVal   = Array.from({length: 32}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    existing[key]  = newVal;
    await vc.write(`secret/data/${sPath}`, { data: existing });
    addAudit('kv.rotate', `Rotated ${key} at ${sPath} (was v${version})`, 'warn');
    res.json({ ok: true, newVersion: version + 1, message: `Rotated ${key} at ${sPath}` });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── GET /api/audit ───────────────────────────────────────────
app.get('/api/audit', (req, res) => {
  res.json({ ok: true, events: auditLog.slice(0, 30) });
});

// ── Verify DB cred ────────────────────────────────────────────
app.post('/api/verify-cred', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ error: 'username + password required' });
  const pool = new Pool({
    host:     process.env.PG_HOST || 'localhost',
    port:     parseInt(process.env.PG_PORT || '5432'),
    database: process.env.PG_DB   || 'appdb',
    user:     username,
    password: password,
    connectionTimeoutMillis: 5000,
  });
  try {
    const r = await pool.query('SELECT current_user, current_timestamp, version()');
    await pool.end();
    addAudit('creds.verify', `Connection verified for ${username}`, 'success');
    res.json({ ok: true, currentUser: r.rows[0].current_user, timestamp: r.rows[0].current_timestamp });
  } catch (e) {
    await pool.end().catch(() => {});
    addAudit('creds.verify', `Connection FAILED for ${username}: ${e.message}`, 'error');
    res.json({ ok: false, error: e.message });
  }
});

// ── WebSocket ─────────────────────────────────────────────────
wss.on('connection', (ws) => {
  // Send full state on connect
  ws.send(JSON.stringify({ type: 'init', payload: {
    leases:  Array.from(activeLeases.values()),
    audit:   auditLog.slice(0, 20),
    initialized: vaultInitialized,
  }}));
});

// ── Start ─────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, async () => {
  console.log(`[SERVER] Listening on port ${PORT}`);
  await initVault().catch(e => console.error('[INIT] Fatal:', e));
});
