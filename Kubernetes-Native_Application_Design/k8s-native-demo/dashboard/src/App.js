import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [pods, setPods] = useState([]);
  const [metrics, setMetrics] = useState({ totalRequests: 0, avgResponseTime: 0 });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const fetchStatus = async () => {
      try {
        const response = await fetch('/api/pods/status');
        const data = await response.json();
        setPods(data.pods || []);
        setMetrics(data.metrics || {});
      } catch (error) {
        console.error('Failed to fetch status:', error);
      }
    };

    fetchStatus();
    const interval = setInterval(fetchStatus, 2000);
    return () => clearInterval(interval);
  }, []);

  const generateLoad = async (intensity) => {
    setLoading(true);
    try {
      await fetch('/api/load/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ intensity })
      });
    } catch (error) {
      console.error('Failed to generate load:', error);
    }
    setLoading(false);
  };

  const triggerChaos = async (action, podName) => {
    try {
      await fetch(`/api/chaos/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pod: podName })
      });
    } catch (error) {
      console.error('Chaos action failed:', error);
    }
  };

  return (
    <div className="app">
      <div className="header">
        <h1>🎯 Kubernetes-Native Application Dashboard</h1>
        <p>Real-time monitoring of K8s-native patterns and behaviors</p>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-value">{pods.length}</div>
          <div className="metric-label">Active Pods</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{pods.filter(p => p.ready).length}</div>
          <div className="metric-label">Ready Pods</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.totalRequests}</div>
          <div className="metric-label">Total Requests</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.avgResponseTime}ms</div>
          <div className="metric-label">Avg Response</div>
        </div>
      </div>

      <div className="controls">
        <h2>Load Generator</h2>
        <div className="button-group">
          <button onClick={() => generateLoad('low')} disabled={loading}>Low Load</button>
          <button onClick={() => generateLoad('medium')} disabled={loading}>Medium Load</button>
          <button onClick={() => generateLoad('high')} disabled={loading}>High Load</button>
        </div>
      </div>

      <div className="pods-section">
        <h2>Pod Status</h2>
        <div className="pods-grid">
          {pods.map(pod => (
            <div key={pod.name} className={`pod-card ${pod.ready ? 'ready' : 'not-ready'}`}>
              <div className="pod-header">
                <span className="pod-name">{pod.name}</span>
                <span className={`status-badge ${pod.healthy ? 'healthy' : 'unhealthy'}`}>
                  {pod.healthy ? '✓ Healthy' : '✗ Unhealthy'}
                </span>
              </div>
              <div className="pod-details">
                <div className="detail-row">
                  <span>Ready:</span>
                  <span>{pod.ready ? 'Yes' : 'No'}</span>
                </div>
                <div className="detail-row">
                  <span>Requests:</span>
                  <span>{pod.activeRequests}</span>
                </div>
                <div className="detail-row">
                  <span>Uptime:</span>
                  <span>{Math.floor(pod.uptime)}s</span>
                </div>
                <div className="detail-row">
                  <span>Config:</span>
                  <span className="config-badge">{pod.config?.featureFlag}</span>
                </div>
              </div>
              <div className="chaos-controls">
                <button onClick={() => triggerChaos('crash', pod.name)} className="chaos-btn">
                  Crash
                </button>
                <button onClick={() => triggerChaos('unhealthy', pod.name)} className="chaos-btn">
                  Unhealthy
                </button>
                <button onClick={() => triggerChaos('notready', pod.name)} className="chaos-btn">
                  Not Ready
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
