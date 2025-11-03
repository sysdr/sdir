const { v4: uuidv4 } = require('uuid');

class PipelineEngine {
  constructor(redisClient, socketIo) {
    this.redis = redisClient;
    this.io = socketIo;
    this.activeJobs = new Map();
    this.metrics = {
      totalPipelines: 0,
      successfulPipelines: 0,
      failedPipelines: 0,
      averageLeadTime: 0,
      stageFailureRates: new Map(),
      deploymentFrequency: 0,
      meanTimeToRecovery: 0
    };
  }

  async initialize() {
    // Initialize metrics collection
    await this.initializeMetrics();
    console.log('Pipeline Engine initialized with metrics collection');
  }

  async initializeMetrics() {
    // Load historical metrics from Redis
    const existingMetrics = await this.redis.get('pipeline:metrics');
    if (existingMetrics) {
      const parsed = JSON.parse(existingMetrics);
      this.metrics = { 
        ...this.metrics, 
        ...parsed,
        // Ensure stageFailureRates remains a Map
        stageFailureRates: parsed.stageFailureRates ? new Map(Object.entries(parsed.stageFailureRates)) : new Map()
      };
    }
    
    // Start metrics collection interval
    setInterval(async () => {
      await this.updateMetrics();
      this.io.emit('metrics-updated', this.metrics);
    }, 10000); // Update every 10 seconds
  }

  async updateMetrics() {
    const pipelines = await this.getAllPipelines();
    const last24Hours = pipelines.filter(p => 
      new Date(p.createdAt) > new Date(Date.now() - 24 * 60 * 60 * 1000)
    );
    
    this.metrics.totalPipelines = pipelines.length;
    this.metrics.successfulPipelines = pipelines.filter(p => p.status === 'completed').length;
    this.metrics.failedPipelines = pipelines.filter(p => p.status === 'failed').length;
    this.metrics.deploymentFrequency = last24Hours.length;
    
    // Calculate average lead time (creation to completion)
    const completedPipelines = pipelines.filter(p => p.status === 'completed');
    if (completedPipelines.length > 0) {
      const totalLeadTime = completedPipelines.reduce((sum, p) => {
        const lastStage = p.stages[p.stages.length - 1];
        if (lastStage.endTime) {
          return sum + (new Date(lastStage.endTime) - new Date(p.createdAt));
        }
        return sum;
      }, 0);
      this.metrics.averageLeadTime = Math.round(totalLeadTime / completedPipelines.length / 1000); // in seconds
    }
    
    // Calculate stage failure rates
    const stageStats = new Map();
    pipelines.forEach(pipeline => {
      pipeline.stages.forEach(stage => {
        if (!stageStats.has(stage.name)) {
          stageStats.set(stage.name, { total: 0, failures: 0 });
        }
        const stats = stageStats.get(stage.name);
        stats.total++;
        if (stage.status === 'failed') {
          stats.failures++;
        }
      });
    });
    
    stageStats.forEach((stats, stageName) => {
      this.metrics.stageFailureRates.set(stageName, 
        Math.round((stats.failures / stats.total) * 100 * 100) / 100 // Round to 2 decimal places
      );
    });
    
    // Store updated metrics (convert Map to object for JSON serialization)
    const metricsToStore = {
      ...this.metrics,
      stageFailureRates: Object.fromEntries(this.metrics.stageFailureRates)
    };
    await this.redis.set('pipeline:metrics', JSON.stringify(metricsToStore));
  }

  async triggerPipeline(service, metadata = {}) {
    const pipelineId = uuidv4();
    const pipeline = {
      id: pipelineId,
      service,
      status: 'running',
      createdAt: new Date().toISOString(),
      metadata,
      stages: this.getStagesForService(service),
      currentStage: 0
    };

    await this.redis.hSet(`pipeline:${pipelineId}`, {
      data: JSON.stringify(pipeline)
    });

    // Start pipeline execution
    this.executePipeline(pipelineId);

    this.io.emit('pipeline-triggered', pipeline);
    return pipelineId;
  }

  getStagesForService(service) {
    const commonStages = [
      { name: 'build', duration: 15000, requiresApproval: false, description: 'Compile and package code' },
      { name: 'test', duration: 20000, requiresApproval: false, description: 'Unit and integration tests' },
      { name: 'security-scan', duration: 25000, requiresApproval: false, description: 'SAST/DAST security analysis' },
      { name: 'staging-deploy', duration: 10000, requiresApproval: true, description: 'Deploy to staging environment' },
      { name: 'production-deploy', duration: 12000, requiresApproval: true, description: 'Deploy to production environment' }
    ];

    // Service-specific variations for realistic enterprise patterns
    if (service === 'database') {
      commonStages.splice(3, 0, { 
        name: 'migration-check', 
        duration: 8000, 
        requiresApproval: true,
        description: 'Validate database schema migrations' 
      });
      commonStages.splice(2, 0, { 
        name: 'backup-validation', 
        duration: 6000, 
        requiresApproval: false,
        description: 'Verify backup integrity' 
      });
    }

    if (service === 'frontend') {
      commonStages.splice(2, 0, { 
        name: 'accessibility-scan', 
        duration: 12000, 
        requiresApproval: false,
        description: 'WCAG compliance validation' 
      });
      commonStages.splice(-1, 0, { 
        name: 'cdn-deploy', 
        duration: 8000, 
        requiresApproval: false,
        description: 'Deploy assets to CDN' 
      });
    }

    if (service === 'backend') {
      commonStages.splice(3, 0, { 
        name: 'load-test', 
        duration: 18000, 
        requiresApproval: false,
        description: 'Performance and load testing' 
      });
      commonStages.splice(2, 0, { 
        name: 'api-validation', 
        duration: 10000, 
        requiresApproval: false,
        description: 'API contract validation' 
      });
    }

    return commonStages.map((stage, index) => ({
      ...stage,
      id: index,
      status: 'pending',
      startTime: null,
      endTime: null,
      securityFindings: stage.name === 'security-scan' ? this.generateSecurityFindings() : null
    }));
  }

  generateSecurityFindings() {
    const findings = [];
    const possibleIssues = [
      { severity: 'high', type: 'SQL Injection', count: Math.random() > 0.8 ? 1 : 0 },
      { severity: 'medium', type: 'XSS Vulnerability', count: Math.random() > 0.7 ? Math.floor(Math.random() * 3) : 0 },
      { severity: 'low', type: 'Outdated Dependencies', count: Math.floor(Math.random() * 8) },
      { severity: 'info', type: 'Code Quality Issues', count: Math.floor(Math.random() * 15) }
    ];
    
    possibleIssues.forEach(issue => {
      if (issue.count > 0) {
        findings.push(issue);
      }
    });
    
    return findings;
  }

  getMetrics() {
    return {
      ...this.metrics,
      stageFailureRates: Object.fromEntries(this.metrics.stageFailureRates)
    };
  }

  async performSecurityScan(service, commit) {
    // Simulate security scanning with realistic results
    const scanDuration = Math.random() * 10000 + 15000; // 15-25 seconds
    
    return new Promise((resolve) => {
      setTimeout(() => {
        const findings = this.generateSecurityFindings();
        const hasHighSeverity = findings.some(f => f.severity === 'high');
        
        resolve({
          service,
          commit,
          duration: scanDuration,
          passed: !hasHighSeverity,
          findings,
          timestamp: new Date().toISOString()
        });
      }, scanDuration);
    });
  }

  async executePipeline(pipelineId) {
    const pipeline = await this.getPipeline(pipelineId);
    if (!pipeline) return;

    for (let i = 0; i < pipeline.stages.length; i++) {
      const stage = pipeline.stages[i];
      
      // Update current stage
      pipeline.currentStage = i;
      await this.updatePipeline(pipelineId, pipeline);

      // Handle approval stage
      if (stage.requiresApproval) {
        stage.status = 'waiting-approval';
        await this.updatePipeline(pipelineId, pipeline);
        this.io.emit('pipeline-updated', pipeline);

        // Wait for approval
        await this.waitForApproval(pipelineId, i);
        stage.status = 'running';
      } else {
        stage.status = 'running';
      }

      stage.startTime = new Date().toISOString();
      await this.updatePipeline(pipelineId, pipeline);
      this.io.emit('pipeline-updated', pipeline);

      // Simulate stage execution with realistic failure chance
      const success = await this.executeStage(stage, pipeline.service);
      
      stage.endTime = new Date().toISOString();
      
      if (success) {
        stage.status = 'success';
      } else {
        stage.status = 'failed';
        pipeline.status = 'failed';
        await this.updatePipeline(pipelineId, pipeline);
        this.io.emit('pipeline-updated', pipeline);
        return;
      }

      await this.updatePipeline(pipelineId, pipeline);
      this.io.emit('pipeline-updated', pipeline);
    }

    pipeline.status = 'completed';
    await this.updatePipeline(pipelineId, pipeline);
    this.io.emit('pipeline-updated', pipeline);
  }

  async executeStage(stage, service) {
    return new Promise((resolve) => {
      setTimeout(() => {
        // Simulate realistic failure rates with stage-specific patterns
        let failureRate = 0.05; // Default 5% failure rate
        
        switch(stage.name) {
          case 'test':
            failureRate = 0.15; // 15% test failure rate
            break;
          case 'security-scan':
            failureRate = 0.08; // 8% security scan failure rate
            break;
          case 'migration-check':
            failureRate = 0.20; // 20% migration check failure rate (database complexity)
            break;
          case 'production-deploy':
            failureRate = 0.03; // Lower production failure rate due to previous gates
            break;
        }
        
        // Service-specific adjustments
        if (service === 'database') failureRate *= 1.5;
        if (service === 'frontend') failureRate *= 0.8;
        
        const success = Math.random() > failureRate;
        
        // Emit stage execution details for monitoring
        this.io.emit('stage-execution', {
          stage: stage.name,
          service,
          duration: stage.duration,
          success,
          timestamp: new Date().toISOString()
        });
        
        resolve(success);
      }, stage.duration);
    });
  }

  async waitForApproval(pipelineId, stageIndex) {
    return new Promise((resolve) => {
      const checkInterval = setInterval(async () => {
        const pipeline = await this.getPipeline(pipelineId);
        if (pipeline.stages[stageIndex].approved) {
          clearInterval(checkInterval);
          resolve();
        }
      }, 1000);

      // Auto-approve after 60 seconds for demo purposes
      setTimeout(() => {
        clearInterval(checkInterval);
        this.approveStage(pipelineId, stageIndex.toString());
        resolve();
      }, 60000);
    });
  }

  async approveStage(pipelineId, stageIndex) {
    const pipeline = await this.getPipeline(pipelineId);
    if (pipeline) {
      pipeline.stages[parseInt(stageIndex)].approved = true;
      await this.updatePipeline(pipelineId, pipeline);
      this.io.emit('pipeline-updated', pipeline);
    }
  }

  async getAllPipelines() {
    const keys = await this.redis.keys('pipeline:*');
    const pipelines = [];
    
    for (const key of keys) {
      // Skip the metrics key as it's a string, not a hash
      if (key === 'pipeline:metrics') continue;
      
      try {
        const data = await this.redis.hGet(key, 'data');
        if (data) {
          pipelines.push(JSON.parse(data));
        }
      } catch (error) {
        // Skip keys that aren't hashes (wrong type)
        console.warn(`Skipping key ${key}: ${error.message}`);
      }
    }
    
    return pipelines.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  async getPipeline(id) {
    const data = await this.redis.hGet(`pipeline:${id}`, 'data');
    return data ? JSON.parse(data) : null;
  }

  async updatePipeline(id, pipeline) {
    await this.redis.hSet(`pipeline:${id}`, {
      data: JSON.stringify(pipeline)
    });
  }

  async getServiceStatus() {
    return {
      frontend: { status: 'healthy', lastDeploy: new Date(Date.now() - 3600000).toISOString() },
      backend: { status: 'healthy', lastDeploy: new Date(Date.now() - 7200000).toISOString() },
      database: { status: 'healthy', lastDeploy: new Date(Date.now() - 86400000).toISOString() }
    };
  }
}

module.exports = PipelineEngine;
