import React, { useState, useEffect } from 'react';
import axios from 'axios';
import io from 'socket.io-client';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';
import './App.css';

function App() {
  const [services, setServices] = useState({});
  const [healthHistory, setHealthHistory] = useState([]);
  const [logs, setLogs] = useState([]);
  const [selectedService, setSelectedService] = useState('');

  useEffect(() => {
    // Connect to WebSocket for real-time updates
    const socket = io('http://localhost:4000');
    
    socket.on('health-update', (data) => {
      setServices(prev => ({ ...prev, [data.service]: data }));
      setHealthHistory(prev => [...prev.slice(-19), {
        time: new Date().toLocaleTimeString(),
        ...data
      }]);
    });

    socket.on('log-update', (log) => {
      setLogs(prev => [log, ...prev.slice(0, 99)]);
    });

    // Initial health check
    fetchHealthStatus();
    
    const interval = setInterval(fetchHealthStatus, 5000);
    return () => {
      clearInterval(interval);
      socket.disconnect();
    };
  }, []);

  const fetchHealthStatus = async () => {
    try {
      const response = await axios.get('http://localhost:4000/health/all');
      setServices(response.data);
    } catch (error) {
      console.error('Failed to fetch health status:', error);
    }
  };

  const injectFailure = async (service, type) => {
    try {
      await axios.post(`http://localhost:4000/inject-failure`, { service, type });
      addLog(`Injected ${type} failure into ${service}`, 'warning');
    } catch (error) {
      console.error('Failed to inject failure:', error);
    }
  };

  const addLog = (message, type = 'info') => {
    const log = {
      timestamp: new Date().toLocaleTimeString(),
      message,
      type,
      id: Date.now()
    };
    setLogs(prev => [log, ...prev.slice(0, 99)]);
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'healthy': return '#4CAF50';
      case 'degraded': return '#FF9800';
      case 'unhealthy': return '#F44336';
      default: return '#757575';
    }
  };

  return (
    <div className="app">
      <header className="header">
        <h1>🏥 Health Check Dashboard</h1>
        <p>Real-time distributed system health monitoring</p>
      </header>

      <div className="main-content">
        {/* Service Status Grid */}
        <div className="status-grid">
          {Object.entries(services).map(([name, service]) => (
            <div key={name} className="service-card" onClick={() => setSelectedService(name)}>
              <div className="service-header">
                <h3>{name}</h3>
                <div 
                  className="status-indicator" 
                  style={{ backgroundColor: getStatusColor(service.status) }}
                />
              </div>
              <div className="service-details">
                <div className="health-checks">
                  <div className="check-item">
                    <span>Shallow:</span>
                    <span className={`check-status ${service.shallow_check ? 'pass' : 'fail'}`}>
                      {service.shallow_check ? '✓' : '✗'}
                    </span>
                  </div>
                  <div className="check-item">
                    <span>Deep:</span>
                    <span className={`check-status ${service.deep_check ? 'pass' : 'fail'}`}>
                      {service.deep_check ? '✓' : '✗'}
                    </span>
                  </div>
                </div>
                <div className="metrics">
                  <div>Response: {service.response_time}ms</div>
                  <div>CPU: {service.cpu_usage}%</div>
                  <div>Memory: {service.memory_usage}%</div>
                </div>
                <div className="actions">
                  <button onClick={(e) => {e.stopPropagation(); injectFailure(name, 'database')}}>
                    💾 DB Fail
                  </button>
                  <button onClick={(e) => {e.stopPropagation(); injectFailure(name, 'latency')}}>
                    ⏱️ Latency
                  </button>
                  <button onClick={(e) => {e.stopPropagation(); injectFailure(name, 'memory')}}>
                    🧠 Memory
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Charts Section */}
        <div className="charts-section">
          <div className="chart-container">
            <h3>Health Status Timeline</h3>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={healthHistory}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Line type="monotone" dataKey="response_time" stroke="#2196F3" name="Response Time (ms)" />
              </LineChart>
            </ResponsiveContainer>
          </div>

          <div className="chart-container">
            <h3>Resource Usage</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={Object.entries(services).map(([name, service]) => ({
                name,
                cpu: service.cpu_usage,
                memory: service.memory_usage
              }))}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="name" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="cpu" fill="#2196F3" name="CPU %" />
                <Bar dataKey="memory" fill="#FF9800" name="Memory %" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Logs Section */}
        <div className="logs-section">
          <h3>Health Check Logs</h3>
          <div className="logs-container">
            {logs.map((log) => (
              <div key={log.id} className={`log-entry ${log.type}`}>
                <span className="timestamp">{log.timestamp}</span>
                <span className="message">{log.message}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
