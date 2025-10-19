import React, { useState, useEffect } from 'react';
import { getPerformanceMetrics } from '../services/api';

const PerformanceMetrics = () => {
  const [metrics, setMetrics] = useState(null);

  useEffect(() => {
    const loadMetrics = async () => {
      try {
        const data = await getPerformanceMetrics();
        setMetrics(data);
      } catch (error) {
        console.error('Error loading metrics:', error);
      }
    };

    loadMetrics();
    const interval = setInterval(loadMetrics, 5000);
    return () => clearInterval(interval);
  }, []);

  if (!metrics) return <div className="card"><h3>Performance Metrics</h3><p>Loading...</p></div>;

  return (
    <div className="card">
      <h3>Real-time Performance</h3>
      <div className="performance-grid">
        <div className="metric-card">
          <div className="metric-value">{metrics.avg_response_time_ms}ms</div>
          <div className="metric-label">Avg Response Time</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{(metrics.cache_hit_rate * 100).toFixed(1)}%</div>
          <div className="metric-label">Cache Hit Rate</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.recommendations_served.toLocaleString()}</div>
          <div className="metric-label">Recommendations Served</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.active_users.toLocaleString()}</div>
          <div className="metric-label">Active Users</div>
        </div>
      </div>
      
      <h4 style={{ marginTop: '2rem', marginBottom: '1rem', color: '#1e40af', fontWeight: '700' }}>Algorithm Performance</h4>
      {Object.entries(metrics.algorithms).map(([algo, stats]) => (
        <div key={algo} style={{ 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center',
          padding: '1.5rem',
          background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
          marginBottom: '1rem',
          borderRadius: '16px',
          border: '1px solid #e2e8f0',
          boxShadow: '0 4px 12px rgba(0, 0, 0, 0.05)',
          transition: 'all 0.3s ease',
          position: 'relative',
          overflow: 'hidden'
        }}>
          <span style={{ 
            fontWeight: '700', 
            textTransform: 'capitalize',
            color: '#1e40af',
            fontSize: '1.1rem'
          }}>
            {algo.replace('_', ' ')}
          </span>
          <div style={{ display: 'flex', gap: '2rem', alignItems: 'center' }}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ 
                fontSize: '1.2rem', 
                fontWeight: '800', 
                color: '#3b82f6',
                marginBottom: '0.25rem'
              }}>
                {(stats.accuracy * 100).toFixed(1)}%
              </div>
              <div style={{ 
                fontSize: '0.8rem', 
                color: '#64748b',
                textTransform: 'uppercase',
                letterSpacing: '0.5px'
              }}>
                Accuracy
              </div>
            </div>
            <div style={{ textAlign: 'center' }}>
              <div style={{ 
                fontSize: '1.2rem', 
                fontWeight: '800', 
                color: '#10b981',
                marginBottom: '0.25rem'
              }}>
                {(stats.coverage * 100).toFixed(1)}%
              </div>
              <div style={{ 
                fontSize: '0.8rem', 
                color: '#64748b',
                textTransform: 'uppercase',
                letterSpacing: '0.5px'
              }}>
                Coverage
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};

export default PerformanceMetrics;
