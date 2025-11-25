import React, { useState, useEffect } from 'react';

export default function App() {
  const [metrics, setMetrics] = useState({ syncRequests: 0, writesQueued: 0, conflicts: 0 });
  const [devices, setDevices] = useState([]);
  const [selectedDevice, setSelectedDevice] = useState('device-1');
  const [connectionStatus, setConnectionStatus] = useState('disconnected');
  const [ws, setWs] = useState(null);
  const [logs, setLogs] = useState([]);

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    connectWebSocket();
    return () => ws?.close();
  }, [selectedDevice]);

  const fetchMetrics = async () => {
    try {
      const res = await fetch('http://localhost:3000/api/metrics');
      const data = await res.json();
      setMetrics(data);
    } catch (error) {
      console.error('Fetch metrics failed:', error);
    }
  };

  const connectWebSocket = () => {
    const websocket = new WebSocket(`ws://localhost:3000?deviceId=${selectedDevice}`);
    
    websocket.onopen = () => {
      setConnectionStatus('connected');
      addLog('✅ Connected to backend');
    };
    
    websocket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      addLog(`📨 Received: ${data.type}`);
    };
    
    websocket.onclose = () => {
      setConnectionStatus('disconnected');
      addLog('❌ Disconnected');
    };

    setWs(websocket);
  };

  const simulateOfflineWrite = async () => {
    const data = {
      deviceId: selectedDevice,
      key: `note-${Date.now()}`,
      value: `Offline note created at ${new Date().toISOString()}`,
      vectorClock: { [selectedDevice]: Math.floor(Math.random() * 10) }
    };

    try {
      const res = await fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      const result = await res.json();
      addLog(`✍️ Write queued: ${result.tempId}`);
    } catch (error) {
      addLog(`❌ Write failed: ${error.message}`);
    }
  };

  const simulateSync = async () => {
    try {
      const res = await fetch('http://localhost:3000/api/sync', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Cursor': '0' },
        body: JSON.stringify({ 
          deviceId: selectedDevice, 
          networkQuality: Math.random() > 0.5 ? 'high' : 'low'
        })
      });
      const result = await res.json();
      addLog(`🔄 Synced ${result.count} items (compressed: ${result.compressed})`);
    } catch (error) {
      addLog(`❌ Sync failed: ${error.message}`);
    }
  };

  const addLog = (message) => {
    setLogs(prev => [`[${new Date().toLocaleTimeString()}] ${message}`, ...prev].slice(0, 10));
  };

  return (
    <div style={{
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      minHeight: '100vh',
      padding: '20px'
    }}>
      <div style={{
        maxWidth: '1400px',
        margin: '0 auto',
        background: 'white',
        borderRadius: '16px',
        padding: '32px',
        boxShadow: '0 20px 60px rgba(0,0,0,0.3)'
      }}>
        <h1 style={{
          fontSize: '32px',
          fontWeight: '700',
          background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          marginBottom: '8px'
        }}>
          Mobile Backend Architecture
        </h1>
        <p style={{ color: '#64748b', marginBottom: '32px' }}>
          Real-time sync, optimistic writes, and conflict resolution
        </p>

        {/* Metrics */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '20px', marginBottom: '32px' }}>
          <MetricCard title="Sync Requests" value={metrics.syncRequests} color="#3b82f6" icon="🔄" />
          <MetricCard title="Writes Queued" value={metrics.writesQueued} color="#8b5cf6" icon="✍️" />
          <MetricCard title="Conflicts Resolved" value={metrics.conflicts} color="#ef4444" icon="⚠️" />
          <MetricCard 
            title="Connection Status" 
            value={connectionStatus} 
            color={connectionStatus === 'connected' ? '#10b981' : '#ef4444'} 
            icon={connectionStatus === 'connected' ? '✅' : '❌'}
          />
        </div>

        {/* Controls */}
        <div style={{
          background: '#f8fafc',
          borderRadius: '12px',
          padding: '24px',
          marginBottom: '32px'
        }}>
          <h3 style={{ fontSize: '18px', fontWeight: '600', marginBottom: '16px', color: '#1e293b' }}>
            Device Simulation
          </h3>
          
          <div style={{ display: 'flex', gap: '12px', marginBottom: '16px', flexWrap: 'wrap' }}>
            <select 
              value={selectedDevice}
              onChange={(e) => setSelectedDevice(e.target.value)}
              style={{
                padding: '12px 16px',
                borderRadius: '8px',
                border: '2px solid #e2e8f0',
                fontSize: '14px',
                fontWeight: '500',
                cursor: 'pointer'
              }}
            >
              {['device-1', 'device-2', 'device-3'].map(d => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>

            <Button onClick={simulateOfflineWrite} color="#8b5cf6">
              ✍️ Simulate Offline Write
            </Button>
            
            <Button onClick={simulateSync} color="#3b82f6">
              🔄 Trigger Sync
            </Button>
            
            <Button onClick={() => ws?.close()} color="#ef4444">
              📡 Disconnect
            </Button>
            
            <Button onClick={connectWebSocket} color="#10b981">
              🔌 Reconnect
            </Button>
          </div>
        </div>

        {/* Activity Log */}
        <div style={{
          background: '#0f172a',
          borderRadius: '12px',
          padding: '20px',
          maxHeight: '300px',
          overflow: 'auto'
        }}>
          <h3 style={{ fontSize: '16px', fontWeight: '600', marginBottom: '12px', color: '#f1f5f9' }}>
            Activity Log
          </h3>
          {logs.map((log, i) => (
            <div key={i} style={{
              padding: '8px 12px',
              marginBottom: '4px',
              background: '#1e293b',
              borderRadius: '6px',
              color: '#e2e8f0',
              fontSize: '13px',
              fontFamily: 'Monaco, monospace'
            }}>
              {log}
            </div>
          ))}
          {logs.length === 0 && (
            <div style={{ color: '#64748b', fontSize: '14px' }}>
              No activity yet. Try simulating writes or syncs.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function MetricCard({ title, value, color, icon }) {
  return (
    <div style={{
      background: 'white',
      borderRadius: '12px',
      padding: '24px',
      border: `2px solid ${color}20`,
      boxShadow: '0 4px 6px rgba(0,0,0,0.05)'
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
        <span style={{ fontSize: '14px', color: '#64748b', fontWeight: '500' }}>{title}</span>
        <span style={{ fontSize: '24px' }}>{icon}</span>
      </div>
      <div style={{ fontSize: '32px', fontWeight: '700', color }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </div>
    </div>
  );
}

function Button({ onClick, children, color }) {
  return (
    <button
      onClick={onClick}
      style={{
        padding: '12px 20px',
        background: color,
        color: 'white',
        border: 'none',
        borderRadius: '8px',
        fontSize: '14px',
        fontWeight: '600',
        cursor: 'pointer',
        transition: 'all 0.2s',
        boxShadow: `0 4px 12px ${color}40`
      }}
      onMouseOver={(e) => e.target.style.transform = 'translateY(-2px)'}
      onMouseOut={(e) => e.target.style.transform = 'translateY(0)'}
    >
      {children}
    </button>
  );
}
