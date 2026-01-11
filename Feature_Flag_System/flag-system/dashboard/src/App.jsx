import React, { useState, useEffect } from 'react';

const API_URL = 'http://localhost:3000';
const WS_URL = 'ws://localhost:3000';

export default function App() {
  const [flags, setFlags] = useState([]);
  const [stats, setStats] = useState({});
  const [ws, setWs] = useState(null);
  const [evaluations, setEvaluations] = useState([]);

  useEffect(() => {
    fetchFlags();
    fetchStats();
    
    const socket = new WebSocket(WS_URL);
    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'flag_updated') {
        fetchFlags();
      }
    };
    setWs(socket);
    
    const statsInterval = setInterval(fetchStats, 2000);
    
    return () => {
      socket.close();
      clearInterval(statsInterval);
    };
  }, []);

  const fetchFlags = async () => {
    const res = await fetch(`${API_URL}/flags`);
    const data = await res.json();
    setFlags(data);
  };

  const fetchStats = async () => {
    const res = await fetch(`${API_URL}/stats`);
    const data = await res.json();
    setStats(data);
  };

  const toggleFlag = async (id) => {
    await fetch(`${API_URL}/flags/${id}/toggle`, { method: 'POST' });
  };

  const updateRollout = async (id, percentage) => {
    await fetch(`${API_URL}/flags/${id}/rollout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ percentage })
    });
  };

  const testEvaluation = async (flagId) => {
    const userId = `user-${Math.floor(Math.random() * 1000)}`;
    const context = { segment: 'beta', region: 'US' };
    
    const res = await fetch(`${API_URL}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flagId, userId, context })
    });
    
    const data = await res.json();
    setEvaluations(prev => [{ ...data, timestamp: new Date() }, ...prev.slice(0, 19)]);
  };

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.title}>🚩 Feature Flag System</h1>
        <div style={styles.statsBar}>
          <div style={styles.stat}>
            <div style={styles.statValue}>{stats.total_flags || 0}</div>
            <div style={styles.statLabel}>Total Flags</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statValue}>{stats.total_evaluations || 0}</div>
            <div style={styles.statLabel}>Total Evaluations</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statValue}>
              {stats.recent_evaluations?.reduce((sum, r) => sum + parseInt(r.count), 0) || 0}
            </div>
            <div style={styles.statLabel}>Evals/min</div>
          </div>
        </div>
      </header>

      <div style={styles.content}>
        <div style={styles.flagsSection}>
          <h2 style={styles.sectionTitle}>Feature Flags</h2>
          <div style={styles.flagGrid}>
            {flags.map(flag => (
              <div key={flag.id} style={styles.flagCard}>
                <div style={styles.flagHeader}>
                  <div>
                    <h3 style={styles.flagName}>{flag.name}</h3>
                    <p style={styles.flagDesc}>{flag.description}</p>
                  </div>
                  <button
                    onClick={() => toggleFlag(flag.id)}
                    style={{
                      ...styles.toggleBtn,
                      ...(flag.enabled ? styles.toggleBtnOn : styles.toggleBtnOff)
                    }}
                  >
                    {flag.enabled ? 'ON' : 'OFF'}
                  </button>
                </div>
                
                <div style={styles.rolloutSection}>
                  <div style={styles.rolloutHeader}>
                    <span style={styles.rolloutLabel}>Rollout: {flag.rollout_percentage}%</span>
                    <button
                      onClick={() => testEvaluation(flag.id)}
                      style={styles.testBtn}
                    >
                      Test
                    </button>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={flag.rollout_percentage}
                    onChange={(e) => updateRollout(flag.id, parseInt(e.target.value))}
                    style={styles.slider}
                  />
                  <div style={styles.progressBar}>
                    <div 
                      style={{
                        ...styles.progressFill,
                        width: `${flag.rollout_percentage}%`
                      }}
                    />
                  </div>
                </div>
                
                {flag.targeting_rules && Object.keys(
                  typeof flag.targeting_rules === 'string' 
                    ? JSON.parse(flag.targeting_rules) 
                    : flag.targeting_rules
                ).length > 0 && (
                  <div style={styles.targeting}>
                    <strong>Targeting:</strong> {JSON.stringify(
                      typeof flag.targeting_rules === 'string' 
                        ? JSON.parse(flag.targeting_rules) 
                        : flag.targeting_rules
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <div style={styles.evalsSection}>
          <h2 style={styles.sectionTitle}>Recent Evaluations</h2>
          <div style={styles.evalsList}>
            {evaluations.map((evaluation, i) => (
              <div key={i} style={styles.evalItem}>
                <span style={evaluation.enabled ? styles.evalEnabled : styles.evalDisabled}>
                  {evaluation.enabled ? '✓' : '✗'}
                </span>
                <span style={styles.evalFlag}>{evaluation.flagId}</span>
                <span style={styles.evalUser}>{evaluation.userId}</span>
                <span style={styles.evalTime}>
                  {evaluation.timestamp.toLocaleTimeString()}
                </span>
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
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    minHeight: '100vh',
    padding: '20px',
  },
  header: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    marginBottom: '20px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  title: {
    margin: '0 0 20px 0',
    fontSize: '32px',
    color: '#2d3748',
  },
  statsBar: {
    display: 'flex',
    gap: '30px',
  },
  stat: {
    flex: 1,
    textAlign: 'center',
  },
  statValue: {
    fontSize: '36px',
    fontWeight: 'bold',
    color: '#3b82f6',
  },
  statLabel: {
    fontSize: '14px',
    color: '#718096',
    marginTop: '5px',
  },
  content: {
    display: 'grid',
    gridTemplateColumns: '2fr 1fr',
    gap: '20px',
  },
  flagsSection: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  sectionTitle: {
    margin: '0 0 20px 0',
    fontSize: '24px',
    color: '#2d3748',
  },
  flagGrid: {
    display: 'grid',
    gap: '15px',
  },
  flagCard: {
    background: '#f7fafc',
    borderRadius: '12px',
    padding: '20px',
    border: '2px solid #e2e8f0',
  },
  flagHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '15px',
  },
  flagName: {
    margin: '0 0 5px 0',
    fontSize: '18px',
    color: '#2d3748',
  },
  flagDesc: {
    margin: 0,
    fontSize: '14px',
    color: '#718096',
  },
  toggleBtn: {
    padding: '8px 20px',
    border: 'none',
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: 'bold',
    cursor: 'pointer',
    transition: 'all 0.3s',
  },
  toggleBtnOn: {
    background: '#48bb78',
    color: 'white',
  },
  toggleBtnOff: {
    background: '#cbd5e0',
    color: '#4a5568',
  },
  rolloutSection: {
    marginTop: '15px',
  },
  rolloutHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '10px',
  },
  rolloutLabel: {
    fontSize: '14px',
    fontWeight: 'bold',
    color: '#4a5568',
  },
  testBtn: {
    padding: '5px 15px',
    background: '#3b82f6',
    color: 'white',
    border: 'none',
    borderRadius: '6px',
    fontSize: '12px',
    cursor: 'pointer',
  },
  slider: {
    width: '100%',
    marginBottom: '10px',
  },
  progressBar: {
    height: '8px',
    background: '#e2e8f0',
    borderRadius: '4px',
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    background: 'linear-gradient(90deg, #3b82f6, #60a5fa)',
    transition: 'width 0.3s',
  },
  targeting: {
    marginTop: '15px',
    padding: '10px',
    background: '#edf2f7',
    borderRadius: '6px',
    fontSize: '12px',
    color: '#4a5568',
  },
  evalsSection: {
    background: 'white',
    borderRadius: '16px',
    padding: '30px',
    boxShadow: '0 10px 30px rgba(0,0,0,0.2)',
  },
  evalsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '10px',
  },
  evalItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
    padding: '12px',
    background: '#f7fafc',
    borderRadius: '8px',
    fontSize: '13px',
  },
  evalEnabled: {
    color: '#48bb78',
    fontWeight: 'bold',
    fontSize: '16px',
  },
  evalDisabled: {
    color: '#f56565',
    fontWeight: 'bold',
    fontSize: '16px',
  },
  evalFlag: {
    flex: 1,
    color: '#2d3748',
    fontWeight: '500',
  },
  evalUser: {
    color: '#718096',
    fontSize: '12px',
  },
  evalTime: {
    color: '#a0aec0',
    fontSize: '11px',
  },
};
