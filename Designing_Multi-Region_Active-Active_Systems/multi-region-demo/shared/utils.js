const crypto = require('crypto');

class VectorClock {
  constructor(regionId) {
    this.regionId = regionId;
    this.clock = {};
  }

  increment() {
    this.clock[this.regionId] = (this.clock[this.regionId] || 0) + 1;
    return { ...this.clock };
  }

  merge(otherClock) {
    Object.keys(otherClock).forEach(region => {
      this.clock[region] = Math.max(this.clock[region] || 0, otherClock[region] || 0);
    });
  }

  compare(clock1, clock2) {
    const keys = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);
    let clock1Greater = false;
    let clock2Greater = false;

    for (const key of keys) {
      const v1 = clock1[key] || 0;
      const v2 = clock2[key] || 0;
      if (v1 > v2) clock1Greater = true;
      if (v2 > v1) clock2Greater = true;
    }

    if (clock1Greater && !clock2Greater) return 1;
    if (clock2Greater && !clock1Greater) return -1;
    return 0; // Concurrent
  }
}

module.exports = { VectorClock };
