import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

const API_URL = 'http://localhost:3001';

export default function App() {
  const [metrics, setMetrics] = useState(null);
  const [history, setHistory] = useState([]);
  const [scenario, setScenario] = useState('normal');
  const [isGenerating, setIsGenerating] = useState(false);
  
  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const response = await fetch(`${API_URL}/api/metrics`);
        const data = await response.json();
        setMetrics(data);
        
        // Update history
        setHistory(prev => {
          const newHistory = [...prev, {
            timestamp: new Date().toLocaleTimeString(),
            p50: data.p50,
            p95: data.p95,
            p99: data.p99,
            p999: data.p999,
            queueDepth: data.queueDepth
          }];
          return newHistory.slice(-30); // Keep last 30 data points
        });
      } catch (error) {
        console.error('Failed to fetch metrics:', error);
      }
    };
    
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 1000);
    return () => clearInterval(interval);
  }, []);
  
  const changeScenario = async (newScenario) => {
    try {
      await fetch(`${API_URL}/api/scenario`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ scenario: newScenario })
      });
      setScenario(newScenario);
    } catch (error) {
      console.error('Failed to change scenario:', error);
    }
  };
  
  const generateLoad = async () => {
    setIsGenerating(true);
    const requests = [];
    for (let i = 0; i < 100; i++) {
      requests.push(
        fetch(`${API_URL}/api/request`).catch(e => console.error(e))
      );
      await new Promise(r => setTimeout(r, 10)); // 10ms between requests
    }
    await Promise.allSettled(requests);
    setIsGenerating(false);
  };
  
  const resetMetrics = async () => {
    try {
      await fetch(`${API_URL}/api/reset`, { method: 'POST' });
      setHistory([]);
    } catch (error) {
      console.error('Failed to reset:', error);
    }
  };
  
  if (!metrics) {
    return (
      <div style={{ color: 'white', textAlign: 'center', marginTop: '50px' }}>
        <h2>Loading metrics...</h2>
      </div>
    );
  }
  
  return (
    <div style={{ color: 'white' }}>
      <header style={{ 
        background: 'white', 
        padding: '30px', 
        borderRadius: '15px',
        boxShadow: '0 10px 30px rgba(0,0,0,0.3)',
        marginBottom: '20px'
      }}>
        <h1 style={{ color: '#667eea', margin: '0 0 10px 0', fontSize: '32px' }}>
          🎯 Tail Latency (P99) Monitor
        </h1>
        <p style={{ color: '#666', margin: 0 }}>
          Real-time percentile tracking with HDR Histogram
        </p>
      </header>
      
      <div style={{ 
        display: 'grid', 
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', 
        gap: '15px',
        marginBottom: '20px'
      }}>
        <MetricCard label="P50 (Median)" value={metrics.p50} unit="ms" color="#3b82f6" noData={metrics.totalRequests === 0} />
        <MetricCard label="P95" value={metrics.p95} unit="ms" color="#8b5cf6" noData={metrics.totalRequests === 0} />
        <MetricCard label="P99" value={metrics.p99} unit="ms" color="#ec4899" noData={metrics.totalRequests === 0} />
        <MetricCard label="P999" value={metrics.p999} unit="ms" color="#ef4444" noData={metrics.totalRequests === 0} />
        <MetricCard label="P9999" value={metrics.p9999} unit="ms" color="#dc2626" noData={metrics.totalRequests === 0} />
        <MetricCard label="Queue Depth" value={metrics.queueDepth} color="#10b981" />
      </div>
      
      <div style={{ 
        background: 'white', 
        padding: '25px', 
        borderRadius: '15px',
        boxShadow: '0 10px 30px rgba(0,0,0,0.3)',
        marginBottom: '20px'
      }}>
        <h2 style={{ color: '#667eea', marginBottom: '15px' }}>Percentile Trends</h2>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={history}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="timestamp" />
            <YAxis label={{ value: 'Latency (ms)', angle: -90, position: 'insideLeft' }} />
            <Tooltip />
            <Legend />
            <Line type="monotone" dataKey="p50" stroke="#3b82f6" strokeWidth={2} dot={false} name="P50" />
            <Line type="monotone" dataKey="p95" stroke="#8b5cf6" strokeWidth={2} dot={false} name="P95" />
            <Line type="monotone" dataKey="p99" stroke="#ec4899" strokeWidth={2} dot={false} name="P99" />
            <Line type="monotone" dataKey="p999" stroke="#ef4444" strokeWidth={2} dot={false} name="P999" />
          </LineChart>
        </ResponsiveContainer>
      </div>
      
      <div style={{ 
        background: 'white', 
        padding: '25px', 
        borderRadius: '15px',
        boxShadow: '0 10px 30px rgba(0,0,0,0.3)',
        marginBottom: '20px'
      }}>
        <h2 style={{ color: '#667eea', marginBottom: '15px' }}>Recent Requests Distribution</h2>
        <ResponsiveContainer width="100%" height={250}>
          <BarChart data={getLatencyBuckets(metrics.recentRequests)}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="bucket" />
            <YAxis label={{ value: 'Count', angle: -90, position: 'insideLeft' }} />
            <Tooltip />
            <Bar dataKey="count" fill="#667eea" />
          </BarChart>
        </ResponsiveContainer>
      </div>
      
      <div style={{ 
        background: 'white', 
        padding: '25px', 
        borderRadius: '15px',
        boxShadow: '0 10px 30px rgba(0,0,0,0.3)'
      }}>
        <h2 style={{ color: '#667eea', marginBottom: '15px' }}>Controls</h2>
        
        <div style={{ marginBottom: '20px' }}>
          <h3 style={{ color: '#666', marginBottom: '10px', fontSize: '14px' }}>Scenario</h3>
          <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
            {['fast', 'normal', 'withGC', 'slowQuery', 'contention'].map(s => (
              <button
                key={s}
                onClick={() => changeScenario(s)}
                style={{
                  padding: '10px 20px',
                  background: scenario === s ? '#667eea' : '#e5e7eb',
                  color: scenario === s ? 'white' : '#374151',
                  border: 'none',
                  borderRadius: '8px',
                  cursor: 'pointer',
                  fontWeight: '600',
                  transition: 'all 0.2s'
                }}
              >
                {s}
              </button>
            ))}
          </div>
        </div>
        
        <div style={{ display: 'flex', gap: '10px' }}>
          <button
            onClick={generateLoad}
            disabled={isGenerating}
            style={{
              padding: '12px 25px',
              background: isGenerating ? '#9ca3af' : '#10b981',
              color: 'white',
              border: 'none',
              borderRadius: '8px',
              cursor: isGenerating ? 'not-allowed' : 'pointer',
              fontWeight: '600',
              fontSize: '16px'
            }}
          >
            {isGenerating ? 'Generating...' : '🚀 Generate 100 Requests'}
          </button>
          
          <button
            onClick={resetMetrics}
            style={{
              padding: '12px 25px',
              background: '#ef4444',
              color: 'white',
              border: 'none',
              borderRadius: '8px',
              cursor: 'pointer',
              fontWeight: '600',
              fontSize: '16px'
            }}
          >
            🔄 Reset Metrics
          </button>
        </div>
        
        <div style={{ 
          marginTop: '20px', 
          padding: '15px', 
          background: '#f3f4f6', 
          borderRadius: '8px',
          color: '#374151',
          fontSize: '14px'
        }}>
          <strong>Current Stats:</strong><br/>
          Total Requests: {metrics.totalRequests} | 
          Mean: {formatStat(metrics.mean)}ms | 
          Std Dev: {formatStat(metrics.stdDev)}ms | 
          Min: {formatStat(metrics.min)}ms | 
          Max: {formatStat(metrics.max)}ms
        </div>
      </div>
    </div>
  );
}

function formatStat(v) {
  if (v == null || (typeof v === 'number' && isNaN(v))) return '—';
  if (typeof v === 'number') return v.toFixed(2);
  return String(v);
}

function MetricCard({ label, value, unit = '', color, noData }) {
  const display = noData && (value == null || value === 0)
    ? '—'
    : (typeof value === 'number' ? value.toFixed(1) : (value ?? '—'));
  return (
    <div style={{
      background: 'white',
      padding: '20px',
      borderRadius: '12px',
      boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
      transition: 'transform 0.2s'
    }}>
      <div style={{ color: '#9ca3af', fontSize: '14px', marginBottom: '5px' }}>
        {label}
      </div>
      <div style={{ color: display === '—' ? '#9ca3af' : color, fontSize: '32px', fontWeight: 'bold' }}>
        {display}
        {display !== '—' && <span style={{ fontSize: '18px', marginLeft: '5px' }}>{unit}</span>}
      </div>
    </div>
  );
}

function getLatencyBuckets(requests) {
  if (!requests || requests.length === 0) return [];
  
  const buckets = {
    '0-50ms': 0,
    '50-100ms': 0,
    '100-200ms': 0,
    '200-500ms': 0,
    '500-1000ms': 0,
    '1000ms+': 0
  };
  
  requests.forEach(req => {
    const lat = req.latency;
    if (lat < 50) buckets['0-50ms']++;
    else if (lat < 100) buckets['50-100ms']++;
    else if (lat < 200) buckets['100-200ms']++;
    else if (lat < 500) buckets['200-500ms']++;
    else if (lat < 1000) buckets['500-1000ms']++;
    else buckets['1000ms+']++;
  });
  
  return Object.entries(buckets).map(([bucket, count]) => ({ bucket, count }));
}
