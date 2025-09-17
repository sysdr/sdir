import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';
import io from 'socket.io-client';
import './App.css';

function App() {
  const [metrics, setMetrics] = useState({
    currentRPS: 0,
    activeConnections: 0,
    circuitBreakerState: 'CLOSED',
    avgResponseTime: 0,
    errorRate: 0,
    scalingEvents: []
  });
  
  const [trafficData, setTrafficData] = useState([]);
  const [isLoadTestActive, setIsLoadTestActive] = useState(false);

  useEffect(() => {
    const socket = io('http://localhost:3001');
    
    socket.on('metrics', (data) => {
      setMetrics(data);
      setTrafficData(prev => [...prev.slice(-29), {
        time: new Date().toLocaleTimeString(),
        rps: data.currentRPS,
        responseTime: data.avgResponseTime
      }]);
    });

    return () => socket.disconnect();
  }, []);

  const startLoadTest = async () => {
    setIsLoadTestActive(true);
    try {
      await fetch('/api/load-test/start', { method: 'POST' });
    } catch (err) {
      console.error('Failed to start load test:', err);
    }
  };

  const stopLoadTest = async () => {
    setIsLoadTestActive(false);
    try {
      await fetch('/api/load-test/stop', { method: 'POST' });
    } catch (err) {
      console.error('Failed to stop load test:', err);
    }
  };

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <h1>🛍️ Black Friday Load Monitor</h1>
        <div className="status-indicators">
          <div className={`status-card ${metrics.circuitBreakerState.toLowerCase()}`}>
            <h3>Circuit Breaker</h3>
            <div className="status-value">{metrics.circuitBreakerState}</div>
          </div>
          <div className="status-card">
            <h3>Current RPS</h3>
            <div className="status-value">{metrics.currentRPS.toLocaleString()}</div>
          </div>
          <div className="status-card">
            <h3>Response Time</h3>
            <div className="status-value">{metrics.avgResponseTime}ms</div>
          </div>
        </div>
      </header>

      <div className="controls">
        <button 
          onClick={startLoadTest} 
          disabled={isLoadTestActive}
          className="load-test-btn start"
        >
          🚀 Start Black Friday Load Test
        </button>
        <button 
          onClick={stopLoadTest} 
          disabled={!isLoadTestActive}
          className="load-test-btn stop"
        >
          ⏹️ Stop Load Test
        </button>
      </div>

      <div className="charts-container">
        <div className="chart-section">
          <h2>Real-Time Traffic Pattern</h2>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={trafficData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Line type="monotone" dataKey="rps" stroke="#2196F3" strokeWidth={2} name="Requests/sec" />
              <Line type="monotone" dataKey="responseTime" stroke="#FF5722" strokeWidth={2} name="Response Time (ms)" />
            </LineChart>
          </ResponsiveContainer>
        </div>

        <div className="metrics-grid">
          <div className="metric-card">
            <h3>Active Connections</h3>
            <div className="metric-value">{metrics.activeConnections}</div>
          </div>
          <div className="metric-card">
            <h3>Error Rate</h3>
            <div className="metric-value">{metrics.errorRate.toFixed(2)}%</div>
          </div>
          <div className="metric-card">
            <h3>Auto-Scaling Events</h3>
            <div className="metric-value">{metrics.scalingEvents.length}</div>
          </div>
        </div>
      </div>

      <div className="scaling-events">
        <h2>Recent Scaling Events</h2>
        <div className="events-list">
          {metrics.scalingEvents.slice(-10).map((event, idx) => (
            <div key={idx} className={`event ${event.type}`}>
              <span className="event-time">{event.timestamp}</span>
              <span className="event-description">{event.description}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
