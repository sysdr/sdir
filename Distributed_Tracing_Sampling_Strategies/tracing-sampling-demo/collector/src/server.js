const express    = require('express');
const { WebSocketServer } = require('ws');
const cors       = require('cors');
const http       = require('http');
const path       = require('path');
const { HeadProbabilistic, HeadRateLimited, TailBased, Adaptive } = require('./strategies');

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocketServer({ server });

app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(__dirname, '../public')));

// ── State ────────────────────────────────────────────────────
const stats = {
  strategy:     'tail_based',
  received:     0,
  kept:         0,
  dropped:      0,
  errors_seen:  0,
  errors_kept:  0,
  slow_kept:    0,
  bytesKept:    0,
  bytesDropped: 0,
  rateWindow:   [],   // timestamps of kept traces
  recentTraces: [],   // last 40 sampling decisions
};

const STRATEGIES = {
  head_probabilistic: new HeadProbabilistic(0.10),
  head_rate_limited:  new HeadRateLimited(12),
  tail_based:         new TailBased({ latencyThresh: 400 }),
  adaptive:           new Adaptive({ targetPerSec: 15 }),
};

function currentStrategy() { return STRATEGIES[stats.strategy]; }

function estimateTraceBytes(trace) {
  return JSON.stringify(trace).length;
}

function computeRatePerSec() {
  const now    = Date.now();
  const window = 5000; // 5 second sliding window
  stats.rateWindow = stats.rateWindow.filter(t => now - t < window);
  return (stats.rateWindow.length / (window / 1000)).toFixed(1);
}

// ── Trace Ingestion Endpoint ─────────────────────────────────
app.post('/trace', (req, res) => {
  const trace  = req.body;
  const bytes  = estimateTraceBytes(trace);
  const result = currentStrategy().decide(trace);

  stats.received++;
  if (trace.hasError) stats.errors_seen++;

  if (result.keep) {
    stats.kept++;
    stats.bytesKept += bytes;
    stats.rateWindow.push(Date.now());
    if (trace.hasError)           stats.errors_kept++;
    if (trace.totalDuration > 400) stats.slow_kept++;
  } else {
    stats.dropped++;
    stats.bytesDropped += bytes;
  }

  // Track recent decisions (ring buffer, 40 items)
  stats.recentTraces.unshift({
    traceId:  trace.traceId.slice(0, 12),
    type:     trace.type,
    duration: trace.totalDuration,
    spans:    trace.spanCount,
    hasError: trace.hasError,
    keep:     result.keep,
    reason:   result.reason,
    ts:       Date.now(),
  });
  if (stats.recentTraces.length > 40) stats.recentTraces.pop();

  broadcast();
  res.json({ sampled: result.keep, reason: result.reason });
});

// ── Strategy Switch ──────────────────────────────────────────
app.post('/strategy', (req, res) => {
  const { strategy } = req.body;
  if (!STRATEGIES[strategy]) return res.status(400).json({ error: 'Unknown strategy' });
  stats.strategy = strategy;
  console.log(`[Collector] Strategy switched → ${strategy}`);
  broadcast();
  res.json({ ok: true, strategy });
});

// ── Health ───────────────────────────────────────────────────
app.get('/health', (req, res) => res.json({ status: 'ok', strategy: stats.strategy }));

// ── Stats Snapshot ────────────────────────────────────────────
app.get('/stats', (req, res) => res.json(buildPayload()));

function buildPayload() {
  const total       = stats.kept + stats.dropped || 1;
  const keptRate    = ((stats.kept / total) * 100).toFixed(1);
  const savings     = ((stats.bytesDropped / (stats.bytesKept + stats.bytesDropped || 1)) * 100).toFixed(1);
  const keptPerSec  = computeRatePerSec();

  return {
    strategy:       stats.strategy,
    received:       stats.received,
    kept:           stats.kept,
    dropped:        stats.dropped,
    keptRatePct:    keptRate,
    storageSavePct: savings,
    keptPerSec,
    errorsKeptPct:  stats.errors_seen > 0
                      ? ((stats.errors_kept / stats.errors_seen) * 100).toFixed(0) : '—',
    bytesKeptMB:    (stats.bytesKept    / 1_048_576).toFixed(2),
    bytesDroppedMB: (stats.bytesDropped / 1_048_576).toFixed(2),
    recentTraces:   stats.recentTraces,
  };
}

// ── WebSocket Broadcast ──────────────────────────────────────
function broadcast() {
  const payload = JSON.stringify(buildPayload());
  wss.clients.forEach(client => {
    if (client.readyState === 1) client.send(payload);
  });
}

// Periodic broadcast even without new traces
setInterval(broadcast, 1000);

// ── Start ────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`[Collector] Listening on :${PORT} — default strategy: ${stats.strategy}`);
});
