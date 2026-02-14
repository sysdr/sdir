const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const WebSocket = require('ws');
const http = require('http');

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Direct connection pool — demonstrates storm vulnerability
const directPool = new Pool({
  host: process.env.POSTGRES_HOST || 'postgres',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'demo_db',
  user: process.env.POSTGRES_USER || 'app_user',
  password: process.env.POSTGRES_PASSWORD || 'app_password123',
  max: 10,
  min: 2,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 3000,
});

// PgBouncer-backed pool — storm resistant
const pooledPool = new Pool({
  host: process.env.PGBOUNCER_HOST || 'pgbouncer',
  port: parseInt(process.env.PGBOUNCER_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'demo_db',
  user: process.env.POSTGRES_USER || 'app_user',
  password: process.env.POSTGRES_PASSWORD || 'app_password123',
  max: 50,
  min: 5,
  idleTimeoutMillis: 60000,
  connectionTimeoutMillis: 5000,
});

const metrics = {
  direct:  { totalRequests: 0, successRequests: 0, failedRequests: 0, rejectedRequests: 0, activeStorms: 0, avgLatencyMs: 0, latencies: [] },
  pooled:  { totalRequests: 0, successRequests: 0, failedRequests: 0, rejectedRequests: 0, activeStorms: 0, avgLatencyMs: 0, latencies: [] },
  connectionStats: { active: 0, idle: 0, idleInTransaction: 0, total: 0, maxConnections: 20 },
  logs: [],
};

function addLog(type, message, data = {}) {
  const entry = { ts: new Date().toISOString(), type, message, ...data };
  metrics.logs.unshift(entry);
  if (metrics.logs.length > 100) metrics.logs = metrics.logs.slice(0, 100);
  broadcast({ type: 'log', data: entry });
}

function updateLatency(pool, ms) {
  pool.latencies.push(ms);
  if (pool.latencies.length > 200) pool.latencies.shift();
  pool.avgLatencyMs = Math.round(pool.latencies.reduce((a, b) => a + b, 0) / pool.latencies.length);
}

function broadcast(msg) {
  const payload = JSON.stringify(msg);
  wss.clients.forEach(c => { if (c.readyState === WebSocket.OPEN) c.send(payload); });
}

async function pollConnectionStats() {
  try {
    const client = await directPool.connect();
    try {
      const r = await client.query(`SELECT COALESCE(state,'unknown') as state, count(*) as count FROM pg_stat_activity WHERE datname = 'demo_db' GROUP BY state`);
      const m = await client.query('SHOW max_connections');
      const s = { active: 0, idle: 0, idleInTransaction: 0, total: 0 };
      r.rows.forEach(row => {
        const n = parseInt(row.count);
        s.total += n;
        if (row.state === 'active') s.active = n;
        else if (row.state === 'idle') s.idle = n;
        else if (row.state === 'idle in transaction') s.idleInTransaction = n;
      });
      s.maxConnections = parseInt(m.rows[0].max_connections);
      metrics.connectionStats = s;
    } finally { client.release(); }
  } catch {}
  broadcast({ type: 'metrics', data: { connectionStats: metrics.connectionStats } });
}

app.get('/health', (_, res) => res.json({ status: 'ok', ts: Date.now() }));
app.get('/api/metrics', (_, res) => res.json({ ...metrics, logs: metrics.logs.slice(0, 20) }));

app.get('/api/query/direct', async (req, res) => {
  const start = Date.now();
  metrics.direct.totalRequests++;
  try {
    const client = await directPool.connect();
    try {
      await client.query('SELECT id, name, price FROM products ORDER BY RANDOM() LIMIT 10');
      const ms = Date.now() - start;
      metrics.direct.successRequests++;
      updateLatency(metrics.direct, ms);
      res.json({ ok: true, ms, source: 'direct' });
    } finally { client.release(); }
  } catch (err) {
    metrics.direct.failedRequests++;
    if (err.message.includes('timeout') || err.message.includes('remaining connection') || err.message.includes('pool')) metrics.direct.rejectedRequests++;
    res.status(503).json({ ok: false, error: err.message, source: 'direct' });
  }
});

app.get('/api/query/pooled', async (req, res) => {
  const start = Date.now();
  metrics.pooled.totalRequests++;
  try {
    const client = await pooledPool.connect();
    try {
      await client.query('SELECT id, name, price FROM products ORDER BY RANDOM() LIMIT 10');
      const ms = Date.now() - start;
      metrics.pooled.successRequests++;
      updateLatency(metrics.pooled, ms);
      res.json({ ok: true, ms, source: 'pooled' });
    } finally { client.release(); }
  } catch (err) {
    metrics.pooled.failedRequests++;
    if (err.message.includes('timeout') || err.message.includes('remaining connection') || err.message.includes('pool')) metrics.pooled.rejectedRequests++;
    res.status(503).json({ ok: false, error: err.message, source: 'pooled' });
  }
});

app.post('/api/storm/:mode', async (req, res) => {
  const { mode } = req.params;
  const { concurrency = 30, holdMs = 500 } = req.body;
  const pool = mode === 'direct' ? directPool : pooledPool;
  const key = mode === 'direct' ? 'direct' : 'pooled';

  addLog('storm_start', `🌩️ Storm started: ${concurrency} concurrent (${mode})`, { concurrency, holdMs, mode });
  metrics[key].activeStorms++;
  res.json({ started: true, concurrency, mode });

  Promise.all(Array.from({ length: concurrency }, async (_, i) => {
    const start = Date.now();
    metrics[key].totalRequests++;
    try {
      const client = await pool.connect();
      try {
        await client.query('SELECT slow_query($1)', [holdMs]);
        metrics[key].successRequests++;
        updateLatency(metrics[key], Date.now() - start);
      } finally { client.release(); }
    } catch (err) {
      metrics[key].failedRequests++;
      const isRej = err.message.includes('timeout') || err.message.includes('remaining connection') || err.message.includes('pool');
      if (isRej) { metrics[key].rejectedRequests++; addLog('storm_reject', `❌ [${mode}] conn ${i+1}: ${err.message.slice(0,80)}`, { mode }); }
    }
  })).then(() => {
    metrics[key].activeStorms = Math.max(0, metrics[key].activeStorms - 1);
    addLog('storm_end', `✅ Storm done [${mode}] · success: ${metrics[key].successRequests} · rejected: ${metrics[key].rejectedRequests}`, { mode });
    broadcast({ type: 'metrics', data: { [key]: metrics[key] } });
  });
});

app.post('/api/reset', (_, res) => {
  metrics.direct  = { totalRequests: 0, successRequests: 0, failedRequests: 0, rejectedRequests: 0, activeStorms: 0, avgLatencyMs: 0, latencies: [] };
  metrics.pooled  = { totalRequests: 0, successRequests: 0, failedRequests: 0, rejectedRequests: 0, activeStorms: 0, avgLatencyMs: 0, latencies: [] };
  metrics.logs = [];
  addLog('reset', '🔄 Metrics reset');
  res.json({ ok: true });
});

wss.on('connection', ws => ws.send(JSON.stringify({ type: 'init', data: metrics })));
setInterval(pollConnectionStats, 2000);
setInterval(() => broadcast({ type: 'metrics', data: metrics }), 3000);

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => { console.log(`[backend] Listening on port ${PORT}`); addLog('startup', `🚀 Backend started`); });
