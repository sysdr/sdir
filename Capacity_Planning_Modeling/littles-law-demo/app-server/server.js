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
