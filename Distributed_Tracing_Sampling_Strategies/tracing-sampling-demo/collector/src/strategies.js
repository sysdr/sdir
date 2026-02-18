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
