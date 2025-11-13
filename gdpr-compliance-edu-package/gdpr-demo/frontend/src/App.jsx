import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API_URL = 'http://localhost:3001/api';
const WS_URL = 'ws://localhost:3001';

function App() {
  const [stats, setStats] = useState({
    totalUsers: 0,
    deletionRequests: 0,
    activeConsents: 0,
    auditEntries: 0
  });
  
  const [formData, setFormData] = useState({
    email: '',
    name: '',
    phone: '',
    consents: {
      marketing: false,
      analytics: false,
      profiling: false,
      thirdParty: false
    }
  });

  const [users, setUsers] = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);
  const [deletionQueue, setDeletionQueue] = useState([]);
  const [message, setMessage] = useState(null);
  const [ws, setWs] = useState(null);

  useEffect(() => {
    loadStats();
    loadAuditLogs();
    loadDeletionQueue();
    loadUsers();
    
    // WebSocket connection with retry logic
    let websocket = null;
    let reconnectAttempts = 0;
    const maxReconnectAttempts = 5;
    let reconnectTimeout = null;
    let isIntentionalClose = false;

    const connectWebSocket = () => {
      try {
        websocket = new WebSocket(WS_URL);
        
        websocket.onopen = () => {
          console.log('WebSocket connected');
          reconnectAttempts = 0; // Reset on successful connection
        };
        
        websocket.onerror = (error) => {
          // Only log if it's not a connection attempt error
          if (websocket?.readyState === WebSocket.CLOSED) {
            // Connection failed, will retry
            return;
          }
        };
        
        websocket.onclose = (event) => {
          if (!isIntentionalClose && reconnectAttempts < maxReconnectAttempts) {
            // Attempt to reconnect with exponential backoff
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 10000);
            reconnectAttempts++;
            reconnectTimeout = setTimeout(() => {
              connectWebSocket();
            }, delay);
          }
        };
        
        websocket.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            
            if (data.type === 'audit') {
              loadAuditLogs();
              loadStats();
            } else if (data.type === 'deletion_progress') {
              loadDeletionQueue();
              loadUsers();
            } else if (data.type === 'consent_change') {
              loadStats();
            }
          } catch (error) {
            console.error('Failed to parse WebSocket message:', error);
          }
        };
        
        setWs(websocket);
      } catch (error) {
        console.error('Failed to create WebSocket connection:', error);
        // Retry after a delay
        if (reconnectAttempts < maxReconnectAttempts) {
          reconnectTimeout = setTimeout(() => {
            reconnectAttempts++;
            connectWebSocket();
          }, 2000);
        }
      }
    };

    // Initial connection attempt with a small delay to allow backend to be ready
    const initialDelay = setTimeout(() => {
      connectWebSocket();
    }, 1000);
    
    return () => {
      clearTimeout(initialDelay);
      isIntentionalClose = true;
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }
      if (websocket) {
        websocket.close();
      }
    };
  }, []);

  const loadStats = async () => {
    try {
      const response = await axios.get(`${API_URL}/stats`);
      setStats(response.data);
    } catch (error) {
      console.error('Failed to load stats:', error);
    }
  };

  const loadAuditLogs = async () => {
    try {
      const response = await axios.get(`${API_URL}/audit-logs`);
      setAuditLogs(response.data);
    } catch (error) {
      console.error('Failed to load audit logs:', error);
    }
  };

  const loadDeletionQueue = async () => {
    try {
      const response = await axios.get(`${API_URL}/deletion-queue`);
      setDeletionQueue(response.data);
    } catch (error) {
      console.error('Failed to load deletion queue:', error);
    }
  };

  const loadUsers = async () => {
    try {
      const response = await axios.get(`${API_URL}/users`);
      setUsers(response.data);
    } catch (error) {
      console.error('Failed to load users:', error);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const response = await axios.post(`${API_URL}/users`, formData);
      setMessage({ type: 'success', text: `✓ User created: ${response.data.userId}` });
      setFormData({
        email: '',
        name: '',
        phone: '',
        consents: { marketing: false, analytics: false, profiling: false, thirdParty: false }
      });
      loadStats();
      loadUsers();
    } catch (error) {
      setMessage({ type: 'error', text: `✗ Error: ${error.response?.data?.error || error.message}` });
    }
  };

  const handleDelete = async (userId) => {
    if (!confirm('Are you sure you want to delete this user? This will trigger GDPR erasure across all subsystems.')) {
      return;
    }

    try {
      await axios.delete(`${API_URL}/users/${userId}`);
      setMessage({ type: 'success', text: '✓ Deletion request submitted. Watch the deletion queue below.' });
      loadStats();
      loadUsers();
      loadDeletionQueue();
    } catch (error) {
      setMessage({ type: 'error', text: `✗ Error: ${error.response?.data?.error || error.message}` });
    }
  };

  const handleExport = async (userId) => {
    try {
      const response = await axios.get(`${API_URL}/users/${userId}/export`);
      const blob = new Blob([JSON.stringify(response.data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `user-data-${userId}.json`;
      a.click();
      setMessage({ type: 'success', text: '✓ Data exported successfully (Right to Data Portability)' });
    } catch (error) {
      setMessage({ type: 'error', text: `✗ Error: ${error.response?.data?.error || error.message}` });
    }
  };

  const handleConsentChange = async (userId, consentType, newStatus) => {
    try {
      await axios.post(`${API_URL}/users/${userId}/consent`, {
        consentType,
        status: newStatus
      });
      setMessage({ type: 'success', text: `✓ Consent for ${consentType} updated` });
    } catch (error) {
      setMessage({ type: 'error', text: `✗ Error: ${error.response?.data?.error || error.message}` });
    }
  };

  return (
    <div className="dashboard">
      <div className="header">
        <h1>🔒 GDPR Privacy Compliance Dashboard</h1>
        <p>Real-time data subject rights management, consent tracking, and audit logging</p>
      </div>

      {message && (
        <div className={`message ${message.type}`}>
          {message.text}
        </div>
      )}

      <div className="stats-grid">
        <div className="stat-card users">
          <h3>Active Users</h3>
          <div className="value">{stats.totalUsers}</div>
        </div>
        <div className="stat-card deletions">
          <h3>Deletion Requests</h3>
          <div className="value">{stats.deletionRequests}</div>
        </div>
        <div className="stat-card consents">
          <h3>Active Consents</h3>
          <div className="value">{stats.activeConsents}</div>
        </div>
        <div className="stat-card audits">
          <h3>Audit Entries</h3>
          <div className="value">{stats.auditEntries}</div>
        </div>
      </div>

      <div className="main-grid">
        <div className="card">
          <h2>Create User with Consent</h2>
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label>Email Address</label>
              <input
                type="email"
                value={formData.email}
                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                required
                placeholder="user@example.com"
              />
            </div>
            <div className="form-group">
              <label>Full Name</label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                required
                placeholder="John Doe"
              />
            </div>
            <div className="form-group">
              <label>Phone Number</label>
              <input
                type="tel"
                value={formData.phone}
                onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                placeholder="+1234567890"
              />
            </div>
            <div className="form-group">
              <label>Consent Preferences</label>
              <div className="checkbox-group">
                <label>
                  <input
                    type="checkbox"
                    checked={formData.consents.marketing}
                    onChange={(e) => setFormData({
                      ...formData,
                      consents: { ...formData.consents, marketing: e.target.checked }
                    })}
                  />
                  Marketing
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={formData.consents.analytics}
                    onChange={(e) => setFormData({
                      ...formData,
                      consents: { ...formData.consents, analytics: e.target.checked }
                    })}
                  />
                  Analytics
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={formData.consents.profiling}
                    onChange={(e) => setFormData({
                      ...formData,
                      consents: { ...formData.consents, profiling: e.target.checked }
                    })}
                  />
                  Profiling
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={formData.consents.thirdParty}
                    onChange={(e) => setFormData({
                      ...formData,
                      consents: { ...formData.consents, thirdParty: e.target.checked }
                    })}
                  />
                  Third-Party Sharing
                </label>
              </div>
            </div>
            <button type="submit">Create User</button>
          </form>
        </div>

        <div className="card">
          <h2>Manage Users</h2>
          <div className="user-list">
            {users.length === 0 ? (
              <p style={{ color: '#999', textAlign: 'center', padding: '20px' }}>
                No users created yet. Create a user to see them here.
              </p>
            ) : (
              users.map(user => (
                <div key={user.id} className="user-item">
                  <div className="user-info">
                    <h4>{user.name}</h4>
                    <p>{user.email}</p>
                  </div>
                  <div className="user-actions">
                    <button onClick={() => handleExport(user.id)}>Export</button>
                    <button className="secondary" onClick={() => handleDelete(user.id)}>Delete</button>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="deletion-progress">
        <h2>Deletion Queue (Right to Erasure)</h2>
        {deletionQueue.length === 0 ? (
          <p style={{ color: '#999', textAlign: 'center', padding: '20px' }}>
            No deletion requests in queue
          </p>
        ) : (
          deletionQueue.slice(0, 5).map(item => {
            // Handle subsystems_completed - it might be a string, array, or null
            let completed = [];
            try {
              if (typeof item.subsystems_completed === 'string') {
                completed = JSON.parse(item.subsystems_completed || '[]');
              } else if (Array.isArray(item.subsystems_completed)) {
                completed = item.subsystems_completed;
              } else if (item.subsystems_completed) {
                completed = [item.subsystems_completed];
              }
            } catch (error) {
              console.error('Failed to parse subsystems_completed:', error);
              completed = [];
            }
            const subsystems = ['database', 'cache', 'analytics', 'backups', 'logs'];
            
            return (
              <div key={item.id}>
                <p style={{ color: '#666', marginBottom: '12px', fontWeight: 600 }}>
                  Deletion ID: {item.id} | User: {item.user_id}
                </p>
                {subsystems.map(subsystem => (
                  <div key={subsystem} className="progress-item">
                    <span className="subsystem">{subsystem.toUpperCase()}</span>
                    <span className={`status ${completed.includes(subsystem) ? 'completed' : 'pending'}`}>
                      {completed.includes(subsystem) ? '✓ Completed' : 'Pending'}
                    </span>
                  </div>
                ))}
              </div>
            );
          })
        )}
      </div>

      <div style={{ marginTop: '30px' }} className="card">
        <h2>Audit Log (Compliance Trail)</h2>
        <div className="audit-log">
          {auditLogs.slice(0, 20).map(log => (
            <div key={log.id} className="audit-entry">
              <div className="action">{log.action}</div>
              <div className="details">
                {log.user_id && `User: ${log.user_id.substring(0, 8)}...`}
                {' | '}
                IP: {log.ip_address}
              </div>
              <div className="timestamp">
                {new Date(log.timestamp).toLocaleString()}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
