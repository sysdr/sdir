/**
 * fleet.js — Mixed-capacity fleet simulation engine
 *
 * Models three purchasing types:
 *   RESERVED  — 1-yr Savings Plan, 57% off On-Demand, never interrupted
 *   ON_DEMAND  — List price, never interrupted, spun up for burst
 *   SPOT       — 70–85% off On-Demand, can receive 2-minute interruption notice
 *
 * Spot interruption lifecycle:
 *   RUNNING → INTERRUPT_NOTICE (T-2min) → DRAINING → TERMINATED → REPLACED
 */

const { v4: uuidv4 } = require('uuid');
const EventEmitter    = require('events');

// ---------------------------------------------------------------------------
// Pricing model — directional, based on public AWS us-east-1 rates (Jan 2025)
// Verify current rates at https://aws.amazon.com/ec2/pricing/
// ---------------------------------------------------------------------------
const INSTANCE_CATALOG = [
  { family: 'm7g.2xlarge', vcpu: 8,  ram: 32, onDemandHr: 0.3392, spotMultiplier: 0.18, graviton: true },
  { family: 'c5.2xlarge',  vcpu: 8,  ram: 16, onDemandHr: 0.3400, spotMultiplier: 0.22, graviton: false },
  { family: 'm5.2xlarge',  vcpu: 8,  ram: 32, onDemandHr: 0.3840, spotMultiplier: 0.20, graviton: false },
  { family: 'r5.xlarge',   vcpu: 4,  ram: 32, onDemandHr: 0.2520, spotMultiplier: 0.17, graviton: false },
  { family: 'm6i.2xlarge', vcpu: 8,  ram: 32, onDemandHr: 0.3840, spotMultiplier: 0.21, graviton: false },
  { family: 'c6i.2xlarge', vcpu: 8,  ram: 16, onDemandHr: 0.3400, spotMultiplier: 0.19, graviton: false },
];

// Savings Plan discount applied to Reserved-type instances
const SAVINGS_PLAN_DISCOUNT = 0.57;

// Availability Zones for capacity diversification
const AZS = ['us-east-1a', 'us-east-1b', 'us-east-1c'];

// Spot interruption probability per simulation tick (realistic ~3% hourly → per-tick fraction)
const SPOT_INTERRUPT_PROBABILITY = 0.004; // ~1.4% per 30s tick → ~2-3% per hour

class Instance {
  constructor({ type, catalog, az }) {
    this.id     = `i-${uuidv4().slice(0, 8)}`;
    this.type   = type;          // 'RESERVED' | 'ON_DEMAND' | 'SPOT'
    this.family = catalog.family;
    this.vcpu   = catalog.vcpu;
    this.ram    = catalog.ram;
    this.az     = az;
    this.state  = 'RUNNING';     // RUNNING | INTERRUPT_NOTICE | DRAINING | TERMINATED
    this.launchedAt = Date.now();
    this.drainStartedAt = null;
    this.terminatedAt   = null;
    this.drainProgress  = 0;     // 0–100% — percent of 120s drain window elapsed

    // Effective hourly cost
    this.onDemandHr = catalog.onDemandHr;
    if (type === 'RESERVED') {
      this.effectiveHr = catalog.onDemandHr * (1 - SAVINGS_PLAN_DISCOUNT);
    } else if (type === 'ON_DEMAND') {
      this.effectiveHr = catalog.onDemandHr;
    } else {
      // SPOT — varies 15–30% of On-Demand depending on market conditions
      const jitter = 0.90 + Math.random() * 0.20;
      this.effectiveHr = catalog.onDemandHr * catalog.spotMultiplier * jitter;
    }
  }

  get savingsVsOnDemand() {
    return ((1 - this.effectiveHr / this.onDemandHr) * 100).toFixed(1);
  }

  toJSON() {
    return {
      id:              this.id,
      type:            this.type,
      family:          this.family,
      vcpu:            this.vcpu,
      ram:             this.ram,
      az:              this.az,
      state:           this.state,
      launchedAt:      this.launchedAt,
      drainStartedAt:  this.drainStartedAt,
      drainProgress:   Math.round(this.drainProgress),
      onDemandHr:      this.onDemandHr,
      effectiveHr:     parseFloat(this.effectiveHr.toFixed(4)),
      savingsPercent:  parseFloat(this.savingsVsOnDemand),
    };
  }
}

class FleetEngine extends EventEmitter {
  constructor(config = {}) {
    super();
    this.config = {
      reservedCount: config.reservedCount ?? 6,
      onDemandCount: config.onDemandCount ?? 2,
      spotCount:     config.spotCount     ?? 8,
      tickMs:        config.tickMs        ?? 3000, // simulation speed (3s per tick)
    };

    this.fleet   = new Map();   // id → Instance
    this.events  = [];          // event log
    this.tick    = 0;
    this._timer  = null;

    this._populateInitialFleet();
  }

  // ---------------------------------------------------------------------------
  // Fleet initialization
  // ---------------------------------------------------------------------------
  _randomCatalog() {
    return INSTANCE_CATALOG[Math.floor(Math.random() * INSTANCE_CATALOG.length)];
  }

  _randomAZ() {
    return AZS[Math.floor(Math.random() * AZS.length)];
  }

  _populateInitialFleet() {
    for (let i = 0; i < this.config.reservedCount; i++) {
      const inst = new Instance({ type: 'RESERVED', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }
    for (let i = 0; i < this.config.onDemandCount; i++) {
      const inst = new Instance({ type: 'ON_DEMAND', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }
    for (let i = 0; i < this.config.spotCount; i++) {
      const inst = new Instance({ type: 'SPOT', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }
    this._log('FLEET_INIT', `Fleet initialized: ${this.config.reservedCount}R + ${this.config.onDemandCount}OD + ${this.config.spotCount}SPOT`);
  }

  // ---------------------------------------------------------------------------
  // Simulation tick
  // ---------------------------------------------------------------------------
  start() {
    this._timer = setInterval(() => this._processTick(), this.config.tickMs);
    this._log('ENGINE_START', 'Fleet engine started');
    this.emit('state', this._snapshot());
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._log('ENGINE_STOP', 'Fleet engine stopped');
  }

  _processTick() {
    this.tick++;

    // Process existing interruption states
    for (const inst of this.fleet.values()) {
      if (inst.state === 'INTERRUPT_NOTICE') {
        // Advance drain window — 120s total / tickMs per tick
        const ticksFor120s = Math.ceil(120_000 / this.config.tickMs);
        inst.drainProgress = Math.min(100, inst.drainProgress + (100 / ticksFor120s));

        if (inst.drainProgress >= 100) {
          inst.state = 'DRAINING';
          inst.drainStartedAt = Date.now();
          this._log('SPOT_DRAIN', `Instance ${inst.id} (${inst.family}) entered final drain phase`);
        }
      } else if (inst.state === 'DRAINING') {
        // Complete drain in next tick
        inst.state = 'TERMINATED';
        inst.terminatedAt = Date.now();
        this._log('SPOT_TERMINATE', `Instance ${inst.id} (${inst.family}) terminated in ${inst.az}`);

        // Trigger replacement from a different AZ/family (capacity rebalancing)
        setTimeout(() => this._replaceSpotInstance(inst), this.config.tickMs * 0.5);
      }
    }

    // Probabilistic Spot interruption — only target RUNNING Spot instances
    if (Math.random() < SPOT_INTERRUPT_PROBABILITY) {
      const candidates = [...this.fleet.values()].filter(
        i => i.type === 'SPOT' && i.state === 'RUNNING'
      );
      if (candidates.length > 0) {
        const victim = candidates[Math.floor(Math.random() * candidates.length)];
        this._triggerSpotInterruption(victim);
      }
    }

    // Optionally scale On-Demand up/down (simulate traffic burst every 25 ticks)
    if (this.tick % 25 === 0) {
      this._simulateBurst();
    }

    // Clean up terminated instances older than 10 ticks
    for (const [id, inst] of this.fleet.entries()) {
      if (inst.state === 'TERMINATED' && Date.now() - inst.terminatedAt > this.config.tickMs * 10) {
        this.fleet.delete(id);
      }
    }

    this.emit('state', this._snapshot());
  }

  // ---------------------------------------------------------------------------
  // Spot interruption sequence
  // ---------------------------------------------------------------------------
  _triggerSpotInterruption(inst) {
    inst.state        = 'INTERRUPT_NOTICE';
    inst.drainProgress = 0;
    this._log(
      'SPOT_INTERRUPT',
      `⚠ INTERRUPT NOTICE: ${inst.id} (${inst.family}@${inst.az}) — 2-minute drain window started`
    );
    this.emit('interrupt', inst.toJSON());
  }

  _replaceSpotInstance(terminated) {
    // Select a different instance family than the terminated one (diversification)
    const different = INSTANCE_CATALOG.filter(c => c.family !== terminated.family);
    const catalog   = different[Math.floor(Math.random() * different.length)];
    // Select a different AZ if possible
    const otherAZs  = AZS.filter(az => az !== terminated.az);
    const az        = otherAZs[Math.floor(Math.random() * otherAZs.length)];

    const replacement = new Instance({ type: 'SPOT', catalog, az });
    this.fleet.set(replacement.id, replacement);
    this._log(
      'SPOT_REPLACE',
      `✓ Replacement: ${replacement.id} (${replacement.family}@${replacement.az}) — different pool selected`
    );
    this.emit('replace', { terminated: terminated.id, replacement: replacement.toJSON() });
  }

  // ---------------------------------------------------------------------------
  // Traffic burst simulation — adds On-Demand instances
  // ---------------------------------------------------------------------------
  _simulateBurst() {
    const addBurst = Math.random() > 0.5;
    const onDemands = [...this.fleet.values()].filter(i => i.type === 'ON_DEMAND' && i.state === 'RUNNING');

    if (addBurst && onDemands.length < 5) {
      const inst = new Instance({ type: 'ON_DEMAND', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
      this._log('BURST_SCALE_UP', `Traffic spike: added On-Demand ${inst.id} (${inst.family})`);
    } else if (!addBurst && onDemands.length > this.config.onDemandCount) {
      // Scale down burst instances
      const victim = onDemands[onDemands.length - 1];
      victim.state = 'TERMINATED';
      victim.terminatedAt = Date.now();
      this._log('BURST_SCALE_DOWN', `Traffic normalized: terminated On-Demand ${victim.id}`);
    }
  }

  // ---------------------------------------------------------------------------
  // Fleet composition adjustments (API-driven)
  // ---------------------------------------------------------------------------
  adjustFleet({ reservedDelta = 0, spotDelta = 0, onDemandDelta = 0 }) {
    // Add instances
    for (let i = 0; i < reservedDelta; i++) {
      const inst = new Instance({ type: 'RESERVED', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }
    for (let i = 0; i < spotDelta; i++) {
      const inst = new Instance({ type: 'SPOT', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }
    for (let i = 0; i < onDemandDelta; i++) {
      const inst = new Instance({ type: 'ON_DEMAND', catalog: this._randomCatalog(), az: this._randomAZ() });
      this.fleet.set(inst.id, inst);
    }

    // Remove instances (negative deltas) — graceful for spot/on-demand
    const terminate = (type, count) => {
      const targets = [...this.fleet.values()]
        .filter(i => i.type === type && i.state === 'RUNNING')
        .slice(0, Math.abs(count));
      targets.forEach(i => {
        i.state = 'TERMINATED';
        i.terminatedAt = Date.now();
      });
    };
    if (reservedDelta < 0) terminate('RESERVED', reservedDelta);
    if (spotDelta     < 0) terminate('SPOT',     spotDelta);
    if (onDemandDelta < 0) terminate('ON_DEMAND', onDemandDelta);

    this._log('FLEET_ADJUST', `Fleet adjusted: R${reservedDelta >= 0 ? '+' : ''}${reservedDelta} OD${onDemandDelta >= 0 ? '+' : ''}${onDemandDelta} SPOT${spotDelta >= 0 ? '+' : ''}${spotDelta}`);
    this.emit('state', this._snapshot());
  }

  // ---------------------------------------------------------------------------
  // Manually trigger a Spot interruption (for demo purposes)
  // ---------------------------------------------------------------------------
  forceInterrupt() {
    const candidates = [...this.fleet.values()].filter(
      i => i.type === 'SPOT' && i.state === 'RUNNING'
    );
    if (candidates.length === 0) return { ok: false, message: 'No running Spot instances' };
    const victim = candidates[Math.floor(Math.random() * candidates.length)];
    this._triggerSpotInterruption(victim);
    return { ok: true, instanceId: victim.id, family: victim.family };
  }

  // ---------------------------------------------------------------------------
  // Snapshot — full fleet state + aggregate metrics
  // ---------------------------------------------------------------------------
  _snapshot() {
    const instances = [...this.fleet.values()].map(i => i.toJSON());
    const active    = instances.filter(i => i.state !== 'TERMINATED');

    const byType = { RESERVED: [], ON_DEMAND: [], SPOT: [] };
    let totalEffectiveHr = 0;
    let totalOnDemandHr  = 0;

    for (const inst of active) {
      byType[inst.type]?.push(inst);
      totalEffectiveHr += inst.effectiveHr;
      totalOnDemandHr  += inst.onDemandHr;
    }

    const overallSavings = totalOnDemandHr > 0
      ? ((1 - totalEffectiveHr / totalOnDemandHr) * 100).toFixed(1)
      : '0.0';

    const totalVcpu = active.reduce((s, i) => s + i.vcpu, 0);
    const totalRam  = active.reduce((s, i) => s + i.ram, 0);

    return {
      tick:           this.tick,
      timestamp:      Date.now(),
      instances,
      metrics: {
        activeCount:     active.length,
        reservedCount:   byType.RESERVED.length,
        onDemandCount:   byType.ON_DEMAND.length,
        spotCount:       byType.SPOT.length,
        interruptedCount: active.filter(i => i.state === 'INTERRUPT_NOTICE' || i.state === 'DRAINING').length,
        totalEffectiveHr: parseFloat(totalEffectiveHr.toFixed(4)),
        totalOnDemandHr:  parseFloat(totalOnDemandHr.toFixed(4)),
        savingsPercent:   parseFloat(overallSavings),
        totalVcpu,
        totalRam,
        dailyCost:        parseFloat((totalEffectiveHr * 24).toFixed(2)),
        monthlyCost:      parseFloat((totalEffectiveHr * 24 * 30).toFixed(2)),
      },
      byType,
      events: this.events.slice(-20),
    };
  }

  _log(event, message) {
    const entry = {
      ts:      new Date().toISOString(),
      event,
      message,
    };
    this.events.push(entry);
    if (this.events.length > 200) this.events.shift();
    console.log(`[${entry.ts}] [${event}] ${message}`);
  }

  getSnapshot() {
    return this._snapshot();
  }
}

module.exports = { FleetEngine, INSTANCE_CATALOG, SAVINGS_PLAN_DISCOUNT };
