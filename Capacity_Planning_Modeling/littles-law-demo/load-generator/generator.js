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
