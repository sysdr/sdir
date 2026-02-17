'use strict';

const http = require('http');

const API_HOST = process.env.API_HOST || 'localhost';
const API_PORT = parseInt(process.env.API_PORT || '3001');

let passed = 0; let failed = 0;

function req(path) {
  return new Promise((resolve, reject) => {
    http.get({ host: API_HOST, port: API_PORT, path }, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(body), headers: res.headers }); }
        catch(e) { resolve({ status: res.statusCode, body: body, headers: res.headers }); }
      });
    }).on('error', reject);
  });
}

async function test(name, fn) {
  try {
    await fn();
    console.log(`  ✔  ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ✖  ${name}: ${e.message}`);
    failed++;
  }
}

function assert(cond, msg) { if (!cond) throw new Error(msg); }

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function run() {
  console.log('\n[Tests] Running integration tests against API...\n');

  await test('Health endpoint returns ok', async () => {
    const r = await req('/health');
    assert(r.status === 200, `status ${r.status}`);
    assert(r.body.status === 'ok', 'body.status should be ok');
  });

  await test('Unknown tenant returns 400', async () => {
    const r = await req('/api/data?tenant=unknown-tenant');
    assert(r.status === 400, `expected 400, got ${r.status}`);
  });

  await test('Missing tenant param returns 400', async () => {
    const r = await req('/api/data');
    assert(r.status === 400, `expected 400, got ${r.status}`);
  });

  await test('Enterprise tenant gets 200 on first request', async () => {
    const r = await req('/api/data?tenant=tenant-enterprise');
    assert(r.status === 200, `expected 200, got ${r.status}`);
    assert(r.body.tier === 'Enterprise', 'tier should be Enterprise');
  });

  await test('Pro tenant gets 200 on first request', async () => {
    const r = await req('/api/data?tenant=tenant-pro');
    assert(r.status === 200, `expected 200, got ${r.status}`);
    assert(r.body.tier === 'Pro', 'tier should be Pro');
  });

  await test('Free tenant gets 200 initially', async () => {
    const r = await req('/api/data?tenant=tenant-free');
    assert(r.status === 200, `expected 200, got ${r.status}`);
    assert(r.body.tier === 'Free', 'tier should be Free');
  });

  await test('Free tenant throttled after exceeding burst (20 rapid requests)', async () => {
    // Drain the free tenant's bucket with 25 rapid requests
    let throttled = 0;
    const promises = [];
    for (let i = 0; i < 25; i++) {
      promises.push(req('/api/data?tenant=tenant-free'));
    }
    const results = await Promise.all(promises);
    throttled = results.filter(r => r.status === 429).length;
    assert(throttled > 0, `expected at least 1 throttle in 25 rapid requests, got ${throttled}`);
  });

  await test('Throttled response includes Retry-After header', async () => {
    // Spam to ensure throttle
    let r;
    for (let i = 0; i < 30; i++) {
      r = await req('/api/data?tenant=tenant-free');
      if (r.status === 429) break;
    }
    if (r.status === 429) {
      assert(r.headers['retry-after'], 'should have Retry-After header');
      assert(r.body.retryAfterMs > 0, 'retryAfterMs should be positive');
    }
  });

  await test('Metrics endpoint returns all tenants', async () => {
    const r = await req('/metrics');
    assert(r.status === 200, `status ${r.status}`);
    assert(r.body['tenant-free'], 'missing tenant-free');
    assert(r.body['tenant-pro'], 'missing tenant-pro');
    assert(r.body['tenant-enterprise'], 'missing tenant-enterprise');
  });

  await test('Enterprise tenant unaffected while free tenant throttled', async () => {
    // Slam free tier
    const freePromises = Array(25).fill(null).map(() => req('/api/data?tenant=tenant-free'));
    await Promise.all(freePromises);
    // Enterprise should still get 200
    const r = await req('/api/data?tenant=tenant-enterprise');
    assert(r.status === 200, `Enterprise got ${r.status} — isolation failed`);
  });

  console.log(`\n  Results: ${passed} passed, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

// Wait for API to be ready
async function waitForApi(maxRetries = 20) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      await req('/health');
      return true;
    } catch {
      await sleep(1000);
    }
  }
  throw new Error('API did not become ready');
}

waitForApi().then(run).catch(e => { console.error('[Tests] Error:', e.message); process.exit(1); });
