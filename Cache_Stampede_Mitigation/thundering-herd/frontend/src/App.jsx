import React, { useState, useEffect } from 'react';

const STRATEGIES = [
  { id: 'no-mitigation', name: 'No Mitigation', color: '#e53935' },
  { id: 'coalescing', name: 'Request Coalescing', color: '#43a047' },
  { id: 'probabilistic', name: 'Probabilistic Early Expiration', color: '#1e88e5' },
  { id: 'stale-revalidate', name: 'Stale-While-Revalidate', color: '#fb8c00' },
  { id: 'jittered', name: 'Jittered TTL', color: '#8e24aa' }
];

export default function App() {
  const [metrics, setMetrics] = useState({
    cacheHits: 0,
    cacheMisses: 0,
    dbQueries: 0,
    coalesced: 0,
    activeDbConnections: 0,
    avgLatency: 0,
    stampedes: 0
  });
  
  const [loading, setLoading] = useState(false);
  const [stampede, setStampede] = useState(false);

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:3001');
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'metrics') {
        setMetrics(message.data);
      }
    };
    
    const interval = setInterval(() => {
      fetch('http://localhost:3001/api/metrics').then(r => r.json()).then(data => {
        if (data && typeof data.cacheHits === 'number') setMetrics(m => ({ ...m, ...data, avgLatency: data.avgLatency || 0 }));
      }).catch(() => {});
    }, 2000);
    return () => { clearInterval(interval); ws.close(); };
  }, []);

  const triggerLoad = async (strategy, concurrent = 100) => {
    setLoading(true);
    setStampede(strategy === 'no-mitigation');
    
    const requests = [];
    for (let i = 0; i < concurrent; i++) {
      requests.push(
        fetch(`http://localhost:3001/api/product/1/${strategy}`)
          .then(r => r.json())
      );
    }
    
    await Promise.all(requests);
    setLoading(false);
    setTimeout(() => setStampede(false), 2000);
  };

  const reset = async () => {
    await fetch('http://localhost:3001/api/reset', { method: 'POST' });
  };

  const hitRate = metrics.cacheHits + metrics.cacheMisses > 0
    ? ((metrics.cacheHits / (metrics.cacheHits + metrics.cacheMisses)) * 100).toFixed(1)
    : 0;

  return (
    <div className="app">
      <div className="header">
        <h1>⚡ Cache Stampede Mitigation Dashboard</h1>
        <p>Real-time demonstration of thundering herd prevention strategies</p>
      </div>

      {stampede && (
        <div className="alert alert-danger">
          <strong>⚠️ STAMPEDE DETECTED!</strong> Database connections spiking. This is what happens without mitigation.
        </div>
      )}

      <div className="controls">
        {STRATEGIES.map(strategy => (
          <button
            key={strategy.id}
            className="btn btn-primary"
            onClick={() => triggerLoad(strategy.id, 100)}
            disabled={loading}
          >
            Test {strategy.name}
          </button>
        ))}
        <button className="btn btn-danger" onClick={reset}>
          Reset Metrics
        </button>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-label">Cache Hit Rate</div>
          <div className="metric-value">{hitRate}%</div>
          <div className="metric-subtext">
            {metrics.cacheHits} hits / {metrics.cacheMisses} misses
          </div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">DB Queries</div>
          <div className="metric-value">{metrics.dbQueries}</div>
          <div className="metric-subtext">
            {metrics.coalesced} coalesced requests
          </div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Active DB Connections</div>
          <div className="metric-value">{metrics.activeDbConnections}</div>
          <div className="metric-subtext">Pool size: 20 connections</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Avg Latency</div>
          <div className="metric-value">{metrics.avgLatency}ms</div>
          <div className="metric-subtext">Last 100 requests</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Stampedes</div>
          <div className="metric-value">{metrics.stampedes ?? 0}</div>
          <div className="metric-subtext">Concurrent stampede events</div>
        </div>
      </div>

      <div className="strategy-grid">
        {STRATEGIES.map(strategy => (
          <div key={strategy.id} className="strategy-card">
            <h3>
              <span className="status-indicator" />
              {strategy.name}
            </h3>
            <p style={{ color: '#546e7a', fontSize: '14px', marginTop: '8px' }}>
              {getStrategyDescription(strategy.id)}
            </p>
            <div className="strategy-stats">
              <div className="stat-item">
                <div className="stat-label">Effectiveness</div>
                <div className="stat-value">{getEffectiveness(strategy.id)}</div>
              </div>
              <div className="stat-item">
                <div className="stat-label">Complexity</div>
                <div className="stat-value">{getComplexity(strategy.id)}</div>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="alert">
        <strong>💡 Tip:</strong> Watch the "Active DB Connections" metric. No mitigation causes 100 concurrent DB queries. 
        Coalescing reduces it to 1. Stale-while-revalidate keeps serving users even during refresh.
      </div>
    </div>
  );
}

function getStrategyDescription(id) {
  const descriptions = {
    'no-mitigation': 'Every cache miss triggers a DB query. Causes stampedes.',
    'coalescing': 'Concurrent requests wait for first query to complete.',
    'probabilistic': 'Randomly refresh before expiration based on TTL.',
    'stale-revalidate': 'Serve stale data while refreshing in background.',
    'jittered': 'Add random variance to TTL to prevent synchronized expiration.'
  };
  return descriptions[id];
}

function getEffectiveness(id) {
  const ratings = {
    'no-mitigation': '❌',
    'coalescing': '⭐⭐⭐⭐',
    'probabilistic': '⭐⭐⭐',
    'stale-revalidate': '⭐⭐⭐⭐⭐',
    'jittered': '⭐⭐⭐'
  };
  return ratings[id];
}

function getComplexity(id) {
  const complexity = {
    'no-mitigation': 'Low',
    'coalescing': 'Medium',
    'probabilistic': 'Medium',
    'stale-revalidate': 'High',
    'jittered': 'Low'
  };
  return complexity[id];
}
