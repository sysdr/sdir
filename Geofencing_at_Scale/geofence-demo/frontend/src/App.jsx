import React, { useState, useEffect, useRef } from 'react';
import { wsManager } from './websocket';

const App = () => {
  const [status, setStatus] = useState(null);
  const [geofences, setGeofences] = useState([]);
  const [vehicles, setVehicles] = useState([]);
  const [metrics, setMetrics] = useState(null);
  const [connected, setConnected] = useState(false);
  const canvasRef = useRef(null);

  useEffect(() => {
    // Fetch initial data
    fetch('http://localhost:3000/api/status')
      .then(res => res.json())
      .then(setStatus)
      .catch(err => console.error('Failed to fetch status:', err));

    fetch('http://localhost:3000/api/geofences')
      .then(res => res.json())
      .then(setGeofences)
      .catch(err => console.error('Failed to fetch geofences:', err));

    // Set up WebSocket listener
    const removeListener = wsManager.addListener((event) => {
      switch (event.type) {
        case 'open':
          setConnected(true);
          break;
        case 'close':
        case 'error':
          setConnected(false);
          break;
        case 'message':
          if (event.data && event.data.type === 'update') {
            setVehicles(event.data.vehicles);
            setMetrics(event.data.metrics);
          }
          break;
      }
    });

    // Connect WebSocket (will only connect if not already connected)
    wsManager.connect();

    // Update connected state based on current connection status
    setConnected(wsManager.isConnected());

    return () => {
      // Remove listener but don't disconnect (singleton persists)
      removeListener();
    };
  }, []);

  // Draw map on canvas
  useEffect(() => {
    if (!canvasRef.current || !geofences.length) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    const scale = canvas.width / 1000;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw geofences
    geofences.forEach(fence => {
      ctx.fillStyle = 'rgba(59, 130, 246, 0.1)';
      ctx.strokeStyle = '#3b82f6';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(
        fence.center.x * scale,
        fence.center.y * scale,
        fence.radius * scale,
        0,
        Math.PI * 2
      );
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = '#1e40af';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(
        fence.name,
        fence.center.x * scale,
        fence.center.y * scale
      );
    });

    // Draw vehicles
    vehicles.forEach(vehicle => {
      const inZone = vehicle.currentZones.length > 0;
      ctx.fillStyle = inZone ? '#10b981' : '#6366f1';
      ctx.beginPath();
      ctx.arc(
        vehicle.x * scale,
        vehicle.y * scale,
        2,
        0,
        Math.PI * 2
      );
      ctx.fill();
    });

  }, [geofences, vehicles]);

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <h1 style={styles.title}>🌍 Geofencing at Scale</h1>
        <div style={styles.badge}>
          <span style={{...styles.indicator, backgroundColor: connected ? '#10b981' : '#ef4444'}}></span>
          {connected ? 'Connected' : 'Disconnected'}
        </div>
      </div>

      <div style={styles.grid}>
        {/* Map Visualization */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Live Map</h2>
          <canvas 
            ref={canvasRef}
            width={600}
            height={600}
            style={styles.canvas}
          />
          <div style={styles.legend}>
            <span><span style={{...styles.dot, backgroundColor: '#6366f1'}}></span> Vehicles</span>
            <span><span style={{...styles.dot, backgroundColor: '#10b981'}}></span> In Zone</span>
            <span><span style={{...styles.dot, backgroundColor: '#3b82f6'}}></span> Geofences</span>
          </div>
        </div>

        {/* QuadTree Metrics */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>QuadTree Performance</h2>
          {status && (
            <div style={styles.metrics}>
              <MetricRow label="Max Depth" value={status.quadtree.maxDepth} />
              <MetricRow label="Total Nodes" value={status.quadtree.nodeCount} />
              <MetricRow label="Insert Time" value={`${metrics?.quadtree.insertTime || 0}ms`} />
              <MetricRow label="Query Time" value={`${metrics?.quadtree.queryTime || 0}ms`} />
              <MetricRow label="Queries" value={metrics?.quadtree.queriesPerformed || 0} />
            </div>
          )}
          <div style={styles.insight}>
            ✨ QuadTree subdivides space recursively, creating deeper trees in dense areas.
          </div>
        </div>

        {/* Geohash Metrics */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Geohash Performance</h2>
          {status && (
            <div style={styles.metrics}>
              <MetricRow label="Total Cells" value={status.geohash.totalCells} />
              <MetricRow label="Avg Objects/Cell" value={status.geohash.avgObjectsPerCell.toFixed(2)} />
              <MetricRow label="Insert Time" value={`${metrics?.geohash.insertTime || 0}ms`} />
              <MetricRow label="Query Time" value={`${metrics?.geohash.queryTime || 0}ms`} />
              <MetricRow label="Queries" value={metrics?.geohash.queriesPerformed || 0} />
            </div>
          )}
          <div style={styles.insight}>
            ✨ Geohash encodes locations as strings, enabling fast prefix-based queries.
          </div>
        </div>

        {/* System Metrics */}
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>System Metrics</h2>
          <div style={styles.metrics}>
            <MetricRow label="Total Vehicles" value={status?.vehicles || 0} />
            <MetricRow label="Active Geofences" value={status?.geofences || 0} />
            <MetricRow label="Boundary Events" value={metrics?.boundaryEvents || 0} />
            <MetricRow label="Update Cycles" value={metrics?.updateCount || 0} />
            <MetricRow 
              label="Vehicles in Zones" 
              value={vehicles.filter(v => v.currentZones.length > 0).length} 
            />
          </div>
          <div style={styles.insight}>
            ✨ Tracking {vehicles.length} vehicles across multiple zones in real-time.
          </div>
        </div>
      </div>

      <div style={styles.footer}>
        <p>⚡ Processing 1,000 location updates per second with spatial indexing</p>
      </div>
    </div>
  );
};

const MetricRow = ({ label, value }) => (
  <div style={styles.metricRow}>
    <span style={styles.metricLabel}>{label}</span>
    <span style={styles.metricValue}>{value}</span>
  </div>
);

const styles = {
  container: {
    maxWidth: '1400px',
    margin: '0 auto',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '30px',
    padding: '20px',
    background: 'white',
    borderRadius: '12px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  title: {
    fontSize: '32px',
    color: '#1e293b',
    fontWeight: '700',
  },
  badge: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 16px',
    background: '#f1f5f9',
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: '500',
    color: '#475569',
  },
  indicator: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))',
    gap: '20px',
    marginBottom: '20px',
  },
  card: {
    background: 'white',
    borderRadius: '12px',
    padding: '24px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  cardTitle: {
    fontSize: '20px',
    fontWeight: '600',
    color: '#1e293b',
    marginBottom: '20px',
    borderBottom: '2px solid #3b82f6',
    paddingBottom: '8px',
  },
  canvas: {
    width: '100%',
    height: 'auto',
    border: '2px solid #e2e8f0',
    borderRadius: '8px',
    background: '#f8fafc',
  },
  legend: {
    display: 'flex',
    gap: '20px',
    marginTop: '12px',
    fontSize: '14px',
    color: '#475569',
  },
  dot: {
    display: 'inline-block',
    width: '12px',
    height: '12px',
    borderRadius: '50%',
    marginRight: '6px',
  },
  metrics: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  metricRow: {
    display: 'flex',
    justifyContent: 'space-between',
    padding: '12px',
    background: '#f8fafc',
    borderRadius: '6px',
    borderLeft: '3px solid #3b82f6',
  },
  metricLabel: {
    fontSize: '14px',
    color: '#64748b',
    fontWeight: '500',
  },
  metricValue: {
    fontSize: '16px',
    color: '#1e293b',
    fontWeight: '600',
  },
  insight: {
    marginTop: '16px',
    padding: '12px',
    background: '#eff6ff',
    borderRadius: '6px',
    fontSize: '13px',
    color: '#1e40af',
    borderLeft: '3px solid #3b82f6',
  },
  footer: {
    textAlign: 'center',
    padding: '20px',
    background: 'white',
    borderRadius: '12px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
    color: '#475569',
    fontSize: '14px',
  },
};

export default App;
