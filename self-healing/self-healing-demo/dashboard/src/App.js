import React, { useState, useEffect } from 'react';
import './App.css';

const Dashboard = () => {
  const [healingState, setHealingState] = useState({
    services: {},
    healingHistory: []
  });
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:8080');
    
    ws.onopen = () => {
      setConnected(true);
      console.log('Connected to healing controller');
    };
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'state-update' || message.type === 'initial-state') {
        setHealingState(message.data);
      }
    };
    
    ws.onclose = () => {
      setConnected(false);
      console.log('Disconnected from healing controller');
    };
    
    return () => ws.close();
  }, []);

  const simulateFailure = async (serviceName, type) => {
    try {
      await fetch(`http://localhost:3004/simulate/${serviceName}/${type}`, {
        method: 'POST'
      });
    } catch (error) {
      console.error('Failed to simulate failure:', error);
    }
  };

  const triggerHealing = async (serviceName) => {
    try {
      await fetch(`http://localhost:3004/heal/${serviceName}`, {
        method: 'POST'
      });
    } catch (error) {
      console.error('Failed to trigger healing:', error);
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'healthy': return '#4CAF50';
      case 'unhealthy': return '#FF9800';
      case 'error': return '#F44336';
      default: return '#9E9E9E';
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'healthy': return '✅';
      case 'unhealthy': return '⚠️';
      case 'error': return '❌';
      default: return '❔';
    }
  };

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <h1>🏥 Self-Healing Systems Dashboard</h1>
        <div className={`connection-status ${connected ? 'connected' : 'disconnected'}`}>
          {connected ? '🟢 Connected' : '🔴 Disconnected'}
        </div>
      </header>

      <div className="services-grid">
        {Object.entries(healingState.services).map(([serviceName, service]) => (
          <div key={serviceName} className="service-card">
            <div className="service-header">
              <h3>{getStatusIcon(service.status)} {serviceName}</h3>
              <span 
                className="status-badge" 
                style={{ backgroundColor: getStatusColor(service.status) }}
              >
                {service.status}
              </span>
            </div>
            
            <div className="service-metrics">
              <div className="metric">
                <span>Memory: {service.metrics?.memoryUsage?.toFixed(1) || 0}%</span>
                <div className="metric-bar">
                  <div 
                    className="metric-fill" 
                    style={{ 
                      width: `${service.metrics?.memoryUsage || 0}%`,
                      backgroundColor: (service.metrics?.memoryUsage || 0) > 80 ? '#FF5722' : '#2196F3'
                    }}
                  ></div>
                </div>
              </div>
              
              <div className="metric">
                <span>CPU: {service.metrics?.cpuUsage?.toFixed(1) || 0}%</span>
                <div className="metric-bar">
                  <div 
                    className="metric-fill" 
                    style={{ 
                      width: `${service.metrics?.cpuUsage || 0}%`,
                      backgroundColor: (service.metrics?.cpuUsage || 0) > 80 ? '#FF5722' : '#4CAF50'
                    }}
                  ></div>
                </div>
              </div>
              
              <div className="metric">
                <span>Error Rate: {service.metrics?.errorRate?.toFixed(1) || 0}%</span>
                <div className="metric-bar">
                  <div 
                    className="metric-fill" 
                    style={{ 
                      width: `${service.metrics?.errorRate || 0}%`,
                      backgroundColor: (service.metrics?.errorRate || 0) > 20 ? '#FF5722' : '#4CAF50'
                    }}
                  ></div>
                </div>
              </div>
            </div>
            
            <div className="service-info">
              <p>Failures: {service.consecutiveFailures}</p>
              <p>Last Check: {service.lastCheck ? new Date(service.lastCheck).toLocaleTimeString() : 'Never'}</p>
              {service.healingInProgress && <p className="healing-indicator">🔄 Healing in progress...</p>}
            </div>
            
            <div className="service-actions">
              <button 
                onClick={() => simulateFailure(serviceName, 'memory-leak')}
                className="btn btn-warning"
              >
                💾 Memory Leak
              </button>
              <button 
                onClick={() => simulateFailure(serviceName, 'high-cpu')}
                className="btn btn-warning"
              >
                ⚡ High CPU
              </button>
              <button 
                onClick={() => simulateFailure(serviceName, 'errors')}
                className="btn btn-warning"
              >
                ⚠️ Errors
              </button>
              <button 
                onClick={() => triggerHealing(serviceName)}
                className="btn btn-primary"
                disabled={service.healingInProgress}
              >
                🔧 Heal
              </button>
            </div>
          </div>
        ))}
      </div>

      <div className="healing-history">
        <h2>🕐 Healing History</h2>
        <div className="history-list">
          {healingState.healingHistory.slice(-10).reverse().map((event, index) => (
            <div key={index} className={`history-item ${event.result}`}>
              <span className="timestamp">{new Date(event.timestamp).toLocaleTimeString()}</span>
              <span className="service">{event.service}</span>
              <span className="action">{event.action}</span>
              <span className="result">{event.result}</span>
              {event.error && <span className="error">{event.error}</span>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
