'use strict';

const http = require('http');

let passed = 0;
let failed = 0;

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost',
      port: 3000,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
      },
    };
    const r = http.request(opts, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(d) }); }
        catch(e) { resolve({ status: res.statusCode, body: d }); }
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

async function test(name, fn) {
  try {
    await fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ❌ ${name}: ${e.message}`);
    failed++;
  }
}

function assert(condition, msg) {
  if (!condition) throw new Error(msg || 'Assertion failed');
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function runTests() {
  console.log('\n🔐 Vault Secrets Demo — Test Suite\n');

  // Wait for server to initialize
  console.log('⏳ Waiting for Vault initialization (15s)...');
  await sleep(15000);

  await test('GET /api/status returns vault status', async () => {
    const r = await req('GET', '/api/status');
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
    assert(typeof r.body.vault === 'object', 'Expected vault object');
  });

  await test('GET /api/secrets returns seeded KV secrets', async () => {
    const r = await req('GET', '/api/secrets');
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
    assert(Array.isArray(r.body.secrets), 'Expected secrets array');
    assert(r.body.secrets.length >= 3, `Expected >=3 secrets, got ${r.body.secrets.length}`);
  });

  await test('POST /api/secrets writes a new KV secret', async () => {
    const r = await req('POST', '/api/secrets', { path: 'app/test', key: 'test_key', value: 'test_value' });
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
  });

  await test('POST /api/creds/dynamic issues dynamic DB credentials', async () => {
    const r = await req('POST', '/api/creds/dynamic', { role: 'app-role' });
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, `Expected ok=true, got: ${JSON.stringify(r.body)}`);
    assert(typeof r.body.username === 'string', 'Expected username string');
    assert(typeof r.body.password === 'string', 'Expected password string');
    assert(r.body.username.startsWith('v-'), `Expected vault username prefix, got ${r.body.username}`);
    assert(r.body.ttlSeconds > 0, 'Expected positive TTL');

    // Store for verification test
    process.env._TEST_USER = r.body.username;
    process.env._TEST_PASS = r.body.password;
    process.env._TEST_LEASE = r.body.id;
  });

  await test('POST /api/verify-cred verifies dynamic credential against PostgreSQL', async () => {
    const username = process.env._TEST_USER;
    const password = process.env._TEST_PASS;
    if (!username) throw new Error('No test credential available');
    const r = await req('POST', '/api/verify-cred', { username, password });
    assert(r.body.ok === true, `Credential verification failed: ${r.body.error}`);
    assert(r.body.currentUser === username, `Expected currentUser=${username}, got ${r.body.currentUser}`);
  });

  await test('GET /api/leases lists active leases', async () => {
    const r = await req('GET', '/api/leases');
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
    assert(Array.isArray(r.body.leases), 'Expected leases array');
    assert(r.body.leases.length >= 1, `Expected >=1 lease, got ${r.body.leases.length}`);
  });

  await test('POST /api/rotate rotates a KV secret value', async () => {
    const r = await req('POST', '/api/rotate', { path: 'app/test', key: 'test_key' });
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
    assert(Number.isInteger(r.body.newVersion) && r.body.newVersion >= 2, `Expected newVersion >= 2, got ${r.body.newVersion}`);
  });

  await test('DELETE /api/creds/:id revokes a lease', async () => {
    const id = process.env._TEST_LEASE;
    if (!id) throw new Error('No test lease available');
    const r = await req('DELETE', `/api/creds/${id}`);
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(r.body.ok === true, 'Expected ok=true');
  });

  await test('GET /api/audit returns audit events', async () => {
    const r = await req('GET', '/api/audit');
    assert(r.status === 200, `Expected 200, got ${r.status}`);
    assert(Array.isArray(r.body.events), 'Expected events array');
    assert(r.body.events.length > 0, 'Expected at least 1 audit event');
  });

  const total = passed + failed;
  console.log(`\n${'─'.repeat(40)}`);
  console.log(`Tests: ${total} | ✅ ${passed} passed | ❌ ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => { console.error('Test runner error:', e); process.exit(1); });
