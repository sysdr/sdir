import React, { useState, useEffect } from 'react';

const API_URL = 'http://localhost:3001';

export default function App() {
  const [state, setState] = useState({ resources: [], locked: false });
  const [metrics, setMetrics] = useState({});
  const [deployments, setDeployments] = useState([]);
  const [drift, setDrift] = useState({ driftDetected: false, driftedResources: [] });
  const [logs, setLogs] = useState([]);
  const [ws, setWs] = useState(null);

  useEffect(() => {
    fetchState();
    fetchMetrics();
    fetchDeployments();
    checkDrift();

    const websocket = new WebSocket('ws://localhost:3001');
    websocket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      addLog(data.type, JSON.stringify(data));
      
      if (data.type.includes('resource') || data.type.includes('lock')) {
        fetchState();
        fetchMetrics();
      }
      if (data.type === 'drift_detected') {
        checkDrift();
      }
    };
    setWs(websocket);

    const interval = setInterval(() => {
      checkDrift();
      fetchMetrics();
    }, 10000);

    return () => {
      websocket.close();
      clearInterval(interval);
    };
  }, []);

  const addLog = (type, message) => {
    setLogs(prev => [{
      time: new Date().toLocaleTimeString(),
      type,
      message
    }, ...prev].slice(0, 50));
  };

  const fetchState = async () => {
    const res = await fetch(`${API_URL}/api/state`);
    const data = await res.json();
    setState(data);
  };

  const fetchMetrics = async () => {
    const res = await fetch(`${API_URL}/api/metrics`);
    const data = await res.json();
    setMetrics(data);
  };

  const fetchDeployments = async () => {
    const res = await fetch(`${API_URL}/api/deployments`);
    const data = await res.json();
    setDeployments(data);
  };

  const checkDrift = async () => {
    const res = await fetch(`${API_URL}/api/drift/check`);
    const data = await res.json();
    setDrift(data);
  };

  const applyInfrastructure = async () => {
    const sampleResources = [
      {
        resource_type: 'compute',
        resource_name: 'web-server-01',
        config: { instance_type: 't3.medium', region: 'us-east-1' }
      },
      {
        resource_type: 'database',
        resource_name: 'postgres-db',
        config: { engine: 'postgresql', version: '14.5' }
      },
      {
        resource_type: 'storage',
        resource_name: 'backup-bucket',
        config: { storage_class: 'STANDARD', versioning: true }
      }
    ];

    try {
      const lockRes = await fetch(`${API_URL}/api/lock`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ operation: 'apply' })
      });
      
      if (!lockRes.ok) {
        addLog('error', 'Failed to acquire lock');
        return;
      }

      const lock = await lockRes.json();
      addLog('lock_acquired', `Lock: ${lock.lockId}`);

      await fetch(`${API_URL}/api/apply`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ resources: sampleResources })
      });

      await fetch(`${API_URL}/api/unlock`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ lockId: lock.lockId })
      });

      fetchDeployments();
      addLog('apply_success', 'Infrastructure applied successfully');
    } catch (error) {
      addLog('error', error.message);
    }
  };

  const simulateDrift = async () => {
    if (state.resources.length === 0) {
      addLog('error', 'No resources to modify');
      return;
    }

    const resource = state.resources[0];
    await fetch(`${API_URL}/api/drift/manual-change`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        resourceName: resource.resource_name,
        change: 'manual_configuration_change'
      })
    });

    addLog('drift_simulated', `Manual change to ${resource.resource_name}`);
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>Infrastructure as Code Dashboard</h1>
        <div style={styles.statusBadge}>
          <div style={{...styles.statusDot, background: state.locked ? '#ef4444' : '#10b981'}} />
          <span>State {state.locked ? 'Locked' : 'Unlocked'}</span>
        </div>
      </header>

      <div style={styles.metricsGrid}>
        <div style={styles.metricCard}>
          <div style={styles.metricValue}>{metrics.totalResources || 0}</div>
          <div style={styles.metricLabel}>Resources</div>
        </div>
        <div style={styles.metricCard}>
          <div style={styles.metricValue}>{metrics.totalDeployments || 0}</div>
          <div style={styles.metricLabel}>Deployments</div>
        </div>
        <div style={styles.metricCard}>
          <div style={{...styles.metricValue, color: drift.driftDetected ? '#ef4444' : '#10b981'}}>
            {metrics.totalDrifts || 0}
          </div>
          <div style={styles.metricLabel}>Drift Events</div>
        </div>
        <div style={styles.metricCard}>
          <div style={{...styles.metricValue, color: state.locked ? '#ef4444' : '#64748b'}}>
            {state.locks?.length || 0}
          </div>
          <div style={styles.metricLabel}>Active Locks</div>
        </div>
      </div>

      <div style={styles.actionsBar}>
        <button onClick={applyInfrastructure} style={styles.button}>
          Apply Infrastructure
        </button>
        <button onClick={simulateDrift} style={{...styles.button, background: '#f59e0b'}}>
          Simulate Drift
        </button>
        <button onClick={checkDrift} style={{...styles.button, background: '#8b5cf6'}}>
          Check Drift
        </button>
      </div>

      <div style={styles.mainGrid}>
        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Infrastructure Resources</h2>
          <div style={styles.resourceList}>
            {state.resources.length === 0 ? (
              <div style={styles.emptyState}>No resources deployed</div>
            ) : (
              state.resources.map(resource => (
                <div key={resource.id} style={styles.resourceCard}>
                  <div style={styles.resourceHeader}>
                    <span style={styles.resourceType}>{resource.resource_type}</span>
                    <span style={{
                      ...styles.statusLabel,
                      background: resource.status === 'active' ? '#dcfce7' : '#fee2e2',
                      color: resource.status === 'active' ? '#166534' : '#991b1b'
                    }}>
                      {resource.status}
                    </span>
                  </div>
                  <div style={styles.resourceName}>{resource.resource_name}</div>
                  <div style={styles.resourceConfig}>
                    {JSON.stringify(JSON.parse(resource.config), null, 2)}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Deployment History</h2>
          <div style={styles.deploymentList}>
            {deployments.map(dep => (
              <div key={dep.id} style={styles.deploymentItem}>
                <div style={styles.deploymentOp}>{dep.operation}</div>
                <div style={styles.deploymentMeta}>
                  {dep.resources_affected} resources • {new Date(dep.timestamp).toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>
            Drift Detection
            {drift.driftDetected && <span style={styles.alertBadge}>!</span>}
          </h2>
          <div style={styles.driftContent}>
            {drift.driftDetected ? (
              <>
                <div style={styles.driftAlert}>
                  Drift detected in {drift.driftedResources.length} resource(s)
                </div>
                {drift.driftedResources.map(resource => (
                  <div key={resource.id} style={styles.driftItem}>
                    {resource.resource_name} - {resource.status}
                  </div>
                ))}
              </>
            ) : (
              <div style={styles.noDrift}>No drift detected</div>
            )}
          </div>
        </div>

        <div style={styles.section}>
          <h2 style={styles.sectionTitle}>Activity Logs</h2>
          <div style={styles.logsList}>
            {logs.map((log, idx) => (
              <div key={idx} style={styles.logItem}>
                <span style={styles.logTime}>{log.time}</span>
                <span style={styles.logType}>{log.type}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

const styles = {
  container: {
    minHeight: '100vh',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    padding: '20px',
  },
  header: {
    background: 'white',
    borderRadius: '12px',
    padding: '30px',
    marginBottom: '20px',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  title: {
    fontSize: '28px',
    fontWeight: 'bold',
    color: '#1e293b',
  },
  statusBadge: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 16px',
    background: '#f1f5f9',
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: '500',
  },
  statusDot: {
    width: '10px',
    height: '10px',
    borderRadius: '50%',
  },
  metricsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: '20px',
    marginBottom: '20px',
  },
  metricCard: {
    background: 'white',
    borderRadius: '12px',
    padding: '24px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  metricValue: {
    fontSize: '36px',
    fontWeight: 'bold',
    color: '#3b82f6',
    marginBottom: '8px',
  },
  metricLabel: {
    fontSize: '14px',
    color: '#64748b',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  actionsBar: {
    display: 'flex',
    gap: '12px',
    marginBottom: '20px',
    flexWrap: 'wrap',
  },
  button: {
    padding: '12px 24px',
    background: '#3b82f6',
    color: 'white',
    border: 'none',
    borderRadius: '8px',
    fontSize: '14px',
    fontWeight: '600',
    cursor: 'pointer',
    transition: 'all 0.2s',
  },
  mainGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))',
    gap: '20px',
  },
  section: {
    background: 'white',
    borderRadius: '12px',
    padding: '24px',
    boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
  },
  sectionTitle: {
    fontSize: '18px',
    fontWeight: 'bold',
    color: '#1e293b',
    marginBottom: '16px',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  alertBadge: {
    background: '#ef4444',
    color: 'white',
    width: '20px',
    height: '20px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    fontWeight: 'bold',
  },
  resourceList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  resourceCard: {
    border: '1px solid #e2e8f0',
    borderRadius: '8px',
    padding: '16px',
    background: '#f8fafc',
  },
  resourceHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  resourceType: {
    fontSize: '12px',
    color: '#64748b',
    textTransform: 'uppercase',
    fontWeight: '600',
  },
  statusLabel: {
    padding: '4px 12px',
    borderRadius: '12px',
    fontSize: '11px',
    fontWeight: '600',
  },
  resourceName: {
    fontSize: '16px',
    fontWeight: '600',
    color: '#1e293b',
    marginBottom: '8px',
  },
  resourceConfig: {
    fontSize: '12px',
    color: '#64748b',
    background: 'white',
    padding: '8px',
    borderRadius: '4px',
    fontFamily: 'monospace',
    whiteSpace: 'pre',
  },
  emptyState: {
    textAlign: 'center',
    padding: '40px',
    color: '#94a3b8',
    fontSize: '14px',
  },
  deploymentList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    maxHeight: '300px',
    overflowY: 'auto',
  },
  deploymentItem: {
    padding: '12px',
    background: '#f8fafc',
    borderRadius: '6px',
    border: '1px solid #e2e8f0',
  },
  deploymentOp: {
    fontSize: '14px',
    fontWeight: '600',
    color: '#1e293b',
    marginBottom: '4px',
  },
  deploymentMeta: {
    fontSize: '12px',
    color: '#64748b',
  },
  driftContent: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  driftAlert: {
    padding: '12px',
    background: '#fee2e2',
    color: '#991b1b',
    borderRadius: '6px',
    fontSize: '14px',
    fontWeight: '500',
  },
  driftItem: {
    padding: '10px',
    background: '#fef3c7',
    borderRadius: '6px',
    fontSize: '13px',
    color: '#92400e',
  },
  noDrift: {
    padding: '20px',
    textAlign: 'center',
    color: '#10b981',
    fontSize: '14px',
    fontWeight: '500',
  },
  logsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
    maxHeight: '300px',
    overflowY: 'auto',
  },
  logItem: {
    padding: '8px 12px',
    background: '#f8fafc',
    borderRadius: '4px',
    fontSize: '12px',
    display: 'flex',
    gap: '12px',
  },
  logTime: {
    color: '#64748b',
    fontFamily: 'monospace',
  },
  logType: {
    color: '#3b82f6',
    fontWeight: '500',
  },
};
