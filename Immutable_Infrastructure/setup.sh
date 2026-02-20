#!/bin/bash
# =============================================================================
# Immutable Infrastructure Demo
# Article 205 - System Design Interview Roadmap
# Demonstrates: image baking, blue-green deployment, rollback, drift detection
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$SCRIPT_DIR/immutable-infra-demo"
BLUE_PORT=3001
GREEN_PORT=3002
PROXY_PORT=3000
REGISTRY_PORT=5005

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $*"; }
fail() { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${BLUE}  $*${NC}"; echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }

# =============================================================================
# PREFLIGHT
# =============================================================================
section "Preflight Checks"
command -v docker >/dev/null 2>&1 || fail "Docker is required. Install from https://docs.docker.com/get-docker/"
command -v docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || fail "docker compose is required"
ok "Docker available: $(docker --version)"

# =============================================================================
# DIRECTORY STRUCTURE
# =============================================================================
section "Creating Project Structure"
rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR"/{v1-app,v2-app,proxy,dashboard,registry-ui,tests,scripts}
cd "$DEMO_DIR"
ok "Project directory: $DEMO_DIR"

# =============================================================================
# V1 APPLICATION (baseline image)
# =============================================================================
log "Writing v1 application (image: api:v1.0.0)..."

cat > "$DEMO_DIR/v1-app/package.json" << 'EOF'
{
  "name": "immutable-api",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2",
    "uuid": "9.0.1"
  }
}
EOF

cat > "$DEMO_DIR/v1-app/server.js" << 'EOF'
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const app = express();
const PORT = 3001;

// Simulate immutable: version/image metadata baked at build time, never mutated
const IMAGE_ID   = process.env.IMAGE_ID   || 'api:v1.0.0';
const IMAGE_SHA  = process.env.IMAGE_SHA  || 'sha256:a1b2c3d4e5f6';
const BUILD_TIME = process.env.BUILD_TIME || new Date().toISOString();
const INSTANCE_ID = uuidv4(); // unique per instance, immutable after start
const startTime  = Date.now();

app.use(express.json());
app.use(function(req,res,next){ res.setHeader('Access-Control-Allow-Origin','*'); next(); });

// Simulate config drift detection
const KNOWN_SYSCTLS = { 'net.core.somaxconn': '1024', 'vm.swappiness': '10' };

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', instance: INSTANCE_ID, image: IMAGE_ID });
});

app.get('/api/info', (req, res) => {
  res.json({
    version: '1.0.0',
    image: IMAGE_ID,
    imageSha: IMAGE_SHA,
    buildTime: BUILD_TIME,
    instanceId: INSTANCE_ID,
    uptimeSeconds: Math.floor((Date.now() - startTime) / 1000),
    color: 'blue',
    features: ['basic-auth', 'rate-limiting'],
    sysctls: KNOWN_SYSCTLS,
    mutablePatch: false,  // this instance has never been mutated
  });
});

app.get('/api/data', (req, res) => {
  res.json({
    message: 'Response from v1.0.0',
    items: Array.from({ length: 5 }, (_, i) => ({
      id: `v1-item-${i + 1}`,
      value: Math.floor(Math.random() * 100),
    })),
  });
});

// Endpoint to simulate what mutable infra looks like (for comparison)
app.post('/admin/mutate', (req, res) => {
  // In real immutable infra, this endpoint would not exist / return 403
  res.status(403).json({
    error: 'Mutation rejected: this instance is immutable',
    reason: 'Change requires image rebuild → redeploy pipeline',
    hint: 'POST to /api/deploy-pipeline with your change manifest',
  });
});

app.listen(PORT, () => console.log(`[v1.0.0] Instance ${INSTANCE_ID} listening on :${PORT}`));
EOF

cat > "$DEMO_DIR/v1-app/Dockerfile" << 'EOF'
# Multi-stage build: builder isolates dev dependencies from runtime image
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .

# Final stage: minimal runtime — no shell, no package manager, no ssh
FROM node:20-alpine AS runtime
WORKDIR /app
# Pin OS packages. In real pipelines, image is scanned here before promotion.
RUN apk add --no-cache dumb-init
COPY --from=builder /app .

# Bake image metadata at build time (GitSHA, timestamp, version)
ARG IMAGE_ID=api:v1.0.0
ARG IMAGE_SHA=sha256:a1b2c3d4e5f6
ARG BUILD_TIME=unknown
ENV IMAGE_ID=$IMAGE_ID IMAGE_SHA=$IMAGE_SHA BUILD_TIME=$BUILD_TIME

# Non-root user — further reduces attack surface
RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3001
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
EOF

# =============================================================================
# V2 APPLICATION (upgraded image — new feature, no mutation)
# =============================================================================
log "Writing v2 application (image: api:v2.0.0)..."

cat > "$DEMO_DIR/v2-app/package.json" << 'EOF'
{
  "name": "immutable-api",
  "version": "2.0.0",
  "dependencies": {
    "express": "4.18.2",
    "uuid": "9.0.1"
  }
}
EOF

cat > "$DEMO_DIR/v2-app/server.js" << 'EOF'
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const app = express();
const PORT = 3002;

const IMAGE_ID   = process.env.IMAGE_ID   || 'api:v2.0.0';
const IMAGE_SHA  = process.env.IMAGE_SHA  || 'sha256:b2c3d4e5f6a1';
const BUILD_TIME = process.env.BUILD_TIME || new Date().toISOString();
const INSTANCE_ID = uuidv4();
const startTime  = Date.now();

app.use(express.json());
app.use(function(req,res,next){ res.setHeader('Access-Control-Allow-Origin','*'); next(); });

// v2 adds new sysctl config and feature flags — baked, not patched
const KNOWN_SYSCTLS = {
  'net.core.somaxconn': '4096',  // tuned in v2
  'vm.swappiness': '5',           // tuned in v2
  'net.ipv4.tcp_tw_reuse': '1'   // new in v2
};

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', instance: INSTANCE_ID, image: IMAGE_ID });
});

app.get('/api/info', (req, res) => {
  res.json({
    version: '2.0.0',
    image: IMAGE_ID,
    imageSha: IMAGE_SHA,
    buildTime: BUILD_TIME,
    instanceId: INSTANCE_ID,
    uptimeSeconds: Math.floor((Date.now() - startTime) / 1000),
    color: 'green',
    features: ['basic-auth', 'rate-limiting', 'circuit-breaker', 'distributed-tracing'],
    sysctls: KNOWN_SYSCTLS,
    mutablePatch: false,
  });
});

app.get('/api/data', (req, res) => {
  res.json({
    message: 'Response from v2.0.0 — new circuit-breaker enabled',
    items: Array.from({ length: 5 }, (_, i) => ({
      id: `v2-item-${i + 1}`,
      value: Math.floor(Math.random() * 100),
      enriched: true,  // new field in v2
    })),
  });
});

app.post('/admin/mutate', (req, res) => {
  res.status(403).json({
    error: 'Mutation rejected: this instance is immutable',
    reason: 'Change requires image rebuild → redeploy pipeline',
  });
});

app.listen(PORT, () => console.log(`[v2.0.0] Instance ${INSTANCE_ID} listening on :${PORT}`));
EOF

cat > "$DEMO_DIR/v2-app/Dockerfile" << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .

FROM node:20-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache dumb-init
COPY --from=builder /app .

ARG IMAGE_ID=api:v2.0.0
ARG IMAGE_SHA=sha256:b2c3d4e5f6a1
ARG BUILD_TIME=unknown
ENV IMAGE_ID=$IMAGE_ID IMAGE_SHA=$IMAGE_SHA BUILD_TIME=$BUILD_TIME

RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3002
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
EOF

# =============================================================================
# PROXY (traffic switch — simulates load balancer / service mesh control plane)
# =============================================================================
log "Writing traffic-switch proxy..."

cat > "$DEMO_DIR/proxy/package.json" << 'EOF'
{
  "name": "traffic-switch",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2",
    "http-proxy-middleware": "2.0.6",
    "node-fetch": "3.3.2"
  }
}
EOF

cat > "$DEMO_DIR/proxy/server.js" << 'EOF'
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const fetch = (...args) => import('node-fetch').then(({ default: f }) => f(...args));

const app = express();
app.use(express.json());
app.use(function(req,res,next){ res.setHeader('Access-Control-Allow-Origin','*'); if(req.method==='OPTIONS'){ res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS'); res.setHeader('Access-Control-Allow-Headers','Content-Type'); return res.sendStatus(200); } next(); });

// Traffic state — in real infra this is a control-plane config (Envoy xDS, ALB target group)
let state = {
  active: 'blue',    // blue = v1, green = v2
  blueTarget:  'http://api-v1:3001',
  greenTarget: 'http://api-v2:3002',
  deployHistory: [{ ts: new Date().toISOString(), event: 'proxy_start', active: 'blue' }],
};

function getActiveTarget() {
  return state.active === 'blue' ? state.blueTarget : state.greenTarget;
}

// Status endpoint for dashboard
app.get('/proxy/status', (req, res) => res.json(state));

// Health check both upstreams
app.get('/proxy/health-check', async (req, res) => {
  const check = async (url, name) => {
    try {
      const r = await fetch(`${url}/health`, { timeout: 2000 });
      const body = await r.json();
      return { name, healthy: true, ...body };
    } catch (e) {
      return { name, healthy: false, error: e.message };
    }
  };
  const [blue, green] = await Promise.all([
    check(state.blueTarget, 'blue-v1'),
    check(state.greenTarget, 'green-v2'),
  ]);
  res.json({ blue, green, activeSlot: state.active });
});

// Traffic switch — the core of blue-green immutable deploys
app.post('/proxy/switch', async (req, res) => {
  const target = req.body.target; // 'blue' or 'green'
  if (!['blue', 'green'].includes(target)) {
    return res.status(400).json({ error: 'target must be blue or green' });
  }

  // Pre-switch health check (simulate load balancer health gate)
  const targetUrl = target === 'blue' ? state.blueTarget : state.greenTarget;
  try {
    const r = await fetch(`${targetUrl}/health`, { timeout: 3000 });
    if (!r.ok) throw new Error(`health returned ${r.status}`);
  } catch (e) {
    return res.status(503).json({ error: `Health check failed for ${target}: ${e.message}` });
  }

  const prev = state.active;
  state.active = target;
  state.deployHistory.push({
    ts: new Date().toISOString(),
    event: 'traffic_switch',
    from: prev,
    to: target,
    reason: req.body.reason || 'manual',
  });

  res.json({ success: true, previous: prev, current: state.active, message: `Traffic → ${target}` });
});

// Proxy all /api/* traffic to the active upstream
app.use('/api', (req, res, next) => {
  const proxy = createProxyMiddleware({
    target: getActiveTarget(),
    changeOrigin: true,
    on: {
      error: (err, req, res) => {
        res.status(502).json({ error: 'upstream error', detail: err.message });
      },
    },
  });
  proxy(req, res, next);
});

app.listen(3000, () => console.log('[proxy] Traffic switch listening on :3000'));
EOF

cat > "$DEMO_DIR/proxy/Dockerfile" << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# =============================================================================
# DASHBOARD
# =============================================================================
log "Writing dashboard..."

cat > "$DEMO_DIR/dashboard/package.json" << 'EOF'
{
  "name": "immutable-dashboard",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.18.2"
  }
}
EOF

cat > "$DEMO_DIR/dashboard/server.js" << 'EOF'
const express = require('express');
const path = require('path');
const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.listen(8080, () => console.log('[dashboard] http://localhost:8080'));
EOF

mkdir -p "$DEMO_DIR/dashboard/public"

cat > "$DEMO_DIR/dashboard/public/style.css" << 'CSSEOF'
/* Light purple theme override */
:root {
  --bg: #f5f3ff;
  --card: #faf5ff;
  --blue-dark: #5b21b6;
  --blue-mid: #8b5cf6;
  --blue-light: #c4b5fd;
  --blue-faint: #ede9fe;
  --green: #16a34a;
  --green-light: #bbf7d0;
  --red: #dc2626;
  --red-light: #fee2e2;
  --text: #3b0764;
  --muted: #6b21a8;
  --shadow: 0 4px 24px rgba(139, 92, 246, 0.15);
  --radius: 14px;
}
body { background: var(--bg); color: var(--text); }
header { background: linear-gradient(135deg, #5b21b6 0%, #8b5cf6 100%); box-shadow: 0 2px 16px rgba(91, 33, 182, 0.3); }
.stat-card { border-top-color: var(--blue-mid); background: var(--card); box-shadow: var(--shadow); }
.stat-card .value { color: var(--blue-dark); }
.slot { background: var(--card); box-shadow: var(--shadow); }
.slot.active { border-color: var(--blue-mid); box-shadow: 0 0 0 4px rgba(139, 92, 246, 0.12), var(--shadow); }
.badge-active { background: #ede9fe; color: var(--blue-dark); }
.feature { background: var(--blue-faint); color: var(--blue-dark); }
.controls { background: var(--card); box-shadow: var(--shadow); }
.controls h2 { color: var(--blue-dark); }
.btn-green { background: var(--blue-mid); }
.btn-green:hover { background: var(--blue-dark); box-shadow: 0 4px 12px rgba(139, 92, 246, 0.35); }
.pipeline { background: var(--card); box-shadow: var(--shadow); }
.pipeline h2 { color: var(--blue-dark); }
.stage.done .stage-icon { background: #ede9fe; color: var(--blue-mid); }
.stage.active .stage-icon { background: var(--blue-mid); box-shadow: 0 0 0 6px rgba(139, 92, 246, 0.2); }
.stage.done .stage-label { color: var(--blue-dark); }
.stage.active .stage-label { color: var(--blue-mid); }
.stage-arrow.done { background: var(--blue-light); }
@keyframes pulse { 0%,100% { box-shadow: 0 0 0 4px rgba(139, 92, 246, 0.2); } 50% { box-shadow: 0 0 0 8px rgba(139, 92, 246, 0.1); } }
.diff { background: var(--card); box-shadow: var(--shadow); }
.diff h2 { color: var(--blue-dark); }
.diff-table th { background: var(--blue-faint); color: var(--blue-dark); }
.toast { background: var(--blue-dark); }
CSSEOF

cat > "$DEMO_DIR/dashboard/public/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Immutable Infrastructure — Live Deploy Console</title>
<link rel="stylesheet" href="style.css">
<style>
  :root {
    --bg: #f0f4ff;
    --card: #ffffff;
    --blue-dark: #1e40af;
    --blue-mid: #3b82f6;
    --blue-light: #93c5fd;
    --blue-faint: #eff6ff;
    --green: #16a34a;
    --green-light: #bbf7d0;
    --red: #dc2626;
    --red-light: #fee2e2;
    --text: #1e293b;
    --muted: #64748b;
    --shadow: 0 4px 24px rgba(59,130,246,0.10);
    --radius: 14px;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background: var(--bg); color: var(--text); min-height: 100vh; }
  header { background: linear-gradient(135deg, var(--blue-dark) 0%, var(--blue-mid) 100%); color: #fff; padding: 28px 36px; box-shadow: 0 2px 16px rgba(30,64,175,0.3); }
  header h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: -0.5px; }
  header p  { margin-top: 4px; opacity: 0.8; font-size: 0.875rem; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 99px; font-size: 0.72rem; font-weight: 600; background: rgba(255,255,255,0.2); color: #fff; margin-left: 10px; vertical-align: middle; }
  main { max-width: 1200px; margin: 0 auto; padding: 32px 24px; }

  /* Status bar */
  .status-bar { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 28px; }
  .stat-card { background: var(--card); border-radius: var(--radius); box-shadow: var(--shadow); padding: 20px 22px; border-top: 4px solid var(--blue-mid); }
  .stat-card .label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.5px; font-weight: 600; }
  .stat-card .value { font-size: 1.7rem; font-weight: 800; color: var(--blue-dark); margin-top: 6px; font-variant-numeric: tabular-nums; }
  .stat-card .sub   { font-size: 0.78rem; color: var(--muted); margin-top: 4px; }

  /* Slot grid */
  .slot-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 28px; }
  .slot { background: var(--card); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px; position: relative; transition: box-shadow 0.3s; }
  .slot.active  { border: 2.5px solid var(--blue-mid); box-shadow: 0 0 0 4px rgba(59,130,246,0.12), var(--shadow); }
  .slot.inactive{ border: 2px dashed #cbd5e1; opacity: 0.75; }
  .slot-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
  .slot-name { font-weight: 700; font-size: 1.05rem; }
  .slot-badge { padding: 3px 12px; border-radius: 99px; font-size: 0.72rem; font-weight: 700; }
  .badge-active   { background: #dbeafe; color: var(--blue-dark); }
  .badge-inactive { background: #f1f5f9; color: var(--muted); }
  .badge-live     { background: #dcfce7; color: var(--green); }
  .slot-info p { font-size: 0.82rem; color: var(--muted); margin-bottom: 5px; }
  .slot-info span { font-weight: 600; color: var(--text); }
  .feature-list { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
  .feature { background: var(--blue-faint); color: var(--blue-dark); border-radius: 6px; padding: 3px 9px; font-size: 0.72rem; font-weight: 600; }

  /* Controls */
  .controls { background: var(--card); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px; margin-bottom: 28px; }
  .controls h2 { font-size: 1rem; font-weight: 700; margin-bottom: 16px; color: var(--blue-dark); }
  .btn-row { display: flex; gap: 12px; flex-wrap: wrap; }
  button { cursor: pointer; border: none; border-radius: 8px; padding: 10px 20px; font-size: 0.875rem; font-weight: 600; transition: all 0.15s; }
  .btn-green  { background: var(--blue-mid); color: #fff; }
  .btn-green:hover  { background: var(--blue-dark); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(59,130,246,0.35); }
  .btn-orange { background: #f97316; color: #fff; }
  .btn-orange:hover { background: #ea580c; transform: translateY(-1px); }
  .btn-red    { background: var(--red); color: #fff; }
  .btn-red:hover    { background: #b91c1c; transform: translateY(-1px); }
  .btn-gray   { background: #e2e8f0; color: var(--text); }
  .btn-gray:hover   { background: #cbd5e1; }
  .btn-sm { padding: 7px 14px; font-size: 0.8rem; }
  button:disabled { opacity: 0.5; cursor: not-allowed; transform: none !important; }

  /* Pipeline visualizer */
  .pipeline { background: var(--card); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px; margin-bottom: 28px; }
  .pipeline h2 { font-size: 1rem; font-weight: 700; margin-bottom: 16px; color: var(--blue-dark); }
  .stages { display: flex; align-items: center; gap: 0; overflow-x: auto; padding-bottom: 8px; }
  .stage { display: flex; flex-direction: column; align-items: center; min-width: 110px; }
  .stage-icon { width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 1.4rem; font-weight: 700; background: #e2e8f0; color: var(--muted); transition: all 0.4s; }
  .stage.done   .stage-icon { background: #dbeafe; color: var(--blue-mid); }
  .stage.active .stage-icon { background: var(--blue-mid); color: #fff; box-shadow: 0 0 0 6px rgba(59,130,246,0.2); animation: pulse 1.2s infinite; }
  .stage.fail   .stage-icon { background: var(--red-light); color: var(--red); }
  .stage-label { font-size: 0.7rem; font-weight: 600; color: var(--muted); margin-top: 6px; text-align: center; }
  .stage.done   .stage-label { color: var(--blue-dark); }
  .stage.active .stage-label { color: var(--blue-mid); }
  .stage-arrow { flex: 1; min-width: 24px; height: 2px; background: #e2e8f0; margin-top: -22px; }
  .stage-arrow.done { background: var(--blue-light); }
  @keyframes pulse { 0%,100% { box-shadow: 0 0 0 4px rgba(59,130,246,0.2); } 50% { box-shadow: 0 0 0 8px rgba(59,130,246,0.1); } }

  /* Event log */
  .log-panel { background: #0f172a; border-radius: var(--radius); box-shadow: var(--shadow); padding: 20px; margin-bottom: 28px; min-height: 180px; max-height: 260px; overflow-y: auto; }
  .log-panel h2 { color: #94a3b8; font-size: 0.8rem; font-weight: 700; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; }
  .log-entry { font-family: 'JetBrains Mono', 'Fira Code', monospace; font-size: 0.78rem; line-height: 1.7; }
  .log-entry .ts { color: #475569; }
  .log-entry .msg-info  { color: #60a5fa; }
  .log-entry .msg-ok    { color: #34d399; }
  .log-entry .msg-warn  { color: #fbbf24; }
  .log-entry .msg-err   { color: #f87171; }

  /* Diff view */
  .diff { background: var(--card); border-radius: var(--radius); box-shadow: var(--shadow); padding: 24px; }
  .diff h2 { font-size: 1rem; font-weight: 700; margin-bottom: 14px; color: var(--blue-dark); }
  .diff-table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
  .diff-table th { background: var(--blue-faint); color: var(--blue-dark); padding: 8px 12px; text-align: left; font-weight: 700; }
  .diff-table td { padding: 7px 12px; border-bottom: 1px solid #f1f5f9; }
  .diff-table tr:last-child td { border-bottom: none; }
  .diff-add { color: var(--green); font-weight: 600; }
  .diff-change { color: #d97706; font-weight: 600; }
  .diff-same { color: var(--muted); }
  .pill-changed { background: #fef3c7; color: #92400e; border-radius: 4px; padding: 1px 7px; font-size: 0.68rem; font-weight: 700; }
  .pill-new { background: var(--green-light); color: #166534; border-radius: 4px; padding: 1px 7px; font-size: 0.68rem; font-weight: 700; }
  .pill-same { background: #f1f5f9; color: var(--muted); border-radius: 4px; padding: 1px 7px; font-size: 0.68rem; }

  .toast { position: fixed; bottom: 24px; right: 24px; background: var(--blue-dark); color: #fff; padding: 12px 22px; border-radius: 10px; font-size: 0.85rem; font-weight: 600; box-shadow: 0 8px 24px rgba(0,0,0,0.25); transform: translateY(80px); opacity: 0; transition: all 0.3s; z-index: 999; }
  .toast.show { transform: translateY(0); opacity: 1; }
</style>
</head>
<body>
<header>
  <h1>🔒 Immutable Infrastructure <span class="badge">Live Deploy Console</span></h1>
  <p>Blue-green deployment pipeline · Image-based rollback · Zero-mutation policy</p>
</header>

<main>
  <!-- Stats -->
  <div class="status-bar">
    <div class="stat-card">
      <div class="label">Active Slot</div>
      <div class="value" id="stat-slot">—</div>
      <div class="sub">Receiving 100% of traffic</div>
    </div>
    <div class="stat-card">
      <div class="label">Active Image</div>
      <div class="value" style="font-size:1.1rem;margin-top:8px" id="stat-image">—</div>
      <div class="sub" id="stat-sha">SHA: —</div>
    </div>
    <div class="stat-card">
      <div class="label">Deploy Switches</div>
      <div class="value" id="stat-switches">0</div>
      <div class="sub">Since proxy start</div>
    </div>
    <div class="stat-card">
      <div class="label">Both Upstreams</div>
      <div class="value" style="font-size:1.1rem;margin-top:8px" id="stat-health">Checking…</div>
      <div class="sub">Health gated before switch</div>
    </div>
  </div>

  <!-- Deployment Slots -->
  <div class="slot-grid" id="slot-grid">
    <div class="slot active" id="slot-blue">
      <div class="slot-header">
        <span class="slot-name">🔵 Blue Slot (v1.0.0)</span>
        <span class="slot-badge badge-active" id="badge-blue">ACTIVE</span>
      </div>
      <div class="slot-info" id="info-blue"><p>Loading…</p></div>
    </div>
    <div class="slot inactive" id="slot-green">
      <div class="slot-header">
        <span class="slot-name">🟢 Green Slot (v2.0.0)</span>
        <span class="slot-badge badge-inactive" id="badge-green">STANDBY</span>
      </div>
      <div class="slot-info" id="info-green"><p>Loading…</p></div>
    </div>
  </div>

  <!-- Controls -->
  <div class="controls">
    <h2>⚡ Pipeline Controls</h2>
    <div class="btn-row">
      <button class="btn-green" onclick="runPipeline('green')">▶ Deploy v2 → Green (Simulate Bake + Switch)</button>
      <button class="btn-orange" onclick="runPipeline('blue')">⏪ Rollback → Blue (v1)</button>
      <button class="btn-gray btn-sm" onclick="callApi()">🔁 Call Active API</button>
      <button class="btn-red btn-sm" onclick="tryMutate()">🚫 Try Mutate Instance</button>
      <button class="btn-gray btn-sm" onclick="refresh()">⟳ Refresh</button>
    </div>
  </div>

  <!-- Pipeline stages -->
  <div class="pipeline">
    <h2>📦 Image Build Pipeline</h2>
    <div class="stages" id="pipeline-stages">
      <div class="stage done" id="stage-commit">
        <div class="stage-icon">📝</div>
        <div class="stage-label">Commit</div>
      </div>
      <div class="stage-arrow done" id="arrow-1"></div>
      <div class="stage done" id="stage-bake">
        <div class="stage-icon">🔨</div>
        <div class="stage-label">Bake Image</div>
      </div>
      <div class="stage-arrow done" id="arrow-2"></div>
      <div class="stage done" id="stage-scan">
        <div class="stage-icon">🔍</div>
        <div class="stage-label">Scan / Test</div>
      </div>
      <div class="stage-arrow done" id="arrow-3"></div>
      <div class="stage done" id="stage-promote">
        <div class="stage-icon">✅</div>
        <div class="stage-label">Promote</div>
      </div>
      <div class="stage-arrow done" id="arrow-4"></div>
      <div class="stage done" id="stage-launch">
        <div class="stage-icon">🚀</div>
        <div class="stage-label">Launch New</div>
      </div>
      <div class="stage-arrow done" id="arrow-5"></div>
      <div class="stage done" id="stage-switch">
        <div class="stage-icon">🔀</div>
        <div class="stage-label">Switch Traffic</div>
      </div>
      <div class="stage-arrow done" id="arrow-6"></div>
      <div class="stage done" id="stage-terminate">
        <div class="stage-icon">🗑️</div>
        <div class="stage-label">Terminate Old</div>
      </div>
    </div>
  </div>

  <!-- Event log -->
  <div class="log-panel">
    <h2>Event Log</h2>
    <div id="log-entries"></div>
  </div>

  <!-- Image diff -->
  <div class="diff">
    <h2>🔬 Image Manifest Diff (v1.0.0 → v2.0.0)</h2>
    <table class="diff-table">
      <thead><tr><th>Property</th><th>v1.0.0 (Blue)</th><th>v2.0.0 (Green)</th><th>Status</th></tr></thead>
      <tbody id="diff-body"></tbody>
    </table>
  </div>
</main>

<div class="toast" id="toast"></div>

<script>
const PROXY = 'http://localhost:3000';
const logEl = document.getElementById('log-entries');
let logCount = 0;

function ts() { return new Date().toLocaleTimeString(); }
function log(msg, type='info') {
  logCount++;
  const cls = type === 'ok' ? 'msg-ok' : type === 'warn' ? 'msg-warn' : type === 'err' ? 'msg-err' : 'msg-info';
  logEl.innerHTML += `<div class="log-entry"><span class="ts">[${ts()}]</span> <span class="${cls}">${msg}</span></div>`;
  logEl.parentElement.scrollTop = logEl.parentElement.scrollHeight;
}
function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg; t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2800);
}

function renderSlotInfo(el, data) {
  if (!data) { el.innerHTML = '<p style="color:#94a3b8">Offline</p>'; return; }
  const featureHtml = (data.features || []).map(f => `<span class="feature">${f}</span>`).join('');
  el.innerHTML = `
    <div class="slot-info">
      <p>Image: <span>${data.image}</span></p>
      <p>SHA: <span style="font-family:monospace;font-size:0.78rem">${data.imageSha}</span></p>
      <p>Instance: <span style="font-family:monospace;font-size:0.78rem">${(data.instanceId||'').slice(0,18)}…</span></p>
      <p>Uptime: <span>${data.uptimeSeconds}s</span></p>
      <p>Mutable Patch Applied: <span style="color:${data.mutablePatch?'#dc2626':'#16a34a'}">${data.mutablePatch ? '⚠ YES' : '✓ Never'}</span></p>
      <div class="feature-list">${featureHtml}</div>
    </div>`;
}

function renderDiff(blueData, greenData) {
  if (!blueData || !greenData) return;
  const rows = [
    ['version', blueData.version, greenData.version],
    ['image', blueData.image, greenData.image],
    ['imageSha', blueData.imageSha, greenData.imageSha],
    ['net.core.somaxconn', blueData.sysctls?.['net.core.somaxconn'], greenData.sysctls?.['net.core.somaxconn']],
    ['vm.swappiness', blueData.sysctls?.['vm.swappiness'], greenData.sysctls?.['vm.swappiness']],
    ['net.ipv4.tcp_tw_reuse', blueData.sysctls?.['net.ipv4.tcp_tw_reuse'] || '—', greenData.sysctls?.['net.ipv4.tcp_tw_reuse'] || '1 (NEW)'],
    ['features count', blueData.features?.length, greenData.features?.length],
    ['mutablePatch', String(blueData.mutablePatch), String(greenData.mutablePatch)],
  ];
  const tbody = document.getElementById('diff-body');
  tbody.innerHTML = rows.map(([prop, v1, v2]) => {
    const same = String(v1) === String(v2);
    const isNew = v1 === '—';
    const cls = same ? 'diff-same' : 'diff-change';
    const pill = same ? '<span class="pill-same">same</span>' : isNew ? '<span class="pill-new">new</span>' : '<span class="pill-changed">changed</span>';
    return `<tr><td style="font-family:monospace;font-size:0.8rem">${prop}</td><td class="diff-same">${v1}</td><td class="${cls}">${v2}</td><td>${pill}</td></tr>`;
  }).join('');
}

async function fetchInfo(url) {
  try {
    const r = await fetch(url);
    return r.ok ? r.json() : null;
  } catch { return null; }
}

let blueData = null, greenData = null;

async function refresh() {
  try {
    const status = await fetchInfo(`${PROXY}/proxy/status`);
    const health = await fetchInfo(`${PROXY}/proxy/health-check`);

    if (status) {
      const switchCount = (status.deployHistory || []).filter(e => e.event === 'traffic_switch').length;
      document.getElementById('stat-slot').textContent = status.active.toUpperCase();
      document.getElementById('stat-switches').textContent = switchCount;

      const slotBlue  = document.getElementById('slot-blue');
      const slotGreen = document.getElementById('slot-green');
      const badgeBlue  = document.getElementById('badge-blue');
      const badgeGreen = document.getElementById('badge-green');

      if (status.active === 'blue') {
        slotBlue.className  = 'slot active';  badgeBlue.className  = 'slot-badge badge-active'; badgeBlue.textContent  = 'ACTIVE';
        slotGreen.className = 'slot inactive'; badgeGreen.className = 'slot-badge badge-inactive'; badgeGreen.textContent = 'STANDBY';
      } else {
        slotGreen.className = 'slot active';  badgeGreen.className = 'slot-badge badge-active'; badgeGreen.textContent = 'ACTIVE';
        slotBlue.className  = 'slot inactive'; badgeBlue.className  = 'slot-badge badge-inactive'; badgeBlue.textContent  = 'STANDBY';
      }
    }

    if (health) {
      const bothOk = health.blue?.healthy && health.green?.healthy;
      document.getElementById('stat-health').textContent = bothOk ? '✓ Both Healthy' : '⚠ Degraded';
      document.getElementById('stat-health').style.color = bothOk ? '#16a34a' : '#d97706';
    }

    // Fetch slot info direct (bypasses proxy)
    blueData  = await fetchInfo('http://localhost:3001/api/info');
    greenData = await fetchInfo('http://localhost:3002/api/info');
    renderSlotInfo(document.getElementById('info-blue'),  blueData);
    renderSlotInfo(document.getElementById('info-green'), greenData);

    const active = status?.active === 'blue' ? blueData : greenData;
    if (active) {
      document.getElementById('stat-image').textContent = active.image;
      document.getElementById('stat-sha').textContent   = `SHA: ${active.imageSha}`;
    }

    renderDiff(blueData, greenData);
  } catch(e) {
    log(`Refresh error: ${e.message}`, 'err');
  }
}

const STAGES = ['commit','bake','scan','promote','launch','switch','terminate'];
const STAGE_LABELS = ['📝 Commit detected','🔨 Baking image…','🔍 Scanning + testing…','✅ Promoting to registry…','🚀 Launching new instance…','🔀 Switching traffic…','🗑️ Terminating old instance…'];
const STAGE_DELAYS = [300, 1200, 1400, 800, 900, 600, 700];

async function animatePipeline(targetSlot) {
  // Reset all
  STAGES.forEach(s => { document.getElementById(`stage-${s}`).className = 'stage'; });
  for (let i = 1; i <= 6; i++) document.getElementById(`arrow-${i}`).className = 'stage-arrow';

  for (let i = 0; i < STAGES.length; i++) {
    const stageEl = document.getElementById(`stage-${STAGES[i]}`);
    stageEl.className = 'stage active';
    log(STAGE_LABELS[i]);
    await new Promise(r => setTimeout(r, STAGE_DELAYS[i]));
    stageEl.className = 'stage done';
    if (i < 6) document.getElementById(`arrow-${i+1}`).className = 'stage-arrow done';

    // Actual switch at stage 5
    if (i === 5) {
      try {
        const resp = await fetch(`${PROXY}/proxy/switch`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ target: targetSlot, reason: 'pipeline_deploy' }),
        });
        const data = await resp.json();
        if (data.success) {
          log(`Traffic switched → ${targetSlot.toUpperCase()}`, 'ok');
        } else {
          log(`Switch failed: ${data.error}`, 'err');
        }
      } catch(e) { log(`Switch error: ${e.message}`, 'err'); }
    }
  }
  log(`✓ Deployment complete → ${targetSlot.toUpperCase()} is live`, 'ok');
  toast(`✓ Deployed to ${targetSlot} slot`);
  await refresh();
}

async function runPipeline(target) {
  log(`--- Pipeline triggered: deploy to ${target.toUpperCase()} ---`, 'warn');
  await animatePipeline(target);
}

async function callApi() {
  try {
    log('Calling /api/data via proxy (active upstream)…');
    const r = await fetch(`${PROXY}/api/data`);
    const data = await r.json();
    log(`Response: ${JSON.stringify(data.message)} (${data.items?.length} items)`, 'ok');
    toast('API call successful');
  } catch(e) { log(`API call failed: ${e.message}`, 'err'); }
}

async function tryMutate() {
  try {
    log('Attempting POST /admin/mutate on active instance…', 'warn');
    const r = await fetch(`${PROXY}/api/../admin/mutate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    const data = await r.json();
    if (data.error) {
      log(`✓ Mutation rejected: ${data.error}`, 'ok');
      toast('✓ Mutation blocked by immutability policy');
    }
  } catch(e) {
    log(`Mutation attempt result: ${e.message}`, 'warn');
    toast('Mutation blocked (connection or policy)');
  }
}

// Auto-refresh
refresh();
log('Dashboard connected. Blue slot (v1.0.0) is live.');
log('Click "Deploy v2" to simulate a full image-bake pipeline and blue-green switch.');
setInterval(refresh, 8000);
setTimeout(refresh, 2000);
setTimeout(refresh, 5000);
</script>
</body>
</html>
HTMLEOF

cat > "$DEMO_DIR/dashboard/Dockerfile" << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
COPY public ./public
EXPOSE 8080
CMD ["node", "server.js"]
EOF

# =============================================================================
# DOCKER COMPOSE
# =============================================================================
log "Writing docker-compose.yml..."

cat > "$DEMO_DIR/docker-compose.yml" << EOF
services:
  api-v1:
    build:
      context: ./v1-app
      args:
        IMAGE_ID: "api:v1.0.0"
        IMAGE_SHA: "sha256:a1b2c3d4e5f6"
        BUILD_TIME: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    container_name: immutable-api-v1
    ports:
      - "${BLUE_PORT}:3001"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3001/health"]
      interval: 5s
      timeout: 3s
      retries: 5

  api-v2:
    build:
      context: ./v2-app
      args:
        IMAGE_ID: "api:v2.0.0"
        IMAGE_SHA: "sha256:b2c3d4e5f6a1"
        BUILD_TIME: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    container_name: immutable-api-v2
    ports:
      - "${GREEN_PORT}:3002"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3002/health"]
      interval: 5s
      timeout: 3s
      retries: 5

  proxy:
    build: ./proxy
    container_name: immutable-proxy
    ports:
      - "${PROXY_PORT}:3000"
    depends_on:
      api-v1:
        condition: service_healthy
      api-v2:
        condition: service_healthy
    restart: unless-stopped

  dashboard:
    build: ./dashboard
    container_name: immutable-dashboard
    ports:
      - "8080:8080"
    depends_on:
      - proxy
    restart: unless-stopped
EOF

# =============================================================================
# TESTS
# =============================================================================
log "Writing tests..."
cat > "$DEMO_DIR/tests/test.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
assert_contains() { echo "$1" | grep -q "$2" && ok "$3" || fail "$3 (got: $1)"; }

echo ""
echo "══════════════════════════════════════"
echo "  Immutable Infrastructure Test Suite"
echo "══════════════════════════════════════"

echo ""
echo "1. Health checks"
HB=$(curl -sf http://localhost:3001/health) && assert_contains "$HB" "healthy" "v1 health" || fail "v1 health unreachable"
HG=$(curl -sf http://localhost:3002/health) && assert_contains "$HG" "healthy" "v2 health" || fail "v2 health unreachable"

echo ""
echo "2. Image metadata baked correctly"
V1=$(curl -sf http://localhost:3001/api/info)
V2=$(curl -sf http://localhost:3002/api/info)
assert_contains "$V1" "v1.0.0"     "v1 version baked"
assert_contains "$V1" "a1b2c3d4"   "v1 SHA baked"
assert_contains "$V2" "v2.0.0"     "v2 version baked"
assert_contains "$V2" "b2c3d4e5"   "v2 SHA baked"
assert_contains "$V1" '"mutablePatch":false' "v1 not mutated"
assert_contains "$V2" '"mutablePatch":false' "v2 not mutated"

echo ""
echo "3. Mutation rejection (immutability policy)"
# Use curl -s without -f so we get the 403 response body
MUT=$(curl -s -X POST http://localhost:3001/admin/mutate -H 'Content-Type: application/json' -d '{}')
assert_contains "$MUT" "Mutation rejected" "v1 blocks mutation"
MUT2=$(curl -s -X POST http://localhost:3002/admin/mutate -H 'Content-Type: application/json' -d '{}')
assert_contains "$MUT2" "Mutation rejected" "v2 blocks mutation"

echo ""
echo "4. Proxy traffic switch"
# Switch to green
SW=$(curl -sf -X POST http://localhost:3000/proxy/switch -H 'Content-Type: application/json' -d '{"target":"green"}')
assert_contains "$SW" '"success":true' "switch to green succeeds"
ST=$(curl -sf http://localhost:3000/proxy/status)
assert_contains "$ST" '"active":"green"' "active is green after switch"

# Switch back to blue
SW2=$(curl -sf -X POST http://localhost:3000/proxy/switch -H 'Content-Type: application/json' -d '{"target":"blue"}')
assert_contains "$SW2" '"success":true' "rollback to blue succeeds"
ST2=$(curl -sf http://localhost:3000/proxy/status)
assert_contains "$ST2" '"active":"blue"' "active is blue after rollback"

echo ""
echo "5. Active API call routes to correct upstream"
API=$(curl -sf http://localhost:3000/api/data)
assert_contains "$API" "v1" "proxy routes to blue v1"

echo ""
echo "6. Image feature diff"
assert_contains "$V1" "basic-auth"        "v1 has basic-auth"
assert_contains "$V2" "circuit-breaker"   "v2 has circuit-breaker (new feature)"
assert_contains "$V2" "distributed-tracing" "v2 has distributed-tracing"

echo ""
echo "7. Sysctl tuning diff"
assert_contains "$V2" "tcp_tw_reuse" "v2 has new sysctl (net.ipv4.tcp_tw_reuse)"

echo ""
echo "══════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
EOF
chmod +x "$DEMO_DIR/tests/test.sh"

# =============================================================================
# DEMO + CLEANUP SCRIPTS
# =============================================================================
cat > "$DEMO_DIR/demo.sh" << 'EOF'
#!/bin/bash
echo ""
echo "════════════════════════════════════════════════════"
echo "  Immutable Infrastructure — Interactive Demo"
echo "════════════════════════════════════════════════════"
echo ""
echo "  Dashboard:  http://localhost:8080"
echo "  Proxy API:  http://localhost:3000/api/info"
echo "  Blue  (v1): http://localhost:3001/api/info"
echo "  Green (v2): http://localhost:3002/api/info"
echo ""
echo "  Try these commands:"
echo ""
echo "  1. Switch traffic to Green (v2):"
echo "     curl -X POST http://localhost:3000/proxy/switch \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"target\":\"green\"}'"
echo ""
echo "  2. Rollback to Blue (v1):"
echo "     curl -X POST http://localhost:3000/proxy/switch \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"target\":\"blue\"}'"
echo ""
echo "  3. Attempt mutation (should be rejected):"
echo "     curl -X POST http://localhost:3001/admin/mutate \\"
echo "       -H 'Content-Type: application/json' -d '{}'"
echo ""
echo "  4. Call active upstream via proxy:"
echo "     curl http://localhost:3000/api/data"
echo ""
echo "  Open the dashboard and click:"
echo "  → 'Deploy v2' to animate the full pipeline"
echo "  → 'Rollback' to see atomic traffic pointer revert"
echo "  → 'Try Mutate Instance' to see rejection"
echo ""
EOF
chmod +x "$DEMO_DIR/demo.sh"

cat > "$DEMO_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
echo "Stopping and removing containers, images, volumes..."
cd "$(dirname "$0")"
docker compose down -v --rmi local 2>/dev/null || true
echo "✓ Cleanup complete"
EOF
chmod +x "$DEMO_DIR/cleanup.sh"

# =============================================================================
# BUILD + START
# =============================================================================
section "Building Docker Images"
cd "$DEMO_DIR"
docker compose build --no-cache 2>&1 | while IFS= read -r line; do echo "  $line"; done
ok "All images built"

section "Starting Services"
docker compose up -d
log "Waiting for health checks..."
sleep 8

# Verify all containers running
for svc in immutable-api-v1 immutable-api-v2 immutable-proxy immutable-dashboard; do
  STATUS=$(docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null || echo "missing")
  [ "$STATUS" = "running" ] && ok "$svc is running" || warn "$svc status: $STATUS"
done

# =============================================================================
# TESTS
# =============================================================================
section "Running Test Suite"
sleep 4
bash "$DEMO_DIR/tests/test.sh"

# =============================================================================
# DONE
# =============================================================================
section "Demo Ready"
bash "$DEMO_DIR/demo.sh"
echo ""
echo -e "${BOLD}${GREEN}  ✓ Setup complete!${NC}"
echo -e "  ${CYAN}Open your browser:${NC} ${BOLD}http://localhost:8080${NC}"
echo ""
echo -e "  To clean up:   ${YELLOW}bash $DEMO_DIR/cleanup.sh${NC}"
echo ""