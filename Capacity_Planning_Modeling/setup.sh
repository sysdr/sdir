#!/bin/bash
# =============================================================================
# Article 201: Capacity Planning Modeling — Little's Law Demo
# Demonstrates L = λW across a multi-tier system (Gateway → App → PostgreSQL)
# =============================================================================

set -e

# Demo directory: use project-relative path so it works in restricted environments
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEMO_DIR="${DEMO_DIR:-$SCRIPT_DIR/littles-law-demo}"
NETWORK="littles-law-net"
COMPOSE_FILE="$DEMO_DIR/docker-compose.yml"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Little's Law Capacity Planning Demo — Article 201       ║"
echo "║     L = λW | Concurrency = Rate × Latency                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. DIRECTORY STRUCTURE
# =============================================================================
echo "📁 Creating directory structure..."
mkdir -p "$DEMO_DIR"/{api-gateway,app-server,load-generator,dashboard/src,postgres-init}

# =============================================================================
# 2. POSTGRESQL INIT SCRIPT
# =============================================================================
cat > "$DEMO_DIR/postgres-init/01-init.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS requests (
  id SERIAL PRIMARY KEY,
  layer VARCHAR(20),
  arrived_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  latency_ms INTEGER
);

CREATE TABLE IF NOT EXISTS metrics_snapshot (
  id SERIAL PRIMARY KEY,
  captured_at TIMESTAMPTZ DEFAULT NOW(),
  layer VARCHAR(20),
  lambda_rps NUMERIC(10,2),
  w_ms NUMERIC(10,2),
  l_concurrent NUMERIC(10,2),
  pool_limit INTEGER,
  utilization_pct NUMERIC(5,2)
);

CREATE INDEX idx_requests_layer ON requests(layer);
CREATE INDEX idx_requests_arrived ON requests(arrived_at);
EOF

# =============================================================================
# 3. API GATEWAY SERVICE
# =============================================================================
cat > "$DEMO_DIR/api-gateway/package.json" << 'EOF'
{
  "name": "api-gateway",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.19.2",
    "node-fetch": "^3.3.2",
    "pg": "^8.12.0",
    "prom-client": "^15.1.3"
  }
}
EOF

cat > "$DEMO_DIR/api-gateway/server.js" << 'EOF'
import express from 'express';
import fetch from 'node-fetch';
import pg from 'pg';
import { Registry, Gauge, Counter, Histogram } from 'prom-client';

const app = express();
const PORT = 3001;
const APP_SERVER_URL = process.env.APP_SERVER_URL || 'http://app-server:3002';

// Metrics registry
const register = new Registry();
const activeRequests = new Gauge({ name: 'gateway_active_requests', help: 'Active concurrent requests (L)', registers: [register] });
const requestRate = new Counter({ name: 'gateway_requests_total', help: 'Total requests (λ basis)', registers: [register] });
const latencyHistogram = new Histogram({
  name: 'gateway_request_duration_ms',
  help: 'Request latency in ms (W)',
  buckets: [5, 10, 25, 50, 100, 200, 500, 1000],
  registers: [register]
});

// DB pool - sized by Little's Law
const pool = new pg.Pool({
  host: process.env.PGHOST || 'postgres',
  database: process.env.PGDATABASE || 'littleslaw',
  user: process.env.PGUSER || 'demo',
  password: process.env.PGPASSWORD || 'demo',
  max: 10  // gateway rarely touches DB directly
});

let concurrentRequests = 0;
const CONCURRENCY_LIMIT = parseInt(process.env.CONCURRENCY_LIMIT || '50');

app.get('/health', (req, res) => res.json({ status: 'ok', layer: 'gateway' }));

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/api/process', async (req, res) => {
  const startTime = Date.now();
  
  // Enforce concurrency limit (simulates thread pool / connection limit)
  if (concurrentRequests >= CONCURRENCY_LIMIT) {
    return res.status(429).json({
      error: 'Concurrency limit exceeded',
      layer: 'gateway',
      current_L: concurrentRequests,
      limit: CONCURRENCY_LIMIT,
      message: `L=${concurrentRequests} >= pool limit=${CONCURRENCY_LIMIT}. Queue forming!`
    });
  }

  concurrentRequests++;
  activeRequests.set(concurrentRequests);
  requestRate.inc();

  try {
    const response = await fetch(`${APP_SERVER_URL}/api/work`, {
      signal: AbortSignal.timeout(5000)
    });
    const data = await response.json();
    
    const latency = Date.now() - startTime;
    latencyHistogram.observe(latency);

    // Record to DB
    await pool.query(
      'INSERT INTO requests(layer, latency_ms) VALUES($1, $2)',
      ['gateway', latency]
    );

    res.json({
      layer: 'gateway',
      status: 'ok',
      gateway_latency_ms: latency,
      downstream: data,
      current_L: concurrentRequests,
      concurrency_limit: CONCURRENCY_LIMIT,
      utilization_pct: ((concurrentRequests / CONCURRENCY_LIMIT) * 100).toFixed(1)
    });
  } catch (err) {
    res.status(500).json({ error: err.message, layer: 'gateway' });
  } finally {
    concurrentRequests--;
    activeRequests.set(concurrentRequests);
  }
});

// Live Little's Law stats endpoint
app.get('/api/littles-law-stats', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        layer,
        COUNT(*) FILTER (WHERE arrived_at > NOW() - INTERVAL '10 seconds') AS requests_last_10s,
        ROUND(AVG(latency_ms) FILTER (WHERE arrived_at > NOW() - INTERVAL '30 seconds')::numeric, 2) AS avg_latency_ms,
        ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms) FILTER (WHERE arrived_at > NOW() - INTERVAL '30 seconds')::numeric, 2) AS p99_latency_ms
      FROM requests
      WHERE arrived_at > NOW() - INTERVAL '60 seconds'
      GROUP BY layer
    `);
    
    const stats = result.rows.map(row => {
      const lambda = row.requests_last_10s / 10; // RPS
      const w_mean = (row.avg_latency_ms || 0) / 1000; // seconds
      const w_p99 = (row.p99_latency_ms || 0) / 1000;
      const L_mean = lambda * w_mean;
      const L_p99 = lambda * w_p99;
      return {
        layer: row.layer,
        lambda_rps: parseFloat(lambda.toFixed(2)),
        w_mean_ms: parseFloat(row.avg_latency_ms || 0),
        w_p99_ms: parseFloat(row.p99_latency_ms || 0),
        L_mean: parseFloat(L_mean.toFixed(2)),
        L_p99: parseFloat(L_p99.toFixed(2)),
        recommended_pool_size: Math.ceil(L_p99 * 3)  // 3× safety buffer
      };
    });

    res.json({
      formula: 'L = λ × W',
      note: 'Use p99 latency for pool sizing, not mean',
      current_concurrent_gateway: concurrentRequests,
      gateway_limit: CONCURRENCY_LIMIT,
      layers: stats
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => console.log(`[Gateway] Listening on :${PORT} | Concurrency limit: ${CONCURRENCY_LIMIT}`));
EOF

cat > "$DEMO_DIR/api-gateway/Dockerfile" << 'EOF'
FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# =============================================================================
# 4. APP SERVER SERVICE (with injectable latency)
# =============================================================================
cat > "$DEMO_DIR/app-server/package.json" << 'EOF'
{
  "name": "app-server",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.19.2",
    "pg": "^8.12.0"
  }
}
EOF

cat > "$DEMO_DIR/app-server/server.js" << 'EOF'
import express from 'express';
import pg from 'pg';

const app = express();
app.use(express.json());

// CORS: allow dashboard (and other origins) to call app-server from the browser
app.use((req, res, next) => {
  const origin = req.headers.origin;
  res.setHeader('Access-Control-Allow-Origin', origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

const PORT = 3002;

// Simulated latency — can be adjusted via API to demonstrate Little's Law effect
let injectedLatencyMs = parseInt(process.env.BASE_LATENCY_MS || '80');
let concurrentRequests = 0;
const CONCURRENCY_LIMIT = parseInt(process.env.CONCURRENCY_LIMIT || '30');

const pool = new pg.Pool({
  host: process.env.PGHOST || 'postgres',
  database: process.env.PGDATABASE || 'littleslaw',
  user: process.env.PGUSER || 'demo',
  password: process.env.PGPASSWORD || 'demo',
  max: parseInt(process.env.DB_POOL_SIZE || '5')  // demonstrating Little's Law sizing
});

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

app.get('/health', (req, res) => res.json({ status: 'ok', layer: 'app-server', injected_latency_ms: injectedLatencyMs }));

// Control endpoint: adjust latency to observe L changing
app.post('/api/set-latency', (req, res) => {
  const { latency_ms } = req.body;
  const prev = injectedLatencyMs;
  injectedLatencyMs = parseInt(latency_ms) || 80;
  const lambda = 10; // assume 10 RPS for illustration
  const w = injectedLatencyMs / 1000;
  const L = lambda * w;
  res.json({
    message: `Latency updated: ${prev}ms → ${injectedLatencyMs}ms`,
    littles_law_prediction: {
      lambda_rps: lambda,
      W_ms: injectedLatencyMs,
      L_concurrent: parseFloat(L.toFixed(2)),
      'note': 'L doubled because W doubled at same λ — this is why latency spikes saturate pools'
    }
  });
});

app.get('/api/current-state', (req, res) => {
  res.json({
    injected_latency_ms: injectedLatencyMs,
    concurrency_limit: CONCURRENCY_LIMIT,
    current_concurrent: concurrentRequests,
    db_pool_size: parseInt(process.env.DB_POOL_SIZE || '5'),
    utilization_pct: ((concurrentRequests / CONCURRENCY_LIMIT) * 100).toFixed(1)
  });
});

app.get('/api/work', async (req, res) => {
  const startTime = Date.now();

  if (concurrentRequests >= CONCURRENCY_LIMIT) {
    return res.status(429).json({
      error: 'App server concurrency limit exceeded',
      current_L: concurrentRequests,
      limit: CONCURRENCY_LIMIT
    });
  }

  concurrentRequests++;

  try {
    // Simulate variable processing time (base + jitter)
    const jitter = Math.floor(Math.random() * 20);
    await sleep(injectedLatencyMs + jitter);

    // DB query — using Little's Law sized pool
    const dbStart = Date.now();
    const result = await pool.query(`
      SELECT COUNT(*) as total,
             ROUND(AVG(latency_ms)::numeric, 2) as avg_ms,
             MAX(latency_ms) as max_ms
      FROM requests
      WHERE arrived_at > NOW() - INTERVAL '60 seconds'
    `);
    const dbLatency = Date.now() - dbStart;

    const totalLatency = Date.now() - startTime;

    await pool.query(
      'INSERT INTO requests(layer, latency_ms) VALUES($1, $2)',
      ['app-server', totalLatency]
    );

    res.json({
      layer: 'app-server',
      status: 'ok',
      latency_ms: totalLatency,
      processing_ms: injectedLatencyMs + jitter,
      db_latency_ms: dbLatency,
      concurrent_at_peak: concurrentRequests,
      concurrency_limit: CONCURRENCY_LIMIT,
      db_stats: result.rows[0],
      littles_law: {
        note: `At 10 RPS with ${injectedLatencyMs}ms latency: L = ${(10 * injectedLatencyMs / 1000).toFixed(1)} concurrent`
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  } finally {
    concurrentRequests--;
  }
});

app.listen(PORT, () => console.log(`[App Server] Listening on :${PORT} | Base latency: ${injectedLatencyMs}ms | Pool: ${CONCURRENCY_LIMIT}`));
EOF

cat > "$DEMO_DIR/app-server/Dockerfile" << 'EOF'
FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
EXPOSE 3002
CMD ["node", "server.js"]
EOF

# =============================================================================
# 5. LOAD GENERATOR
# =============================================================================
cat > "$DEMO_DIR/load-generator/package.json" << 'EOF'
{
  "name": "load-generator",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "node-fetch": "^3.3.2"
  }
}
EOF

cat > "$DEMO_DIR/load-generator/generator.js" << 'EOF'
import fetch from 'node-fetch';

const GATEWAY_URL = process.env.GATEWAY_URL || 'http://api-gateway:3001';
const TARGET_RPS = parseInt(process.env.TARGET_RPS || '10');
const DURATION_SEC = parseInt(process.env.DURATION_SEC || '60');

const stats = { total: 0, success: 0, errors: 0, throttled: 0, latencies: [] };
let running = true;

// Stop after DURATION_SEC
setTimeout(() => { running = false; }, DURATION_SEC * 1000);

// Print summary every 5 seconds
const summaryInterval = setInterval(() => {
  const avg = stats.latencies.length > 0
    ? (stats.latencies.reduce((a, b) => a + b, 0) / stats.latencies.length).toFixed(1)
    : 0;
  const p99 = stats.latencies.length > 0
    ? stats.latencies.sort((a,b) => a-b)[Math.floor(stats.latencies.length * 0.99)]
    : 0;
  const lambda = stats.total / (Date.now() / 1000 - startTime);
  const L = lambda * (avg / 1000);  // Little's Law
  
  console.log(`\n[Load Gen] ── Little's Law Live ──`);
  console.log(`  λ (measured RPS):  ${lambda.toFixed(2)}`);
  console.log(`  W (avg latency):   ${avg}ms`);
  console.log(`  L (computed):      ${L.toFixed(2)} concurrent  [= λ × W]`);
  console.log(`  p99 latency:       ${p99}ms`);
  console.log(`  Throttled (429):   ${stats.throttled}`);
  console.log(`  Errors:            ${stats.errors}`);
}, 5000);

const startTime = Date.now() / 1000;
const intervalMs = 1000 / TARGET_RPS;

async function sendRequest() {
  const t = Date.now();
  try {
    const res = await fetch(`${GATEWAY_URL}/api/process`, {
      signal: AbortSignal.timeout(3000)
    });
    const latency = Date.now() - t;
    stats.total++;
    if (res.status === 429) {
      stats.throttled++;
    } else if (res.ok) {
      stats.success++;
      stats.latencies.push(latency);
    } else {
      stats.errors++;
    }
  } catch (e) {
    stats.errors++;
    stats.total++;
  }
}

console.log(`[Load Gen] Starting: ${TARGET_RPS} RPS for ${DURATION_SEC}s → ${GATEWAY_URL}`);
console.log(`[Load Gen] Expected L at baseline = ${TARGET_RPS} × (W/1000) concurrent`);

// Generate load at target RPS
const genLoop = async () => {
  while (running) {
    const loopStart = Date.now();
    sendRequest();  // fire and don't await — true async concurrency
    const elapsed = Date.now() - loopStart;
    const wait = Math.max(0, intervalMs - elapsed);
    await new Promise(r => setTimeout(r, wait));
  }
  clearInterval(summaryInterval);
  const totalSec = (Date.now() / 1000) - startTime;
  const finalLambda = stats.total / totalSec;
  const finalW = stats.latencies.length > 0
    ? stats.latencies.reduce((a,b) => a+b,0) / stats.latencies.length / 1000
    : 0;
  console.log(`\n[Load Gen] ═══ FINAL SUMMARY ═══`);
  console.log(`  Total requests: ${stats.total}`);
  console.log(`  Measured λ:     ${finalLambda.toFixed(2)} RPS`);
  console.log(`  Measured W:     ${(finalW * 1000).toFixed(1)}ms`);
  console.log(`  Computed L:     ${(finalLambda * finalW).toFixed(2)} concurrent`);
  console.log(`  Throttled:      ${stats.throttled}`);
  console.log(`  Success rate:   ${((stats.success/stats.total)*100).toFixed(1)}%`);
  process.exit(0);
};

genLoop();
EOF

cat > "$DEMO_DIR/load-generator/Dockerfile" << 'EOF'
FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY generator.js .
CMD ["node", "generator.js"]
EOF

# =============================================================================
# 6. DASHBOARD (React + real-time WebSocket)
# =============================================================================
cat > "$DEMO_DIR/dashboard/package.json" << 'EOF'
{
  "name": "capacity-dashboard",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "vite build"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.12.7",
    "express": "^4.19.2",
    "ws": "^8.18.0",
    "node-fetch": "^3.3.2",
    "vite": "^5.4.2",
    "@vitejs/plugin-react": "^4.3.1"
  }
}
EOF

cat > "$DEMO_DIR/dashboard/vite.config.js" << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { '/api': 'http://api-gateway:3001' } }
});
EOF

cat > "$DEMO_DIR/dashboard/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Little's Law Dashboard</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

mkdir -p "$DEMO_DIR/dashboard/src"
cat > "$DEMO_DIR/dashboard/src/main.jsx" << 'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
createRoot(document.getElementById('root')).render(<App/>);
EOF

cat > "$DEMO_DIR/dashboard/src/App.jsx" << 'APPEOF'
import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, ReferenceLine, AreaChart, Area
} from 'recharts';

const GATEWAY = import.meta.env.VITE_GATEWAY_URL || '/api';
const APP_SERVER = import.meta.env.VITE_APP_URL || 'http://localhost:3002';

export default function App() {
  const [stats, setStats] = useState(null);
  const [history, setHistory] = useState([]);
  const [latencyMs, setLatencyMs] = useState(80);
  const [pendingLatency, setPendingLatency] = useState(80);
  const [appState, setAppState] = useState(null);
  const [error, setError] = useState(null);
  const [loadActive, setLoadActive] = useState(false);
  const loadRef = useRef(null);
  const requestCounter = useRef(0);

  const fetchStats = useCallback(async () => {
    try {
      const [statsRes, stateRes] = await Promise.all([
        fetch(`${GATEWAY}/littles-law-stats`),
        fetch(`${APP_SERVER}/api/current-state`)
      ]);
      if (statsRes.ok) {
        const data = await statsRes.json();
        setStats(data);
        setHistory(prev => {
          const layerObj = (data.layers || []).map(l => [
            `${l.layer}_lambda`, l.lambda_rps,
            `${l.layer}_L_mean`, l.L_mean,
            `${l.layer}_L_p99`, l.L_p99,
          ]).flat().reduce((acc, _, i, arr) => {
            if (i % 2 === 0) acc[arr[i]] = arr[i + 1];
            return acc;
          }, {});
          const entry = {
            time: new Date().toLocaleTimeString(),
            gateway_L: data.current_concurrent_gateway,
            ...layerObj,
          };
          return [...prev.slice(-40), entry];
        });
      }
      if (stateRes.ok) setAppState(await stateRes.json());
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    fetchStats();
    const interval = setInterval(fetchStats, 1500);
    return () => clearInterval(interval);
  }, [fetchStats]);

  const applyLatency = async () => {
    try {
      await fetch(`${APP_SERVER}/api/set-latency`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ latency_ms: pendingLatency })
      });
      setLatencyMs(pendingLatency);
    } catch(e) { setError(e.message); }
  };

  const fireRequest = useCallback(async () => {
    requestCounter.current++;
    try { await fetch(`${GATEWAY}/process`); } catch(_) {}
  }, []);

  const startLoad = () => {
    if (loadRef.current) return;
    setLoadActive(true);
    loadRef.current = setInterval(() => {
      for (let i = 0; i < 8; i++) setTimeout(fireRequest, i * 120);
    }, 1000);
  };
  const stopLoad = () => {
    clearInterval(loadRef.current);
    loadRef.current = null;
    setLoadActive(false);
  };

  const gatewayLimit = stats?.gateway_limit || 50;
  const currentL = stats?.current_concurrent_gateway || 0;
  const utilPct = ((currentL / gatewayLimit) * 100).toFixed(1);
  const utilColor = utilPct < 60 ? '#22c55e' : utilPct < 80 ? '#f59e0b' : '#ef4444';

  const predictedL = appState
    ? ((8 * pendingLatency) / 1000).toFixed(2)
    : '—';

  return (
    <div style={{
      minHeight: '100vh', background: 'linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%)',
      fontFamily: 'system-ui, -apple-system, sans-serif', padding: '24px'
    }}>
      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: 32 }}>
        <h1 style={{ fontSize: 28, fontWeight: 800, color: '#1e3a8a', margin: 0 }}>
          Little's Law Live Dashboard
        </h1>
        <div style={{
          display: 'inline-block', marginTop: 8, padding: '6px 20px',
          background: '#1d4ed8', color: 'white', borderRadius: 20, fontSize: 15, fontWeight: 700
        }}>L = λ × W</div>
        <p style={{ color: '#64748b', marginTop: 6, fontSize: 13 }}>
          Concurrency = Rate × Latency — applied per service layer
        </p>
        {error && (
          <div style={{ background: '#fef2f2', border: '1px solid #fca5a5', padding: '8px 16px', borderRadius: 8, marginTop: 8, color: '#dc2626', fontSize: 12 }}>
            ⚠ {error} — waiting for services...
          </div>
        )}
      </div>

      {/* Top metrics row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
        {[
          { label: 'Current L (Gateway)', value: currentL, sub: `of ${gatewayLimit} limit`, color: utilColor },
          { label: 'Utilization', value: `${utilPct}%`, sub: utilPct < 70 ? '✓ Safe' : utilPct < 85 ? '⚠ Caution' : '✗ Danger', color: utilColor },
          { label: 'Injected W', value: `${latencyMs}ms`, sub: 'App server latency', color: '#3b82f6' },
          { label: 'Predicted L', value: predictedL, sub: 'at 8 RPS (Little\'s Law)', color: '#1d4ed8' },
        ].map((m, i) => (
          <div key={i} style={{
            background: 'white', borderRadius: 16, padding: '20px 16px',
            boxShadow: '0 4px 12px rgba(59,130,246,0.15)', textAlign: 'center'
          }}>
            <div style={{ fontSize: 12, color: '#64748b', marginBottom: 8 }}>{m.label}</div>
            <div style={{ fontSize: 36, fontWeight: 800, color: m.color }}>{m.value}</div>
            <div style={{ fontSize: 11, color: m.color, marginTop: 4 }}>{m.sub}</div>
          </div>
        ))}
      </div>

      {/* Charts row */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 24 }}>
        {/* L over time */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Concurrent Requests (L) Over Time</h3>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={history}>
              <defs>
                <linearGradient id="lgL" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9"/>
              <XAxis dataKey="time" tick={{ fontSize: 9 }} interval="preserveStartEnd"/>
              <YAxis tick={{ fontSize: 10 }}/>
              <Tooltip/>
              <ReferenceLine y={gatewayLimit} stroke="#ef4444" strokeDasharray="4" label={{ value: 'Limit', position: 'right', fontSize: 10 }}/>
              <ReferenceLine y={gatewayLimit * 0.7} stroke="#f59e0b" strokeDasharray="4" label={{ value: '70%', position: 'right', fontSize: 9 }}/>
              <Area type="monotone" dataKey="gateway_L" stroke="#3b82f6" fill="url(#lgL)" name="L (gateway)" strokeWidth={2}/>
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Per-layer bar chart */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Per-Layer L (mean vs p99 latency)</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={stats?.layers || []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9"/>
              <XAxis dataKey="layer" tick={{ fontSize: 11 }}/>
              <YAxis tick={{ fontSize: 10 }}/>
              <Tooltip formatter={(v, n) => [v, n]}/>
              <Legend/>
              <Bar dataKey="L_mean" name="L (mean W)" fill="#60a5fa" radius={[4,4,0,0]}/>
              <Bar dataKey="L_p99" name="L (p99 W)" fill="#1d4ed8" radius={[4,4,0,0]}/>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Layer details table */}
      <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)', marginBottom: 24 }}>
        <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Little's Law Per Layer — Live Computation</h3>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
          <thead>
            <tr style={{ background: '#eff6ff' }}>
              {['Layer', 'λ (RPS)', 'W mean (ms)', 'W p99 (ms)', 'L (mean)', 'L (p99)', 'Rec. Pool Size (3×p99)'].map(h => (
                <th key={h} style={{ padding: '8px 12px', textAlign: 'left', color: '#1e40af', fontWeight: 600 }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {(stats?.layers || []).map((l, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #f1f5f9' }}>
                <td style={{ padding: '8px 12px', fontWeight: 600, color: '#1e3a8a' }}>{l.layer}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.lambda_rps}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.w_mean_ms}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.w_p99_ms}</td>
                <td style={{ padding: '8px 12px', color: '#3b82f6', fontWeight: 600 }}>{l.L_mean}</td>
                <td style={{ padding: '8px 12px', color: '#1d4ed8', fontWeight: 700 }}>{l.L_p99}</td>
                <td style={{ padding: '8px 12px', color: '#059669', fontWeight: 600 }}>{l.recommended_pool_size}</td>
              </tr>
            ))}
            {(!stats?.layers || stats.layers.length === 0) && (
              <tr><td colSpan={7} style={{ padding: '16px', textAlign: 'center', color: '#94a3b8' }}>
                Generate load to see real measurements
              </td></tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Controls */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {/* Latency injection */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>
            🔬 Inject Latency — Watch L Change at Constant λ
          </h3>
          <p style={{ fontSize: 12, color: '#64748b', margin: '0 0 12px' }}>
            Increase W → L increases proportionally. This is the failure mode that saturates thread pools without traffic growth.
          </p>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <input
              type="range" min="20" max="500" value={pendingLatency}
              onChange={e => setPendingLatency(parseInt(e.target.value))}
              style={{ flex: 1 }}
            />
            <span style={{ width: 60, textAlign: 'center', fontWeight: 700, color: '#1d4ed8' }}>{pendingLatency}ms</span>
            <button onClick={applyLatency} style={{
              background: '#1d4ed8', color: 'white', border: 'none', borderRadius: 8,
              padding: '8px 16px', cursor: 'pointer', fontWeight: 600, fontSize: 13
            }}>Apply</button>
          </div>
          <div style={{ marginTop: 12, padding: '10px 14px', background: '#eff6ff', borderRadius: 8, fontSize: 12 }}>
            <strong>Little's Law prediction at 8 RPS:</strong><br/>
            L = 8 × {pendingLatency}/1000 = <strong style={{ color: '#1d4ed8' }}>{(8 * pendingLatency / 1000).toFixed(2)} concurrent</strong>
            {pendingLatency > 200 && (
              <span style={{ color: '#dc2626', marginLeft: 8 }}>⚠ Pool saturation risk</span>
            )}
          </div>
        </div>

        {/* Load control */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>
            ⚡ Load Generator Controls
          </h3>
          <p style={{ fontSize: 12, color: '#64748b', margin: '0 0 16px' }}>
            Generate ~8 RPS from the browser to observe Little's Law measurements update in real time.
          </p>
          <div style={{ display: 'flex', gap: 12 }}>
            <button onClick={startLoad} disabled={loadActive} style={{
              flex: 1, background: loadActive ? '#94a3b8' : '#22c55e', color: 'white',
              border: 'none', borderRadius: 8, padding: '12px', cursor: loadActive ? 'default' : 'pointer',
              fontWeight: 700, fontSize: 14
            }}>▶ Start Load</button>
            <button onClick={stopLoad} disabled={!loadActive} style={{
              flex: 1, background: !loadActive ? '#94a3b8' : '#ef4444', color: 'white',
              border: 'none', borderRadius: 8, padding: '12px', cursor: !loadActive ? 'default' : 'pointer',
              fontWeight: 700, fontSize: 14
            }}>■ Stop Load</button>
          </div>
          <div style={{ marginTop: 12, padding: '10px', background: '#f8fafc', borderRadius: 8, fontSize: 11, color: '#64748b' }}>
            App server concurrency limit: {appState?.concurrency_limit || 30} |
            DB pool size: {appState?.db_pool_size || 5} |
            Current W: {appState?.injected_latency_ms || 80}ms
          </div>
        </div>
      </div>

      <div style={{ textAlign: 'center', marginTop: 24, fontSize: 11, color: '#94a3b8' }}>
        Article 201 · System Design Interview Roadmap · Section 8: Production Engineering
      </div>
    </div>
  );
}
APPEOF

cat > "$DEMO_DIR/dashboard/Dockerfile" << 'EOF'
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
ENV VITE_GATEWAY_URL=/api
ENV VITE_APP_URL=http://localhost:3002
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
EOF

cat > "$DEMO_DIR/dashboard/nginx.conf" << 'EOF'
server {
  listen 80;
  root /usr/share/nginx/html;
  index index.html;

  location /api/ {
    proxy_pass http://api-gateway:3001/api/;
    proxy_set_header Host $host;
  }

  location / {
    try_files $uri $uri/ /index.html;
  }
}
EOF

# =============================================================================
# 7. DOCKER COMPOSE
# =============================================================================
cat > "$COMPOSE_FILE" << 'EOF'
# Docker Compose (no version - attribute obsolete in Compose v2)

networks:
  littles-law-net:
    driver: bridge

volumes:
  pgdata:

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: littleslaw
      POSTGRES_USER: demo
      POSTGRES_PASSWORD: demo
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d
    networks: [littles-law-net]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U demo -d littleslaw"]
      interval: 5s
      timeout: 3s
      retries: 10

  app-server:
    build: ./app-server
    ports:
      - "3002:3002"
    environment:
      PGHOST: postgres
      PGDATABASE: littleslaw
      PGUSER: demo
      PGPASSWORD: demo
      BASE_LATENCY_MS: "80"
      CONCURRENCY_LIMIT: "30"
      DB_POOL_SIZE: "5"
    networks: [littles-law-net]
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3002/health || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 10

  api-gateway:
    build: ./api-gateway
    ports:
      - "3001:3001"
    environment:
      PGHOST: postgres
      PGDATABASE: littleslaw
      PGUSER: demo
      PGPASSWORD: demo
      APP_SERVER_URL: http://app-server:3002
      CONCURRENCY_LIMIT: "50"
    networks: [littles-law-net]
    depends_on:
      app-server:
        condition: service_healthy

  load-generator:
    build: ./load-generator
    environment:
      GATEWAY_URL: http://api-gateway:3001
      TARGET_RPS: "10"
      DURATION_SEC: "120"
    networks: [littles-law-net]
    depends_on:
      - api-gateway
    profiles: [load]

  dashboard:
    build: ./dashboard
    ports:
      - "8080:80"
    networks: [littles-law-net]
    depends_on:
      - api-gateway
      - app-server
EOF

# =============================================================================
# 8. DEMO AND CLEANUP SCRIPTS
# =============================================================================
cat > "$DEMO_DIR/demo.sh" << 'EOF'
#!/bin/bash
echo "🚀 Starting Little's Law Load Generator (10 RPS for 120s)..."
cd "$(dirname "$0")"
docker compose --profile load up load-generator --no-deps
EOF
chmod +x "$DEMO_DIR/demo.sh"

cat > "$DEMO_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
echo "🧹 Cleaning up Little's Law demo..."
cd "$(dirname "$0")"
docker compose --profile load down -v --remove-orphans
docker rmi littles-law-demo-api-gateway littles-law-demo-app-server littles-law-demo-load-generator littles-law-demo-dashboard 2>/dev/null || true
echo "✅ Cleanup complete."
EOF
chmod +x "$DEMO_DIR/cleanup.sh"

# Test script: run validation checks (use full path or run from DEMO_DIR)
cat > "$DEMO_DIR/test.sh" << 'EOF'
#!/bin/bash
set -e
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DEMO_DIR"
echo "🧪 Little's Law Demo — Validation Tests"
echo ""

# Ensure services are up
if ! curl -sf http://localhost:3001/health >/dev/null 2>&1; then
  echo "❌ API Gateway not responding. Start with: docker compose up -d"
  exit 1
fi

PASS=0
FAIL=0

# 1. Gateway health
if curl -sf http://localhost:3001/health | grep -q '"status":"ok"'; then
  echo "  ✅ Gateway health"
  PASS=$((PASS+1))
else
  echo "  ❌ Gateway health"
  FAIL=$((FAIL+1))
fi

# 2. Request pipeline (L field)
if curl -sf http://localhost:3001/api/process | grep -q '"current_L"'; then
  echo "  ✅ Request pipeline (L field present)"
  PASS=$((PASS+1))
else
  echo "  ❌ Request pipeline"
  FAIL=$((FAIL+1))
fi

# 3. Little's Law stats endpoint
if curl -sf http://localhost:3001/api/littles-law-stats | grep -q '"formula"'; then
  echo "  ✅ Little's Law stats endpoint"
  PASS=$((PASS+1))
else
  echo "  ❌ Stats endpoint"
  FAIL=$((FAIL+1))
fi

# 4. App server (for dashboard Predicted L / latency control)
if curl -sf http://localhost:3002/api/current-state >/dev/null 2>&1; then
  echo "  ✅ App server current-state"
  PASS=$((PASS+1))
else
  echo "  ❌ App server (port 3002)"
  FAIL=$((FAIL+1))
fi

# 5. Dashboard
if curl -sf http://localhost:8080/ | grep -qE 'html|DOCTYPE'; then
  echo "  ✅ Dashboard serving"
  PASS=$((PASS+1))
else
  echo "  ❌ Dashboard (port 8080)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
EOF
chmod +x "$DEMO_DIR/test.sh"

# =============================================================================
# 9. BUILD AND START
# =============================================================================
echo ""
echo "🔨 Building Docker images..."
cd "$DEMO_DIR"
docker compose build --quiet

echo ""
echo "🚀 Starting services..."
docker compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
MAX_WAIT=90
WAITED=0
while true; do
  HEALTHY=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
total = len([l for l in lines if l.strip()])
healthy = sum(1 for l in lines if l.strip() and 'healthy' in json.loads(l).get('Health',''))
print(f'{healthy}/{total}')
" 2>/dev/null || echo "0/0")
  echo "  Services healthy: $HEALTHY"
  if [[ "$HEALTHY" == "3/3" ]]; then
    echo "  ✅ All services ready!"
    break
  fi
  WAITED=$((WAITED + 5))
  if [ $WAITED -ge $MAX_WAIT ]; then
    echo "  ⚠ Timeout waiting. Services may still be starting..."
    break
  fi
  sleep 5
done

# =============================================================================
# 10. QUICK VALIDATION TEST
# =============================================================================
echo ""
echo "🧪 Running validation tests..."
sleep 3

# Test 1: Gateway health
GATEWAY_HEALTH=$(curl -sf http://localhost:3001/health 2>/dev/null)
if echo "$GATEWAY_HEALTH" | grep -q '"status":"ok"'; then
  echo "  ✅ API Gateway: healthy"
else
  echo "  ⚠  API Gateway: not yet responding"
fi

# Test 2: Send a test request and verify Little's Law response fields
TEST_RESP=$(curl -sf http://localhost:3001/api/process 2>/dev/null)
if echo "$TEST_RESP" | grep -q '"current_L"'; then
  echo "  ✅ Request pipeline: working (L field present)"
else
  echo "  ⚠  Request pipeline: still warming up"
fi

# Test 3: Stats endpoint
STATS=$(curl -sf http://localhost:3001/api/littles-law-stats 2>/dev/null)
if echo "$STATS" | grep -q '"formula"'; then
  echo "  ✅ Little's Law stats endpoint: working"
else
  echo "  ⚠  Stats endpoint: still warming up"
fi

# Test 4: Dashboard
DASH=$(curl -sf http://localhost:8080/ 2>/dev/null | head -c 100)
if echo "$DASH" | grep -q 'html\|DOCTYPE'; then
  echo "  ✅ Dashboard: serving"
else
  echo "  ⚠  Dashboard: still building"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  🎯 Little's Law Capacity Planning Demo — READY"
echo ""
echo "  📊 Dashboard:      http://localhost:8080"
echo "  🔌 API Gateway:    http://localhost:3001"
echo ""
echo "  Quick experiments:"
echo "  1. Open dashboard → click 'Start Load' → watch L = λW update live"
echo "  2. Drag latency slider to 300ms → L triples without traffic change"
echo "  3. Set latency to 400ms → watch 429 throttle errors appear"
echo ""
echo "  Run load generator (terminal output):"
echo "    cd \"$DEMO_DIR\" && bash demo.sh"
echo "  Or with full path:"
echo "    bash \"$DEMO_DIR/demo.sh\""
echo ""
echo "  Try the API directly:"
echo "    curl http://localhost:3001/api/process"
echo "    curl http://localhost:3001/api/littles-law-stats"
echo "    curl -X POST http://localhost:3002/api/set-latency \\"
echo "         -H 'Content-Type: application/json' \\"
echo "         -d '{\"latency_ms\": 250}'"
echo ""
echo "  Run validation tests:"
echo "    bash \"$DEMO_DIR/test.sh\""
echo ""
echo "  Cleanup:"
echo "    cd \"$DEMO_DIR\" && bash cleanup.sh"
echo "  Or: bash \"$DEMO_DIR/cleanup.sh\""
echo "════════════════════════════════════════════════════════════════"