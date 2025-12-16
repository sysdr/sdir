const express = require('express');
const { VectorClock } = require('./utils');

class RegionNode {
  constructor(regionId, port, peers) {
    this.regionId = regionId;
    this.port = port;
    this.peers = peers;
    this.data = new Map();
    this.vectorClock = new VectorClock(regionId);
    this.metadata = new Map(); // Stores vector clock per key
    this.stats = {
      writes: 0,
      reads: 0,
      replications: 0,
      conflicts: 0
    };
    this.healthy = true;
    this.app = express();
    this.app.use(express.json());
    this.setupRoutes();
  }

  setupRoutes() {
    // Write endpoint
    this.app.post('/write', (req, res) => {
      const { key, value } = req.body;
      const clock = this.vectorClock.increment();
      
      this.data.set(key, value);
      this.metadata.set(key, { clock, timestamp: Date.now(), region: this.regionId });
      this.stats.writes++;

      // Async replicate to peers
      this.replicateToPeers(key, value, clock);

      res.json({ success: true, region: this.regionId, clock });
    });

    // Read endpoint
    this.app.get('/read/:key', (req, res) => {
      const { key } = req.params;
      this.stats.reads++;
      
      const value = this.data.get(key);
      const metadata = this.metadata.get(key);
      
      res.json({ 
        value, 
        metadata,
        region: this.regionId 
      });
    });

    // Replication endpoint
    this.app.post('/replicate', (req, res) => {
      const { key, value, clock, sourceRegion } = req.body;
      this.stats.replications++;

      const existing = this.metadata.get(key);
      
      if (!existing) {
        // No conflict, accept write
        this.data.set(key, value);
        this.metadata.set(key, { clock, timestamp: Date.now(), region: sourceRegion });
        this.vectorClock.merge(clock);
        res.json({ accepted: true, conflict: false });
      } else {
        // Check for conflict
        const comparison = this.vectorClock.compare(clock, existing.clock);
        
        if (comparison === 1) {
          // Incoming write is newer
          this.data.set(key, value);
          this.metadata.set(key, { clock, timestamp: Date.now(), region: sourceRegion });
          this.vectorClock.merge(clock);
          res.json({ accepted: true, conflict: false });
        } else if (comparison === -1) {
          // Existing write is newer, reject
          res.json({ accepted: false, conflict: false });
        } else {
          // Concurrent writes - conflict!
          this.stats.conflicts++;
          // Last-write-wins based on timestamp
          const incomingTimestamp = Date.now();
          if (incomingTimestamp > existing.timestamp) {
            this.data.set(key, value);
            this.metadata.set(key, { clock, timestamp: incomingTimestamp, region: sourceRegion });
          }
          this.vectorClock.merge(clock);
          res.json({ accepted: true, conflict: true });
        }
      }
    });

    // Health check
    this.app.get('/health', (req, res) => {
      res.json({ 
        healthy: this.healthy,
        region: this.regionId,
        stats: this.stats,
        dataSize: this.data.size
      });
    });

    // Stats endpoint
    this.app.get('/stats', (req, res) => {
      res.json({
        region: this.regionId,
        ...this.stats,
        dataSize: this.data.size,
        healthy: this.healthy
      });
    });

    // Simulate failure
    this.app.post('/fail', (req, res) => {
      this.healthy = false;
      res.json({ region: this.regionId, healthy: false });
    });

    // Recover
    this.app.post('/recover', (req, res) => {
      this.healthy = true;
      res.json({ region: this.regionId, healthy: true });
    });
  }

  async replicateToPeers(key, value, clock) {
    const fetch = require('node-fetch');
    
    for (const peer of this.peers) {
      try {
        await fetch(`http://${peer}/replicate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            key, 
            value, 
            clock, 
            sourceRegion: this.regionId 
          })
        });
      } catch (error) {
        // Peer might be down, continue
      }
    }
  }

  start() {
    this.app.listen(this.port, () => {
      console.log(`${this.regionId} running on port ${this.port}`);
    });
  }
}

module.exports = RegionNode;
