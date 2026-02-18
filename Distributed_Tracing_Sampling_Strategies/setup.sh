#!/bin/bash
# ============================================================
# Article 201 — Distributed Tracing Sampling Strategies
# System Design Interview Roadmap | Section 8
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
  echo -e "${BLUE}${BOLD}"
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │   Distributed Tracing Sampling Strategies Demo      │"
  echo "  │   Article 201 — Section 8: Production Engineering   │"
  echo "  └─────────────────────────────────────────────────────┘"
  echo -e "${NC}"
}

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
step()    { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }

banner

# ─── Prerequisites ──────────────────────────────────────────
step "Checking prerequisites"
command -v docker >/dev/null 2>&1 || error "Docker not installed"
command -v docker compose >/dev/null 2>&1 || \
  command -v docker-compose >/dev/null 2>&1 || error "Docker Compose not installed"

COMPOSE="docker compose"
command -v docker compose >/dev/null 2>&1 || COMPOSE="docker-compose"

success "Docker & Compose available"

# ─── Directory Structure ─────────────────────────────────────
step "Creating project structure"
BASE="./tracing-sampling-demo"
mkdir -p "$BASE"/{generator,collector/{src,public},tests}
cd "$BASE"
DEMO_ROOT="$(pwd)"

# ─── Generator Package ──────────────────────────────────────
cat > generator/package.json << 'EOF'
{
  "name": "trace-generator",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "axios": "^1.7.2",
    "uuid": "^10.0.0"
  }
}
EOF

# ─── Generator Source ───────────────────────────────────────
cat > generator/index.js << 'GENEOF'
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');

const COLLECTOR_URL = process.env.COLLECTOR_URL || 'http://collector:3000';
const TRACE_RATE    = parseInt(process.env.TRACE_RATE || '15'); // traces/sec

// Simulated microservice topology
const SERVICES = [
  { name: 'api-gateway',     color: '#1a73e8' },
  { name: 'auth-service',    color: '#0d47a1' },
  { name: 'order-service',   color: '#1565c0' },
  { name: 'payment-service', color: '#0277bd' },
];

const OPERATIONS = {
  'api-gateway':     ['GET /api/orders', 'POST /api/checkout', 'GET /api/user/profile', 'DELETE /api/cart'],
  'auth-service':    ['validateToken', 'refreshSession', 'checkPermissions'],
  'order-service':   ['createOrder', 'fetchOrderHistory', 'updateOrderStatus'],
  'payment-service': ['chargeCard', 'refundTransaction', 'validatePaymentMethod'],
};

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Build a realistic multi-hop trace tree
function generateTrace(type) {
  const traceId   = uuidv4().replace(/-/g, '');
  const startTime = Date.now();
  const spans     = [];

  // Determine profile based on type
  const profile = {
    normal: { latencyBase: 50,  latencyJitter: 40,  errorProb: 0.00, dbSlowProb: 0.05 },
    slow:   { latencyBase: 400, latencyJitter: 300, errorProb: 0.03, dbSlowProb: 0.60 },
    error:  { latencyBase: 80,  latencyJitter: 40,  errorProb: 0.90, dbSlowProb: 0.10 },
  }[type];

  // Root span (API Gateway)
  const rootSpanId = uuidv4().replace(/-/g, '').slice(0, 16);
  const rootOp = OPERATIONS['api-gateway'][randomInt(0, OPERATIONS['api-gateway'].length - 1)];

  let cursor = startTime;

  // Decide service chain (1–4 hops)
  const hopCount   = type === 'error' ? randomInt(2, 4) : randomInt(2, 4);
  const serviceChain = SERVICES.slice(0, hopCount);
  let parentSpanId = rootSpanId;
  let totalDuration = 0;

  serviceChain.forEach((svc, idx) => {
    const spanId   = idx === 0 ? rootSpanId : uuidv4().replace(/-/g, '').slice(0, 16);
    const ops      = OPERATIONS[svc.name];
    const op       = idx === 0 ? rootOp : ops[randomInt(0, ops.length - 1)];
    const isError  = Math.random() < profile.errorProb && idx === hopCount - 1;
    const isSlowDb = svc.name === 'order-service' && Math.random() < profile.dbSlowProb;

    const spanLatency = isSlowDb
      ? randomInt(800, 2000)
      : randomInt(profile.latencyBase, profile.latencyBase + profile.latencyJitter);

    spans.push({
      traceId,
      spanId,
      parentSpanId: idx === 0 ? null : parentSpanId,
      service:      svc.name,
      operation:    op,
      startTime:    cursor,
      duration:     spanLatency,
      status:       isError ? 'ERROR' : 'OK',
      statusCode:   isError ? (Math.random() < 0.5 ? 500 : 503) : 200,
      tags: {
        'span.kind':   idx === 0 ? 'server' : 'client',
        'db.slow':     isSlowDb ? 'true' : 'false',
        'http.status': isError ? String(Math.random() < 0.5 ? 500 : 503) : '200',
        ...(isSlowDb ? { 'db.statement': 'SELECT * FROM orders WHERE user_id = ?', 'db.duration_ms': String(spanLatency) } : {}),
      },
    });

    cursor += spanLatency;
    totalDuration += spanLatency;
    parentSpanId = spanId;
  });

  const endTime = cursor;
  spans[0].totalDuration = totalDuration;

  return {
    traceId,
    type,
    totalDuration,
    startTime,
    endTime,
    spanCount: spans.length,
    hasError:  spans.some(s => s.status === 'ERROR'),
    spans,
  };
}

async function sendTrace(trace) {
  try {
    await axios.post(`${COLLECTOR_URL}/trace`, trace, { timeout: 5000 });
  } catch (e) {
    // Collector may be starting up
  }
}

async function run() {
  console.log(`[Generator] Starting — target ${TRACE_RATE} traces/sec → ${COLLECTOR_URL}`);
  await new Promise(r => setTimeout(r, 3000)); // wait for collector

  const intervalMs = 1000 / TRACE_RATE;
  let seq = 0;

  setInterval(async () => {
    const rand = Math.random();
    const type = rand < 0.60 ? 'normal' : rand < 0.85 ? 'slow' : 'error';
    const trace = generateTrace(type);
    await sendTrace(trace);
    seq++;
    if (seq % 50 === 0) {
      console.log(`[Generator] Sent ${seq} traces (last: ${type}, ${trace.spanCount} spans, ${trace.totalDuration}ms)`);
    }
  }, intervalMs);
}

run();
GENEOF

# ─── Collector Package ───────────────────────────────────────
cat > collector/package.json << 'EOF'
{
  "name": "sampling-collector",
  "version": "1.0.0",
  "main": "src/server.js",
  "dependencies": {
    "express":  "^4.19.2",
    "ws":       "^8.18.0",
    "redis":    "^4.7.0",
    "uuid":     "^10.0.0",
    "cors":     "^2.8.5"
  }
}
EOF

# ─── Sampling Strategies ────────────────────────────────────
cat > collector/src/strategies.js << 'STRATEOF'
/**
 * Four canonical distributed tracing sampling strategies.
 * Each exposes: decide(trace) → { keep: bool, reason: string }
 */

// ── Strategy 1: Head-Based Probabilistic ─────────────────────
class HeadProbabilistic {
  constructor(rate = 0.10) { this.rate = rate; }
  decide(trace) {
    const keep = Math.random() < this.rate;
    return {
      keep,
      reason: keep ? `head:sampled (${(this.rate*100).toFixed(1)}% rate)` : `head:dropped`,
      strategy: 'head_probabilistic',
    };
  }
}

// ── Strategy 2: Head-Based Rate Limited ──────────────────────
class HeadRateLimited {
  constructor(targetPerSec = 10) {
    this.target  = targetPerSec;
    this.bucket  = targetPerSec;
    this.last    = Date.now();
    this.refillRate = targetPerSec; // tokens per second
  }
  _refill() {
    const now     = Date.now();
    const elapsed = (now - this.last) / 1000;
    this.bucket   = Math.min(this.target, this.bucket + elapsed * this.refillRate);
    this.last     = now;
  }
  decide(trace) {
    this._refill();
    if (this.bucket >= 1) {
      this.bucket -= 1;
      return { keep: true,  reason: `rate:token consumed (${this.bucket.toFixed(1)} left)`, strategy: 'head_rate_limited' };
    }
    return { keep: false, reason: `rate:bucket empty`, strategy: 'head_rate_limited' };
  }
}

// ── Strategy 3: Tail-Based ───────────────────────────────────
class TailBased {
  constructor(opts = {}) {
    this.windowMs       = opts.windowMs       || 5000;  // buffer window
    this.latencyThresh  = opts.latencyThresh  || 500;   // ms — keep if exceeded
    this.alwaysErrors   = opts.alwaysErrors   !== false; // keep all errors
    this.baseSampleRate = opts.baseSampleRate || 0.05;  // 5% baseline for normal
  }
  decide(trace) {
    // Tail sampling: evaluate complete trace
    if (this.alwaysErrors && trace.hasError) {
      return { keep: true,  reason: `tail:error detected (${trace.spanCount} spans)`, strategy: 'tail_based' };
    }
    if (trace.totalDuration >= this.latencyThresh) {
      return { keep: true,  reason: `tail:slow trace ${trace.totalDuration}ms > ${this.latencyThresh}ms`, strategy: 'tail_based' };
    }
    if (Math.random() < this.baseSampleRate) {
      return { keep: true,  reason: `tail:baseline sample`, strategy: 'tail_based' };
    }
    return { keep: false, reason: `tail:not interesting`, strategy: 'tail_based' };
  }
}

// ── Strategy 4: Adaptive ──────────────────────────────────────
class Adaptive {
  constructor(opts = {}) {
    this.targetPerSec  = opts.targetPerSec  || 20;    // target kept traces/sec
    this.windowSec     = opts.windowSec     || 5;
    this.minRate       = opts.minRate       || 0.001;
    this.maxRate       = opts.maxRate       || 1.0;
    this.alpha         = opts.alpha         || 0.3;   // EWMA smoothing

    this.currentRate   = 0.10;
    this.keptInWindow  = 0;
    this.seenInWindow  = 0;
    this.windowStart   = Date.now();
  }
  _adjust() {
    const now     = Date.now();
    const elapsed = (now - this.windowStart) / 1000;
    if (elapsed < this.windowSec) return;

    const actualPerSec = this.keptInWindow / elapsed;
    const targetRate   = this.targetPerSec / (this.seenInWindow / elapsed || 1);

    // EWMA adjustment — avoid oscillation
    const newRate  = Math.max(this.minRate, Math.min(this.maxRate, targetRate));
    this.currentRate = this.alpha * newRate + (1 - this.alpha) * this.currentRate;

    this.keptInWindow = 0;
    this.seenInWindow = 0;
    this.windowStart  = Date.now();
  }
  decide(trace) {
    this._adjust();
    this.seenInWindow++;

    // Always keep errors in adaptive mode
    if (trace.hasError) {
      this.keptInWindow++;
      return { keep: true, reason: `adaptive:error (rate=${(this.currentRate*100).toFixed(2)}%)`, strategy: 'adaptive' };
    }

    const keep = Math.random() < this.currentRate;
    if (keep) this.keptInWindow++;
    return {
      keep,
      reason: keep ? `adaptive:sampled (rate=${(this.currentRate*100).toFixed(2)}%)` : `adaptive:dropped`,
      strategy: 'adaptive',
      currentRate: this.currentRate,
    };
  }
}

module.exports = { HeadProbabilistic, HeadRateLimited, TailBased, Adaptive };
STRATEOF

# ─── Collector Server ────────────────────────────────────────
cat > collector/src/server.js << 'SRVEOF'
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
SRVEOF

# ─── Dashboard HTML ──────────────────────────────────────────
cat > collector/public/index.html << 'DASHEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sampling Strategies — Live Dashboard</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  :root {
    --bg:        #04091a;
    --surface:   #081228;
    --card:      #0c1a38;
    --border:    #1a3060;
    --accent:    #2563eb;
    --accent2:   #3b82f6;
    --accent3:   #60a5fa;
    --text:      #e2e8f0;
    --muted:     #64748b;
    --keep:      #22d3ee;
    --drop:      #475569;
    --error:     #f87171;
    --slow:      #fbbf24;
    --font-mono: 'JetBrains Mono', monospace;
    --font-sans: 'IBM Plex Sans', sans-serif;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: var(--font-sans);
    min-height: 100vh;
    padding: 24px;
  }

  /* Header */
  .header {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 28px; padding-bottom: 20px;
    border-bottom: 1px solid var(--border);
  }
  .header-left h1 {
    font-size: 18px; font-weight: 600; letter-spacing: -0.02em;
    color: var(--text);
  }
  .header-left p {
    font-size: 12px; color: var(--muted); margin-top: 3px;
    font-family: var(--font-mono);
  }
  .pulse {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--keep);
    box-shadow: 0 0 8px var(--keep);
    animation: pulse 2s ease-in-out infinite;
    display: inline-block; margin-right: 8px;
  }
  @keyframes pulse { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.5;transform:scale(.8)} }

  /* Strategy Selector */
  .strategy-bar {
    display: flex; gap: 8px; flex-wrap: wrap;
    margin-bottom: 24px;
  }
  .strategy-btn {
    padding: 8px 16px; border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--card);
    color: var(--muted);
    font-family: var(--font-mono); font-size: 11px; font-weight: 500;
    cursor: pointer; letter-spacing: 0.03em;
    transition: all .2s;
  }
  .strategy-btn:hover { border-color: var(--accent2); color: var(--accent3); }
  .strategy-btn.active {
    background: var(--accent); border-color: var(--accent2);
    color: #fff;
    box-shadow: 0 0 12px rgba(37,99,235,.4);
  }

  /* Metrics Grid */
  .metrics {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 14px; margin-bottom: 24px;
  }
  .metric-card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px 18px;
    position: relative; overflow: hidden;
  }
  .metric-card::before {
    content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px;
    background: linear-gradient(90deg, var(--accent), var(--accent3));
  }
  .metric-label {
    font-size: 10px; font-weight: 500; color: var(--muted);
    letter-spacing: .08em; text-transform: uppercase; margin-bottom: 8px;
  }
  .metric-value {
    font-family: var(--font-mono); font-size: 28px; font-weight: 600;
    color: var(--text); line-height: 1; transition: all .3s;
  }
  .metric-sub { font-size: 10px; color: var(--muted); margin-top: 6px; font-family: var(--font-mono); }
  .metric-value.highlight { color: var(--keep); }
  .metric-value.warn      { color: var(--slow); }
  .metric-value.danger    { color: var(--error); }

  /* Main Content Split */
  .content { display: grid; grid-template-columns: 1fr 340px; gap: 16px; }
  @media (max-width: 1100px) { .content { grid-template-columns: 1fr; } }

  /* Trace Feed */
  .panel {
    background: var(--card); border: 1px solid var(--border);
    border-radius: 10px; overflow: hidden;
  }
  .panel-header {
    padding: 12px 18px; border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
  }
  .panel-title {
    font-size: 12px; font-weight: 600; color: var(--text);
    letter-spacing: .04em; text-transform: uppercase;
  }
  .panel-count {
    font-family: var(--font-mono); font-size: 11px; color: var(--muted);
  }
  .trace-feed { overflow-y: auto; max-height: 520px; padding: 8px; }
  .trace-item {
    display: grid; grid-template-columns: auto 1fr auto auto;
    gap: 12px; align-items: center;
    padding: 8px 10px; border-radius: 6px; margin-bottom: 4px;
    border: 1px solid transparent;
    font-family: var(--font-mono); font-size: 11px;
    transition: all .2s;
  }
  .trace-item.keep  { background: rgba(34,211,238,.05); border-color: rgba(34,211,238,.15); }
  .trace-item.drop  { background: rgba(71,85,105,.05);  border-color: rgba(71,85,105,.15); opacity: .7; }
  .trace-item.error-trace { background: rgba(248,113,113,.07); border-color: rgba(248,113,113,.2); }
  .badge {
    padding: 2px 8px; border-radius: 4px;
    font-size: 10px; font-weight: 600; letter-spacing: .05em;
    min-width: 44px; text-align: center;
  }
  .badge.keep  { background: rgba(34,211,238,.2); color: var(--keep); }
  .badge.drop  { background: rgba(71,85,105,.3);  color: #94a3b8; }
  .badge.error { background: rgba(248,113,113,.2); color: var(--error); }
  .trace-id    { color: var(--accent3); font-size: 10px; }
  .trace-dur   { color: var(--slow); font-size: 10px; }
  .trace-reason { color: var(--muted); font-size: 10px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 220px; }

  /* Right Column */
  .right-col { display: flex; flex-direction: column; gap: 14px; }

  /* Storage Bar */
  .storage-visual {
    padding: 18px;
  }
  .storage-label { font-size: 11px; color: var(--muted); margin-bottom: 10px; font-family: var(--font-mono); }
  .storage-bar-bg {
    height: 12px; background: rgba(71,85,105,.4); border-radius: 6px;
    overflow: hidden; margin-bottom: 8px;
  }
  .storage-bar-fill {
    height: 100%; border-radius: 6px;
    background: linear-gradient(90deg, var(--accent), var(--keep));
    transition: width .8s ease;
  }
  .storage-stats {
    display: flex; justify-content: space-between;
    font-family: var(--font-mono); font-size: 10px; color: var(--muted);
  }
  .kept-mb   { color: var(--keep); }
  .dropped-mb { color: var(--drop); }

  /* Strategy Explainer */
  .explainer { padding: 16px 18px; }
  .explainer-title { font-size: 11px; font-weight: 600; color: var(--accent3); margin-bottom: 8px; text-transform: uppercase; letter-spacing: .06em; }
  .explainer-text  { font-size: 12px; line-height: 1.7; color: #94a3b8; }

  /* Legend */
  .legend { display: flex; gap: 14px; flex-wrap: wrap; padding: 14px 18px; border-top: 1px solid var(--border); }
  .legend-item { display: flex; align-items: center; gap: 5px; font-size: 10px; color: var(--muted); }
  .dot { width: 7px; height: 7px; border-radius: 50%; }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    <h1><span class="pulse"></span>Distributed Tracing Sampling Dashboard</h1>
    <p>Article 201 — Section 8: Production Engineering &amp; Optimization</p>
  </div>
  <div style="font-family:var(--font-mono);font-size:11px;color:var(--muted)" id="conn-status">Connecting...</div>
</div>

<div class="strategy-bar" id="strategy-bar">
  <button class="strategy-btn" data-s="head_probabilistic">Head Probabilistic</button>
  <button class="strategy-btn" data-s="head_rate_limited">Head Rate-Limited</button>
  <button class="strategy-btn active" data-s="tail_based">Tail-Based</button>
  <button class="strategy-btn" data-s="adaptive">Adaptive</button>
</div>

<div class="metrics">
  <div class="metric-card">
    <div class="metric-label">Traces Received</div>
    <div class="metric-value" id="m-received">—</div>
    <div class="metric-sub">total ingested</div>
  </div>
  <div class="metric-card">
    <div class="metric-label">Sample Rate</div>
    <div class="metric-value highlight" id="m-rate">—</div>
    <div class="metric-sub">% of traces kept</div>
  </div>
  <div class="metric-card">
    <div class="metric-label">Kept / sec</div>
    <div class="metric-value" id="m-kps">—</div>
    <div class="metric-sub">5-sec sliding window</div>
  </div>
  <div class="metric-card">
    <div class="metric-label">Errors Kept</div>
    <div class="metric-value warn" id="m-err">—</div>
    <div class="metric-sub">% of errors sampled</div>
  </div>
  <div class="metric-card">
    <div class="metric-label">Storage Saved</div>
    <div class="metric-value highlight" id="m-saved">—</div>
    <div class="metric-sub">bytes dropped vs total</div>
  </div>
  <div class="metric-card">
    <div class="metric-label">Dropped</div>
    <div class="metric-value" id="m-dropped" style="color:var(--muted)">—</div>
    <div class="metric-sub">not written to storage</div>
  </div>
</div>

<div class="content">
  <div class="panel">
    <div class="panel-header">
      <span class="panel-title">Live Sampling Decisions</span>
      <span class="panel-count" id="feed-count">0 decisions</span>
    </div>
    <div class="trace-feed" id="trace-feed"></div>
    <div class="legend">
      <div class="legend-item"><div class="dot" style="background:var(--keep)"></div>KEEP</div>
      <div class="legend-item"><div class="dot" style="background:var(--drop)"></div>DROP</div>
      <div class="legend-item"><div class="dot" style="background:var(--error)"></div>ERROR trace</div>
      <div class="legend-item"><div class="dot" style="background:var(--slow)"></div>slow trace</div>
    </div>
  </div>

  <div class="right-col">
    <div class="panel">
      <div class="panel-header"><span class="panel-title">Storage Breakdown</span></div>
      <div class="storage-visual">
        <div class="storage-label">KEPT vs DROPPED bytes (estimated)</div>
        <div class="storage-bar-bg"><div class="storage-bar-fill" id="storage-bar" style="width:10%"></div></div>
        <div class="storage-stats">
          <span class="kept-mb">Kept: <span id="s-kept">0</span> MB</span>
          <span class="dropped-mb">Dropped: <span id="s-dropped">0</span> MB</span>
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-header"><span class="panel-title">Active Strategy</span></div>
      <div class="explainer">
        <div class="explainer-title" id="strat-name">tail_based</div>
        <div class="explainer-text" id="strat-desc">Loading...</div>
      </div>
    </div>
  </div>
</div>

<script>
const DESCRIPTIONS = {
  head_probabilistic: 'Sampling decision made at trace start. 10% probability — no information about downstream spans. Fast and cheap, but errors can be dropped before they happen.',
  head_rate_limited:  'Token bucket allows ~12 traces/sec. Fills continuously; if token bucket is empty, traces are dropped regardless of content.',
  tail_based:         'All spans buffered. Decision made after trace completes: keep if error detected OR latency > 400ms. 5% baseline sample for normal traces.',
  adaptive:           'EWMA-adjusted rate targeting ~15 kept traces/sec. Auto-scales between 0.1% and 100%. Always keeps errors. Avoids oscillation via smoothing.',
};

let currentStrategy = 'tail_based';
let ws;

function connect() {
  ws = new WebSocket(`ws://${location.host}`);
  ws.onopen = () => {
    document.getElementById('conn-status').textContent = '● Connected';
    document.getElementById('conn-status').style.color = '#22d3ee';
  };
  ws.onclose  = () => { setTimeout(connect, 2000); };
  ws.onerror  = () => { ws.close(); };
  ws.onmessage = e => render(JSON.parse(e.data));
}

function num(n) { return Number(n).toLocaleString(); }
function pct(n) { return `${n}%`; }
const noData = '—';

function render(data) {
  const hasData = data.received > 0;
  document.getElementById('m-received').textContent = num(data.received);
  document.getElementById('m-rate').textContent     = hasData ? pct(data.keptRatePct) : noData;
  document.getElementById('m-kps').textContent      = hasData ? data.keptPerSec : noData;
  document.getElementById('m-err').textContent      = data.errorsKeptPct + (data.errorsKeptPct === '—' ? '' : '%');
  document.getElementById('m-saved').textContent     = hasData ? pct(data.storageSavePct) : noData;
  document.getElementById('m-dropped').textContent   = hasData ? num(data.dropped) : noData;

  document.getElementById('s-kept').textContent    = hasData ? data.bytesKeptMB : '0';
  document.getElementById('s-dropped').textContent = hasData ? data.bytesDroppedMB : '0';

  const keptF = parseFloat(data.bytesKeptMB) || 0;
  const totF  = keptF + (parseFloat(data.bytesDroppedMB) || 0);
  const barW  = totF > 0 ? ((keptF / totF) * 100).toFixed(1) : 10;
  document.getElementById('storage-bar').style.width = barW + '%';

  // Update strategy if changed server-side
  if (data.strategy !== currentStrategy) {
    currentStrategy = data.strategy;
    updateStrategyUI(currentStrategy);
  }

  document.getElementById('feed-count').textContent = hasData ? `${data.kept + data.dropped} decisions` : '0 decisions';
  renderFeed(data.recentTraces || []);
}

function renderFeed(traces) {
  const feed = document.getElementById('trace-feed');
  feed.innerHTML = traces.map(t => {
    const cls   = t.hasError ? 'error-trace' : (t.keep ? 'keep' : 'drop');
    const badge = t.hasError ? 'error' : (t.keep ? 'keep' : 'drop');
    const bl    = t.hasError ? 'ERR' : (t.keep ? 'KEEP' : 'DROP');
    const durColor = t.duration > 400 ? 'color:var(--slow)' : '';
    return `<div class="trace-item ${cls}">
      <span class="badge ${badge}">${bl}</span>
      <span class="trace-reason">${esc(t.reason)}</span>
      <span class="trace-id">${t.traceId}</span>
      <span class="trace-dur" style="${durColor}">${t.duration}ms</span>
    </div>`;
  }).join('');
}

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;');
}

function updateStrategyUI(s) {
  document.querySelectorAll('.strategy-btn').forEach(b => b.classList.toggle('active', b.dataset.s === s));
  document.getElementById('strat-name').textContent = s;
  document.getElementById('strat-desc').textContent = DESCRIPTIONS[s] || '';
}

document.querySelectorAll('.strategy-btn').forEach(btn => {
  btn.addEventListener('click', async () => {
    const s = btn.dataset.s;
    await fetch('/strategy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ strategy: s }),
    });
    currentStrategy = s;
    updateStrategyUI(s);
  });
});

updateStrategyUI(currentStrategy);
connect();
</script>
</body>
</html>
DASHEOF

# ─── Dockerfiles ────────────────────────────────────────────
cat > generator/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY index.js .
CMD ["node", "index.js"]
EOF

cat > collector/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY src/ src/
COPY public/ public/
EXPOSE 3000
CMD ["node", "src/server.js"]
EOF

# ─── Docker Compose ──────────────────────────────────────────
cat > docker-compose.yml << 'EOF'
services:
  collector:
    build: ./collector
    ports:
      - "3000:3000"
    environment:
      - PORT=3000
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  generator:
    build: ./generator
    depends_on:
      collector:
        condition: service_healthy
    environment:
      - COLLECTOR_URL=http://collector:3000
      - TRACE_RATE=18
    restart: unless-stopped
EOF

# ─── Tests ──────────────────────────────────────────────────
cat > tests/test.sh << 'EOF'
#!/bin/bash
BASE="http://localhost:3000"
PASS=0; FAIL=0

chk() {
  local label="$1"; local cmd="$2"; local expect="$3"
  local actual; actual=$(eval "$cmd" 2>/dev/null)
  if echo "$actual" | grep -q "$expect"; then
    echo "  ✓ $label"; ((PASS++))
  else
    echo "  ✗ $label (got: $actual)"; ((FAIL++))
  fi
}

echo ""
echo "Running integration tests..."
echo ""

chk "Health endpoint returns ok"        "curl -sf $BASE/health"              '"ok"'
chk "Stats endpoint reachable"          "curl -sf $BASE/stats"               '"received"'
chk "Strategy: head_probabilistic"      "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"head_probabilistic\"}'" '"ok":true'
chk "Strategy: head_rate_limited"       "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"head_rate_limited\"}'"  '"ok":true'
chk "Strategy: tail_based"             "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"tail_based\"}'"          '"ok":true'
chk "Strategy: adaptive"               "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"adaptive\"}'"            '"ok":true'
chk "Reject unknown strategy"          "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"unknown\"}'|| echo 'error'"  'error'
chk "Trace ingestion endpoint"         "curl -sf -X POST $BASE/trace -H 'Content-Type: application/json' -d '{\"traceId\":\"test123\",\"type\":\"normal\",\"totalDuration\":120,\"spanCount\":3,\"hasError\":false,\"spans\":[]}'" '"sampled"'
chk "Trace feed populated in stats"    "curl -sf $BASE/stats"               '"recentTraces"'

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
EOF
chmod +x tests/test.sh

# ─── Demo Script ────────────────────────────────────────────
cat > demo.sh << 'EOF'
#!/bin/bash
echo "Switching strategies every 15 seconds for live comparison..."
echo ""
STRATEGIES=("tail_based" "head_probabilistic" "adaptive" "head_rate_limited")
for S in "${STRATEGIES[@]}"; do
  echo "→ Setting strategy: $S"
  curl -sf -X POST http://localhost:3000/strategy \
    -H 'Content-Type: application/json' \
    -d "{\"strategy\":\"$S\"}" | python3 -m json.tool 2>/dev/null || true
  echo "   (watching for 15 seconds — check http://localhost:3000)"
  sleep 15
done
echo ""
echo "Demo complete. Open http://localhost:3000 to explore."
EOF
chmod +x demo.sh

# ─── Cleanup Script ─────────────────────────────────────────
cat > cleanup.sh << 'EOF'
#!/bin/bash
echo "Stopping and removing containers..."
docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null
echo "Removing built images..."
docker rmi tracing-sampling-demo-collector tracing-sampling-demo-generator 2>/dev/null || true
echo "Cleaned up."
EOF
chmod +x cleanup.sh

success "All source files generated"

# ─── Verify generated files ───────────────────────────────────
step "Verifying generated files"
for f in generator/package.json generator/index.js generator/Dockerfile \
         collector/package.json collector/src/strategies.js collector/src/server.js collector/public/index.html collector/Dockerfile \
         docker-compose.yml tests/test.sh demo.sh cleanup.sh; do
  [ -f "$f" ] || error "Missing generated file: $f"
done
success "All expected files present"

# ─── Build ──────────────────────────────────────────────────
step "Building Docker images (first build may take 60–90s)"
$COMPOSE build --parallel 2>&1 | grep -E "(Step|Successfully|error|Error|=>)" | head -40
success "Images built"

# ─── Start ──────────────────────────────────────────────────
step "Starting services"
$COMPOSE up -d
info "Waiting for collector to become healthy..."

ATTEMPTS=0
until curl -sf http://localhost:3000/health >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS+1))
  [ $ATTEMPTS -gt 30 ] && error "Collector did not become healthy in time. Check: docker logs tracing-sampling-demo-collector-1"
  sleep 2
done
success "Collector healthy"

# Wait a few seconds for traces to start flowing
info "Waiting 8s for generator to start producing traces..."
sleep 8

# ─── Tests ──────────────────────────────────────────────────
step "Running integration tests"
bash "$DEMO_ROOT/tests/test.sh"
TEST_EXIT=$?
[ $TEST_EXIT -eq 0 ] && success "All tests passed" || warn "Some tests failed — check output above"

# ─── Done ────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓ Sampling Demo Running${NC}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Dashboard:${NC}   http://localhost:3000"
echo -e "  ${CYAN}Stats API:${NC}   http://localhost:3000/stats"
echo -e "  ${CYAN}Health:${NC}      http://localhost:3000/health"
echo ""
echo -e "${BOLD}  What to explore:${NC}"
echo -e "  1. Watch the live trace feed — compare KEEP vs DROP decisions"
echo -e "  2. Click ${CYAN}Head Probabilistic${NC} — notice error traces get dropped randomly"
echo -e "  3. Switch to ${CYAN}Tail-Based${NC} — errors and slow traces always kept"
echo -e "  4. Try ${CYAN}Adaptive${NC} — watch sample rate auto-adjust to hit target"
echo -e "  5. Compare ${CYAN}Storage Saved %${NC} across strategies"
echo ""
echo -e "  ${CYAN}Run demo cycle:${NC}  bash $DEMO_ROOT/demo.sh"
echo -e "  ${CYAN}View logs:${NC}       docker logs -f tracing-sampling-demo-collector-1"
echo -e "  ${CYAN}Stop & clean:${NC}    bash $DEMO_ROOT/cleanup.sh"
echo ""