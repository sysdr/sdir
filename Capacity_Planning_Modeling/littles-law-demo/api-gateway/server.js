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
