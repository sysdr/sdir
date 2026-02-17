/**
 * tests/fleet.test.js — Fleet engine unit tests
 * Run: node tests/fleet.test.js
 */

const { FleetEngine, INSTANCE_CATALOG, SAVINGS_PLAN_DISCOUNT } = require('../src/fleet');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) {
    console.log(`  ✓ ${msg}`);
    passed++;
  } else {
    console.error(`  ✗ FAIL: ${msg}`);
    failed++;
  }
}

function assertEqual(a, b, msg) {
  assert(a === b, `${msg} (expected ${b}, got ${a})`);
}

// ---------------------------------------------------------------------------
console.log('\n── Test Suite: FleetEngine ──\n');

// Test 1: Initial fleet composition
console.log('1. Fleet initialization');
const engine = new FleetEngine({ reservedCount: 4, onDemandCount: 2, spotCount: 6 });
const snap = engine.getSnapshot();
assertEqual(snap.metrics.reservedCount, 4, 'Reserved count matches config');
assertEqual(snap.metrics.onDemandCount, 2, 'On-Demand count matches config');
assertEqual(snap.metrics.spotCount, 6,     'Spot count matches config');
assertEqual(snap.metrics.activeCount, 12,  'Total active count is correct');

// Test 2: Cost calculation — Reserved cheaper than On-Demand
console.log('\n2. Cost calculation');
const reserved  = snap.instances.filter(i => i.type === 'RESERVED')[0];
const ondemand  = snap.instances.filter(i => i.type === 'ON_DEMAND')[0];
assert(reserved.effectiveHr < reserved.onDemandHr, 'Reserved instance costs less than On-Demand rate');
assert(ondemand.effectiveHr === ondemand.onDemandHr, 'On-Demand instance costs full list price');
assert(reserved.savingsPercent > 50, `Reserved savings > 50% (got ${reserved.savingsPercent}%)`);

// Test 3: Spot cheaper than On-Demand
console.log('\n3. Spot pricing');
const spot = snap.instances.filter(i => i.type === 'SPOT')[0];
assert(spot.effectiveHr < spot.onDemandHr, 'Spot instance costs less than On-Demand rate');
assert(spot.savingsPercent > 60, `Spot savings > 60% (got ${spot.savingsPercent}%)`);

// Test 4: Overall savings
console.log('\n4. Fleet savings');
assert(snap.metrics.savingsPercent > 0, 'Mixed fleet has positive overall savings');
assert(snap.metrics.totalEffectiveHr < snap.metrics.totalOnDemandHr, 'Mixed fleet total cost < all-On-Demand cost');

// Test 5: Force interruption
console.log('\n5. Spot interruption');
let interrupted = null;
engine.on('interrupt', (inst) => { interrupted = inst; });
const result = engine.forceInterrupt();
assert(result.ok, 'forceInterrupt returns ok:true');
assert(result.instanceId !== undefined, 'Returns instanceId');
assert(interrupted !== null, 'Interrupt event was emitted');
assert(interrupted.type === 'SPOT', 'Interrupted instance is SPOT type');
assert(interrupted.state === 'INTERRUPT_NOTICE', 'State is INTERRUPT_NOTICE');

// Test 6: Instance catalog integrity
console.log('\n6. Instance catalog');
assert(INSTANCE_CATALOG.length >= 4, `Catalog has >= 4 instance types (got ${INSTANCE_CATALOG.length})`);
for (const c of INSTANCE_CATALOG) {
  assert(c.onDemandHr > 0, `${c.family}: onDemandHr > 0`);
  assert(c.spotMultiplier > 0 && c.spotMultiplier < 1, `${c.family}: spotMultiplier in range`);
}

// Test 7: Savings Plan constant
console.log('\n7. Savings Plan discount');
assert(SAVINGS_PLAN_DISCOUNT > 0.4 && SAVINGS_PLAN_DISCOUNT < 0.8, 
  `Savings Plan discount in realistic range: ${(SAVINGS_PLAN_DISCOUNT * 100).toFixed(0)}%`);

// Test 8: Fleet adjustment
console.log('\n8. Fleet adjustment');
engine.adjustFleet({ spotDelta: 2 });
const snap2 = engine.getSnapshot();
assert(snap2.metrics.spotCount >= snap.metrics.spotCount + 2, 'Adding Spot instances increases count');

engine.adjustFleet({ spotDelta: -1 });
const snap3 = engine.getSnapshot();
assert(snap3.metrics.spotCount <= snap2.metrics.spotCount, 'Removing Spot instances decreases count');

// Test 9: No On-Demand interruption possible
console.log('\n9. On-Demand interruption immunity');
engine.adjustFleet({ reservedDelta: 0, spotDelta: -100, onDemandDelta: 0 }); // remove all spot
const snap4 = engine.getSnapshot();
const noSpot = engine.forceInterrupt();
assert(!noSpot.ok, 'forceInterrupt returns ok:false when no Spot instances present');

// ---------------------------------------------------------------------------
console.log(`\n── Results: ${passed} passed, ${failed} failed ──\n`);
process.exit(failed > 0 ? 1 : 0);
