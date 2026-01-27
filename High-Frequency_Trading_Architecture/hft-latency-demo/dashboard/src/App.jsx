import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, BarChart, Bar } from 'recharts';

export default function App() {
  const [metrics, setMetrics] = useState(null);
  const [history, setHistory] = useState([]);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    const ws = new WebSocket(
      (typeof window !== 'undefined' && window.location?.hostname)
        ? `ws://${window.location.hostname}:3004`
        : 'ws://localhost:3004'
    );
    let closedByCleanup = false;

    ws.onopen = () => {
      if (closedByCleanup) {
        ws.close();
        return;
      }
      setConnected(true);
      console.log('Connected to metrics collector');
    };

    ws.onmessage = (event) => {
      if (closedByCleanup) return;
      const message = JSON.parse(event.data);
      if (message.type === 'metrics_update') {
        setMetrics(message.data);
        const d = message.data;
        const tradAvg = parseFloat(d.traditional?.avgLatency);
        const optAvg = parseFloat(d.optimized?.avgLatency);
        const tradP99 = parseFloat(d.traditional?.p99);
        const optP99 = parseFloat(d.optimized?.p99);
        const hasData = (d.traditional?.packetsProcessed > 0 || d.optimized?.packetsProcessed > 0);
        setHistory(prev => {
          if (!hasData) return prev;
          const newHistory = [...prev, {
            time: new Date(d.timestamp).toLocaleTimeString(),
            traditional: isFinite(tradAvg) ? tradAvg : null,
            optimized: isFinite(optAvg) ? optAvg : null,
            tradP99: isFinite(tradP99) ? tradP99 : null,
            optP99: isFinite(optP99) ? optP99 : null
          }];
          return newHistory.slice(-50);
        });
      }
    };

    ws.onclose = () => {
      if (!closedByCleanup) {
        setConnected(false);
        console.log('Disconnected from metrics collector');
      }
    };

    ws.onerror = () => {
      if (closedByCleanup) return;
    };

    return () => {
      closedByCleanup = true;
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CLOSING) {
        ws.close();
      } else if (ws.readyState === WebSocket.CONNECTING) {
        ws.onopen = () => ws.close();
      }
    };
  }, []);

  const formatMetric = (v, suffix = '') => {
    if (v == null || v === '') return '—';
    const n = parseFloat(v);
    if (!isFinite(n) || n === 0) return '—';
    return `${v}${suffix ? ' ' + suffix : ''}`;
  };
  const formatPackets = (v) => {
    const n = Number(v);
    if (v == null || !isFinite(n) || n === 0) return '—';
    return n.toLocaleString();
  };
  const formatImprovement = (v, packetsProcessed) => {
    if (v == null || v === '') return '—';
    if (Number(packetsProcessed) === 0) return '—';
    return `${v}%`;
  };

  if (!metrics) {
    return (
      <div style={styles.container}>
        <div style={styles.loading}>
          <div style={styles.spinner}></div>
          <p>Connecting to HFT Latency Demo...</p>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h1 style={styles.title}>⚡ High-Frequency Trading Latency Comparison</h1>
        <div style={styles.subtitle}>Kernel Bypass vs Traditional Network Stack</div>
        <div style={{...styles.status, background: connected ? '#10b981' : '#ef4444'}}>
          {connected ? '🟢 Live' : '🔴 Disconnected'}
        </div>
      </div>

      <div style={styles.grid}>
        {/* Traditional Processor */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <h3 style={styles.cardTitle}>🐢 Traditional Network Stack</h3>
            <div style={styles.badge}>Kernel Mode</div>
          </div>
          <div style={styles.stats}>
            <StatItem label="Avg Latency" value={formatMetric(metrics.traditional?.avgLatency, 'μs')} color="#ef4444" />
            <StatItem label="P50" value={formatMetric(metrics.traditional?.p50, 'μs')} color="#f59e0b" />
            <StatItem label="P95" value={formatMetric(metrics.traditional?.p95, 'μs')} color="#f97316" />
            <StatItem label="P99" value={formatMetric(metrics.traditional?.p99, 'μs')} color="#dc2626" />
            <StatItem label="Packets" value={formatPackets(metrics.traditional?.packetsProcessed)} color="#6366f1" />
          </div>
          <div style={styles.features}>
            <div style={styles.featuresLabel}>Overhead sources</div>
            <ul style={styles.featuresList}>
              <li style={styles.featureItemNegative}><span style={styles.featureMarkerNeg} aria-hidden>×</span> Kernel context switches</li>
              <li style={styles.featureItemNegative}><span style={styles.featureMarkerNeg} aria-hidden>×</span> System calls overhead</li>
              <li style={styles.featureItemNegative}><span style={styles.featureMarkerNeg} aria-hidden>×</span> Memory copies (kernel↔user)</li>
              <li style={styles.featureItemNegative}><span style={styles.featureMarkerNeg} aria-hidden>×</span> TCP/IP stack latency</li>
            </ul>
          </div>
        </div>

        {/* Optimized Processor */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <h3 style={styles.cardTitle}>⚡ Kernel Bypass (DPDK)</h3>
            <div style={{...styles.badge, background: '#10b981'}}>User Space</div>
          </div>
          <div style={styles.stats}>
            <StatItem label="Avg Latency" value={formatMetric(metrics.optimized?.avgLatency, 'μs')} color="#10b981" />
            <StatItem label="P50" value={formatMetric(metrics.optimized?.p50, 'μs')} color="#14b8a6" />
            <StatItem label="P95" value={formatMetric(metrics.optimized?.p95, 'μs')} color="#06b6d4" />
            <StatItem label="P99" value={formatMetric(metrics.optimized?.p99, 'μs')} color="#0ea5e9" />
            <StatItem label="Packets" value={formatPackets(metrics.optimized?.packetsProcessed)} color="#6366f1" />
          </div>
          <div style={styles.features}>
            <div style={styles.featuresLabel}>Bypass benefits</div>
            <ul style={styles.featuresList}>
              <li style={styles.featureItemPositive}><span style={styles.featureMarkerPos} aria-hidden>✓</span> Direct NIC access</li>
              <li style={styles.featureItemPositive}><span style={styles.featureMarkerPos} aria-hidden>✓</span> Zero-copy DMA</li>
              <li style={styles.featureItemPositive}><span style={styles.featureMarkerPos} aria-hidden>✓</span> CPU polling mode</li>
              <li style={styles.featureItemPositive}><span style={styles.featureMarkerPos} aria-hidden>✓</span> Cache-optimized</li>
            </ul>
          </div>
        </div>
      </div>

      {/* Improvement Metrics */}
      <div style={styles.improvementCard}>
        <h3 style={styles.cardTitle}>📈 Performance Improvement</h3>
        <div style={styles.improvementGrid}>
          <div style={styles.improvementStat}>
            <div style={styles.improvementValue}>{formatImprovement(metrics.improvement?.avgLatency, metrics.traditional?.packetsProcessed)}</div>
            <div style={styles.improvementLabel}>Faster Avg Latency</div>
          </div>
          <div style={styles.improvementStat}>
            <div style={styles.improvementValue}>{formatImprovement(metrics.improvement?.p99, metrics.traditional?.packetsProcessed)}</div>
            <div style={styles.improvementLabel}>Better P99 Latency</div>
          </div>
          <div style={styles.improvementStat}>
            <div style={styles.improvementValue}>{formatPackets((metrics.generator && metrics.generator.packetsGenerated) != null ? metrics.generator.packetsGenerated : 0)}</div>
            <div style={styles.improvementLabel}>Total Packets Generated</div>
          </div>
        </div>
      </div>

      {/* Latency Trends */}
      <div style={styles.chartCard}>
        <h3 style={styles.cardTitle}>Average Latency Over Time</h3>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={history}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis dataKey="time" stroke="#6b7280" />
            <YAxis stroke="#6b7280" label={{ value: 'Latency (μs)', angle: -90, position: 'insideLeft' }} />
            <Tooltip contentStyle={{background: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px'}} />
            <Legend />
            <Line type="monotone" dataKey="traditional" stroke="#ef4444" strokeWidth={2} name="Traditional" dot={false} />
            <Line type="monotone" dataKey="optimized" stroke="#10b981" strokeWidth={2} name="Optimized" dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>

      {/* P99 Trends */}
      <div style={styles.chartCard}>
        <h3 style={styles.cardTitle}>P99 Latency Comparison</h3>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={history}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis dataKey="time" stroke="#6b7280" />
            <YAxis stroke="#6b7280" label={{ value: 'Latency (μs)', angle: -90, position: 'insideLeft' }} />
            <Tooltip contentStyle={{background: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px'}} />
            <Legend />
            <Line type="monotone" dataKey="tradP99" stroke="#dc2626" strokeWidth={2} name="Traditional P99" dot={false} />
            <Line type="monotone" dataKey="optP99" stroke="#059669" strokeWidth={2} name="Optimized P99" dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function StatItem({ label, value, color }) {
  return (
    <div style={styles.statItem}>
      <div style={{...styles.statValue, color}}>{value}</div>
      <div style={styles.statLabel}>{label}</div>
    </div>
  );
}

function Feature({ text }) {
  return <div style={styles.feature}>{text}</div>;
}

const styles = {
  container: {
    minHeight: '100vh',
  },
  loading: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100vh',
    color: '#fff',
    fontSize: '18px'
  },
  spinner: {
    width: '50px',
    height: '50px',
    border: '4px solid rgba(255,255,255,0.3)',
    borderTop: '4px solid #fff',
    borderRadius: '50%',
    animation: 'spin 1s linear infinite',
    marginBottom: '20px'
  },
  header: {
    textAlign: 'center',
    marginBottom: '30px',
    color: '#fff'
  },
  title: {
    fontSize: '36px',
    fontWeight: 'bold',
    marginBottom: '10px'
  },
  subtitle: {
    fontSize: '18px',
    opacity: 0.9,
    marginBottom: '15px'
  },
  status: {
    display: 'inline-block',
    padding: '8px 16px',
    borderRadius: '20px',
    color: '#fff',
    fontWeight: 'bold',
    fontSize: '14px'
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))',
    gap: '20px',
    marginBottom: '20px'
  },
  card: {
    background: '#fff',
    borderRadius: '16px',
    padding: '24px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)'
  },
  cardHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '20px'
  },
  cardTitle: {
    fontSize: '20px',
    fontWeight: 'bold',
    color: '#1f2937'
  },
  badge: {
    padding: '4px 12px',
    background: '#3b82f6',
    color: '#fff',
    borderRadius: '12px',
    fontSize: '12px',
    fontWeight: 'bold'
  },
  stats: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: '15px',
    marginBottom: '20px'
  },
  statItem: {
    textAlign: 'center'
  },
  statValue: {
    fontSize: '24px',
    fontWeight: 'bold',
    marginBottom: '4px'
  },
  statLabel: {
    fontSize: '12px',
    color: '#6b7280',
    textTransform: 'uppercase',
    letterSpacing: '0.5px'
  },
  features: {
    paddingTop: '15px',
    borderTop: '1px solid #e5e7eb'
  },
  featuresLabel: {
    fontSize: '11px',
    fontWeight: 600,
    color: '#6b7280',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
    marginBottom: '8px'
  },
  featuresList: {
    listStyleType: 'none',
    margin: 0,
    padding: 0
  },
  featureItemNegative: {
    fontSize: '14px',
    color: '#374151',
    marginBottom: '6px',
    paddingLeft: '18px',
    display: 'flex',
    alignItems: 'center'
  },
  featureItemPositive: {
    fontSize: '14px',
    color: '#374151',
    marginBottom: '6px',
    paddingLeft: '18px',
    display: 'flex',
    alignItems: 'center'
  },
  featureMarkerNeg: {
    color: '#dc2626',
    marginRight: '8px',
    fontWeight: 'bold',
    fontSize: '16px'
  },
  featureMarkerPos: {
    color: '#059669',
    marginRight: '8px',
    fontWeight: 'bold',
    fontSize: '16px'
  },
  feature: {
    fontSize: '14px',
    color: '#374151'
  },
  improvementCard: {
    background: '#fff',
    borderRadius: '16px',
    padding: '24px',
    marginBottom: '20px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)'
  },
  improvementGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: '20px',
    marginTop: '20px'
  },
  improvementStat: {
    textAlign: 'center',
    padding: '20px',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    borderRadius: '12px',
    color: '#fff'
  },
  improvementValue: {
    fontSize: '36px',
    fontWeight: 'bold',
    marginBottom: '8px'
  },
  improvementLabel: {
    fontSize: '14px',
    opacity: 0.9
  },
  chartCard: {
    background: '#fff',
    borderRadius: '16px',
    padding: '24px',
    marginBottom: '20px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)'
  }
};
