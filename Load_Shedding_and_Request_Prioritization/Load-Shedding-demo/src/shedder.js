export class LoadShedder {
  constructor() {
    this.metrics = {
      cpu: 0,
      queueDepth: 0,
      latencyP99: 0,
      activeConnections: 0
    };
    
    this.thresholds = {
      cpuWarning: 60,
      cpuCritical: 80,
      queueWarning: 100,
      queueCritical: 500,
      latencyWarning: 200,
      latencyCritical: 1000
    };
    
    this.acceptanceRates = {
      0: 1.0,  // CRITICAL - always accept
      1: 1.0,  // IMPORTANT
      2: 1.0,  // NORMAL
      3: 1.0   // BACKGROUND
    };
    
    this.stats = {
      total: 0,
      accepted: 0,
      rejected: 0,
      byPriority: {
        0: { total: 0, accepted: 0, rejected: 0 },
        1: { total: 0, accepted: 0, rejected: 0 },
        2: { total: 0, accepted: 0, rejected: 0 },
        3: { total: 0, accepted: 0, rejected: 0 }
      }
    };
    
    this.queue = [];
    this.processing = 0;
    this.maxProcessing = 100;
    
    // Update acceptance rates every 100ms
    setInterval(() => this.updateAcceptanceRates(), 100);
  }
  
  updateMetrics(cpu, queueDepth, latencyP99, activeConnections) {
    this.metrics.cpu = cpu;
    this.metrics.queueDepth = queueDepth;
    this.metrics.latencyP99 = latencyP99;
    this.metrics.activeConnections = activeConnections;
  }
  
  calculateLoadScore() {
    const cpuScore = Math.min(100, (this.metrics.cpu / this.thresholds.cpuCritical) * 100);
    const queueScore = Math.min(100, (this.metrics.queueDepth / this.thresholds.queueCritical) * 100);
    const latencyScore = Math.min(100, (this.metrics.latencyP99 / this.thresholds.latencyCritical) * 100);
    
    return Math.max(cpuScore, queueScore, latencyScore);
  }
  
  updateAcceptanceRates() {
    const loadScore = this.calculateLoadScore();
    
    if (loadScore < 50) {
      // Normal operation - accept everything
      this.acceptanceRates = { 0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0 };
    } else if (loadScore < 70) {
      // Light load - shed background
      this.acceptanceRates = { 0: 1.0, 1: 1.0, 2: 1.0, 3: 0.5 };
    } else if (loadScore < 85) {
      // Medium load - shed background and reduce normal
      this.acceptanceRates = { 0: 1.0, 1: 1.0, 2: 0.7, 3: 0.1 };
    } else if (loadScore < 95) {
      // High load - aggressive shedding
      this.acceptanceRates = { 0: 1.0, 1: 0.8, 2: 0.3, 3: 0.0 };
    } else {
      // Critical load - only critical requests
      this.acceptanceRates = { 0: 1.0, 1: 0.5, 2: 0.1, 3: 0.0 };
    }
  }
  
  shouldAccept(priority) {
    this.stats.total++;
    this.stats.byPriority[priority].total++;
    
    const acceptanceRate = this.acceptanceRates[priority];
    const shouldAccept = Math.random() < acceptanceRate;
    
    if (shouldAccept) {
      this.stats.accepted++;
      this.stats.byPriority[priority].accepted++;
    } else {
      this.stats.rejected++;
      this.stats.byPriority[priority].rejected++;
    }
    
    return shouldAccept;
  }
  
  getStats() {
    return {
      ...this.stats,
      acceptanceRates: this.acceptanceRates,
      metrics: this.metrics,
      loadScore: this.calculateLoadScore()
    };
  }
  
  reset() {
    this.stats = {
      total: 0,
      accepted: 0,
      rejected: 0,
      byPriority: {
        0: { total: 0, accepted: 0, rejected: 0 },
        1: { total: 0, accepted: 0, rejected: 0 },
        2: { total: 0, accepted: 0, rejected: 0 },
        3: { total: 0, accepted: 0, rejected: 0 }
      }
    };
  }
}
