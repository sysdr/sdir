const express = require('express');
const http    = require('http');
const WebSocket = require('ws');
const axios   = require('axios');

const app = express();
const PORT = 5000;

const LOAD_GEN_URL   = `http://${process.env.LOAD_GEN_HOST || 'load-generator'}:4000/metrics`;
const ENVOY_A_ADMIN  = `http://${process.env.ENVOY_A_HOST  || 'envoy-sidecar-a'}:9901/stats?filter=downstream_cx_total`;
const ENVOY_B_ADMIN  = `http://${process.env.ENVOY_B_HOST  || 'envoy-sidecar-b'}:9902/stats?filter=downstream_cx_total`;

app.use(express.static(__dirname + '/public'));

const server = http.createServer(app);
const wss    = new WebSocket.Server({ server });

async function fetchMetrics() {
  const [loadMetrics, envoyAStats, envoyBStats] = await Promise.allSettled([
    axios.get(LOAD_GEN_URL,  { timeout: 3000 }),
    axios.get(ENVOY_A_ADMIN, { timeout: 3000 }),
    axios.get(ENVOY_B_ADMIN, { timeout: 3000 }),
  ]);

  const load    = loadMetrics.status  === 'fulfilled' ? loadMetrics.value.data  : {};
  const eaStats = envoyAStats.status  === 'fulfilled' ? envoyAStats.value.data  : {};
  const ebStats = envoyBStats.status  === 'fulfilled' ? envoyBStats.value.data  : {};

  // Parse Envoy stats: text format (name: value per line) or JSON format
  const parseEnvoyStats = (raw) => {
    if (typeof raw === 'string') {
      const out = {};
      raw.split('\n').forEach(line => {
        const idx = line.indexOf(': ');
        if (idx > 0) {
          const k = line.slice(0, idx).trim();
          const v = line.slice(idx + 2).trim();
          if (k && v !== undefined) out[k] = parseFloat(v) || 0;
        }
      });
      return out;
    }
    if (raw && typeof raw === 'object' && Array.isArray(raw.stats)) {
      const out = {};
      raw.stats.forEach(s => { if (s.name != null) out[s.name] = parseFloat(s.value) || 0; });
      return out;
    }
    return {};
  };

  const ea = parseEnvoyStats(eaStats);
  const eb = parseEnvoyStats(ebStats);

  return {
    timestamp: Date.now(),
    load: {
      p50:         load.p50   || 0,
      p95:         load.p95   || 0,
      p99:         load.p99   || 0,
      avg:         load.avgMs || 0,
      min:         (load.minMs != null && load.minMs !== Infinity && load.minMs >= 0) ? load.minMs : 0,
      max:         load.maxMs || 0,
      total:       load.total || 0,
      errors:      load.errors || 0,
      successRate: load.successRate || '100.0',
      rps:         load.rps   || 10,
      uptime:      load.uptimeSeconds || 0,
      recentLatencies: load.latencies ? load.latencies.slice(-60) : []
    },
    envoy: {
      a: { connections: ea['listener.0.0.0.0_8081.downstream_cx_total'] || 0 },
      b: { connections: eb['listener.0.0.0.0_8082.downstream_cx_total'] || 0 }
    }
  };
}

// Broadcast metrics to all WebSocket clients every second
setInterval(async () => {
  try {
    const data = await fetchMetrics();
    const msg  = JSON.stringify({ type: 'metrics', data });
    wss.clients.forEach(ws => { if (ws.readyState === WebSocket.OPEN) ws.send(msg); });
  } catch (e) { /* swallow */ }
}, 1000);

server.listen(PORT, () => console.log(`[dashboard] listening on :${PORT}`));
