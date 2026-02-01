// Latency tracking utilities
class LatencyTracker {
  constructor() {
    this.measurements = [];
    this.maxSamples = 1000;
  }

  track(latencyMs, metadata = {}) {
    this.measurements.push({
      latency: latencyMs,
      timestamp: Date.now(),
      ...metadata
    });
    
    if (this.measurements.length > this.maxSamples) {
      this.measurements.shift();
    }
  }

  getPercentile(p) {
    if (this.measurements.length === 0) return 0;
    const sorted = [...this.measurements].map(m => m.latency).sort((a, b) => a - b);
    const index = Math.ceil((p / 100) * sorted.length) - 1;
    return sorted[Math.max(0, index)];
  }

  getStats() {
    if (this.measurements.length === 0) {
      return { p50: 0, p95: 0, p99: 0, avg: 0, count: 0 };
    }

    const latencies = this.measurements.map(m => m.latency);
    const avg = latencies.reduce((a, b) => a + b, 0) / latencies.length;

    return {
      p50: this.getPercentile(50),
      p95: this.getPercentile(95),
      p99: this.getPercentile(99),
      avg: Math.round(avg),
      count: this.measurements.length
    };
  }

  getRecentMeasurements(limit = 50) {
    return this.measurements.slice(-limit);
  }
}

module.exports = { LatencyTracker };
