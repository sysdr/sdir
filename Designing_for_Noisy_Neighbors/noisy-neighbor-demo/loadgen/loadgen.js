'use strict';
const http = require('http');

const API_HOST = process.env.API_HOST || 'api';
const API_PORT = parseInt(process.env.API_PORT || '3001');

// ─── Load profiles: send at rates that create interesting throttle patterns
// FREE:       30 req/s  → 3x over limit  (noisy neighbor scenario)
// PRO:        120 req/s → 1.2x over limit (occasional throttle)
// ENTERPRISE: 300 req/s → well under limit (never throttled)
const TENANTS = [
  { id: 'tenant-free',       rps: 30,  label: 'FREE (3x noisy)' },
  { id: 'tenant-pro',        rps: 120, label: 'PRO  (1.2x burst)' },
  { id: 'tenant-enterprise', rps: 300, label: 'ENT  (0.6x normal)' }
];

let counters = {};
for (const t of TENANTS) counters[t.id] = { sent: 0, ok: 0, throttled: 0, err: 0 };

function request(tenant) {
  return new Promise((resolve) => {
    const path = `/api/data?tenant=${tenant}`;
    const req = http.get({ host: API_HOST, port: API_PORT, path }, (res) => {
      res.resume();
      resolve(res.statusCode);
    });
    req.on('error', () => resolve(0));
    req.setTimeout(2000, () => { req.destroy(); resolve(0); });
  });
}

// Start load for each tenant
for (const tenant of TENANTS) {
  const intervalMs = 1000 / tenant.rps;
  setInterval(async () => {
    counters[tenant.id].sent++;
    const code = await request(tenant.id);
    if (code === 200)      counters[tenant.id].ok++;
    else if (code === 429) counters[tenant.id].throttled++;
    else                   counters[tenant.id].err++;
  }, intervalMs);
}

// Print stats every 5 seconds
let startTime = Date.now();
setInterval(() => {
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
  console.log(`\n[+${elapsed}s] Load Generator Status`);
  console.log('─'.repeat(55));
  for (const tenant of TENANTS) {
    const c = counters[tenant.id];
    const total = c.ok + c.throttled;
    const tRate = total > 0 ? Math.round((c.throttled / total) * 100) : 0;
    console.log(
      `  ${tenant.label.padEnd(22)} ` +
      `✓ ${String(c.ok).padStart(5)}  ✗ ${String(c.throttled).padStart(5)}  ` +
      `throttle: ${String(tRate).padStart(3)}%`
    );
  }
}, 5000);

console.log('[LoadGen] Starting multi-tenant load simulation...');
console.log('[LoadGen] Dashboard: http://localhost:3001\n');
for (const t of TENANTS) {
  console.log(`  • ${t.label} @ ${t.rps} req/s`);
}
