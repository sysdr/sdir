/**
 * Load Generator
 * Sends requests at configurable RPS, recording per-request latency
 * Exposes metrics over HTTP for the dashboard to consume
 */
const http    = require('http');
const axios   = require('axios');

const TARGET_HOST = process.env.TARGET_HOST || 'envoy-sidecar-a';
const TARGET_PORT = process.env.TARGET_PORT || 8081;
const RPS         = parseInt(process.env.RPS || '10');
const BASE_URL    = `http://${TARGET_HOST}:${TARGET_PORT}`;

const stats = {
  total: 0, errors: 0,
  latencies: [],          // rolling window of last 1000
  p50: 0, p95: 0, p99: 0,
  minMs: Infinity, maxMs: 0, avgMs: 0,
  started: Date.now()
};

function percentile(sorted, p) {
  if (!sorted.length) return 0;
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function recalc() {
  if (!stats.latencies.length) return;
  const sorted = [...stats.latencies].sort((a, b) => a - b);
  stats.p50 = percentile(sorted, 50);
  stats.p95 = percentile(sorted, 95);
  stats.p99 = percentile(sorted, 99);
  stats.avgMs = sorted.reduce((a, b) => a + b, 0) / sorted.length;
}

async function sendRequest() {
  const start = Date.now();
  try {
    // Alternate between direct and chain calls
    const path = stats.total % 3 === 0 ? '/api/chain' : '/api/data';
    await axios.get(`${BASE_URL}${path}`, { timeout: 10000 });
    const ms = Date.now() - start;
    stats.latencies.push(ms);
    if (stats.latencies.length > 1000) stats.latencies.shift();
    stats.minMs = Math.min(stats.minMs, Math.max(0, ms));
    stats.maxMs = Math.max(stats.maxMs, ms);
    stats.total++;
    if (stats.total % 10 === 0) recalc();
  } catch (err) {
    stats.errors++;
    stats.total++;
  }
}

// Generate load at configured RPS
const intervalMs = 1000 / RPS;
setInterval(sendRequest, intervalMs);

// Metrics server for dashboard
const server = http.createServer((req, res) => {
  if (req.url === '/metrics') {
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Access-Control-Allow-Origin', '*');
    const safeMin = (stats.minMs === Infinity || stats.minMs < 0) ? 0 : stats.minMs;
    res.end(JSON.stringify({
      ...stats,
      minMs: safeMin,
      uptimeSeconds: Math.floor((Date.now() - stats.started) / 1000),
      successRate: stats.total > 0 ? ((stats.total - stats.errors) / stats.total * 100).toFixed(1) : 100,
      rps: RPS
    }));
  } else if (req.url === '/health') {
    res.end('ok');
  } else {
    res.writeHead(404); res.end();
  }
});

server.listen(4000, () => console.log(`[load-gen] running at ${RPS} RPS, metrics on :4000`));
