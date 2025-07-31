import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';
import axios from 'axios';
import './App.css';

const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:3002';
const GATEWAY_URL = process.env.REACT_APP_GATEWAY_URL || 'ws://localhost:3001';

function App() {
  const [metrics, setMetrics] = useState({
    activeConnections: 0,
    totalConnections: 0,
    messagesDelivered: 0,
    messagesFailed: 0,
    averageLatency: 0,
    connectionsByRegion: {}
  });
  
  const [connections, setConnections] = useState([]);
  const [latencyData, setLatencyData] = useState([]);
  const [connectionData, setConnectionData] = useState([]);
  const [isSimulating, setIsSimulating] = useState(false);
  const [simulatedClients, setSimulatedClients] = useState([]);

  // Fetch metrics
  const fetchMetrics = async () => {
    try {
      const response = await axios.get(`${GATEWAY_URL.replace('ws://', 'http://')}/metrics`);
      setMetrics(response.data);
      
      // Update charts
      const now = new Date().toLocaleTimeString();
      setLatencyData(prev => [...prev.slice(-19), {
        time: now,
        latency: response.data.averageLatency || 0
      }]);
      
      setConnectionData(prev => [...prev.slice(-19), {
        time: now,
        connections: response.data.activeConnections || 0
      }]);
      
    } catch (error) {
      console.error('Error fetching metrics:', error);
    }
  };

  // Simulate clients
  const simulateClients = async (count = 1000) => {
    setIsSimulating(true);
    const clients = [];
    
    // Create connections in smaller batches with proper delays
    const batchSize = 50;
    const delayBetweenBatches = 500; // 500ms between batches
    
    for (let i = 0; i < count; i++) {
      try {
        const ws = new WebSocket(GATEWAY_URL);
        clients.push(ws);
        
        ws.onopen = () => {
          console.log(`Client ${i} connected`);
        };
        
        ws.onmessage = (event) => {
          const data = JSON.parse(event.data);
          if (data.type === 'notification') {
            console.log(`Client ${i} received notification:`, data.message);
          }
        };
        
        ws.onerror = (error) => {
          console.error(`Client ${i} connection error:`, error);
        };
        
        // Add delay between batches to prevent overwhelming the server
        if ((i + 1) % batchSize === 0) {
          console.log(`Created ${i + 1} connections, pausing...`);
          await new Promise(resolve => setTimeout(resolve, delayBetweenBatches));
        }
      } catch (error) {
        console.error(`Error creating client ${i}:`, error);
      }
    }
    
    setSimulatedClients(clients);
    setIsSimulating(false);
    console.log(`✅ Created ${clients.length} simulated clients`);
  };

  // Disconnect simulated clients
  const disconnectClients = () => {
    simulatedClients.forEach(ws => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    });
    setSimulatedClients([]);
  };

  // Send notification
  const sendNotification = async (type, fanoutType = 'broadcast') => {
    try {
      await axios.post(`${API_URL}/send`, {
        type,
        fanoutType
      });
      console.log(`Sent ${type} notification`);
    } catch (error) {
      console.error('Error sending notification:', error);
    }
  };

  // Send bulk notifications
  const sendBulkNotifications = async () => {
    const notifications = [
      { type: 'welcome', fanoutType: 'broadcast' },
      { type: 'promotion', fanoutType: 'broadcast' },
      { type: 'news', fanoutType: 'broadcast' }
    ];
    
    try {
      await axios.post(`${API_URL}/send-bulk`, { notifications });
      console.log('Sent bulk notifications');
    } catch (error) {
      console.error('Error sending bulk notifications:', error);
    }
  };

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 2000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="App">
      <header className="header">
        <h1>🚀 Push Notification System</h1>
        <p>Real-time monitoring and testing dashboard</p>
      </header>

      <main className="main">
        {/* Metrics Cards */}
        <div className="metrics-grid">
          <div className="metric-card">
            <h3>Active Connections</h3>
            <div className="metric-value">{metrics.activeConnections.toLocaleString()}</div>
          </div>
          <div className="metric-card">
            <h3>Messages Delivered</h3>
            <div className="metric-value">{metrics.messagesDelivered.toLocaleString()}</div>
          </div>
          <div className="metric-card">
            <h3>Average Latency</h3>
            <div className="metric-value">{metrics.averageLatency}ms</div>
          </div>
          <div className="metric-card">
            <h3>Success Rate</h3>
            <div className="metric-value">
              {metrics.messagesDelivered + metrics.messagesFailed > 0 
                ? ((metrics.messagesDelivered / (metrics.messagesDelivered + metrics.messagesFailed)) * 100).toFixed(1)
                : 100}%
            </div>
          </div>
        </div>

        {/* Control Panel */}
        <div className="control-panel">
          <h2>Test Controls</h2>
          <div className="button-group">
            <button 
              onClick={() => simulateClients(1000)} 
              disabled={isSimulating}
              className="btn btn-primary"
            >
              {isSimulating ? 'Connecting...' : 'Connect 1K Devices'}
            </button>
            <button 
              onClick={disconnectClients}
              className="btn btn-secondary"
            >
              Disconnect All
            </button>
          </div>
          
          <div className="button-group">
            <button onClick={() => sendNotification('welcome')} className="btn">
              Send Welcome
            </button>
            <button onClick={() => sendNotification('promotion')} className="btn">
              Send Promotion
            </button>
            <button onClick={() => sendNotification('news')} className="btn">
              Send News
            </button>
            <button onClick={sendBulkNotifications} className="btn btn-accent">
              Send Bulk
            </button>
          </div>
        </div>

        {/* Charts */}
        <div className="charts-container">
          <div className="chart-section">
            <h3>Connection Count</h3>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={connectionData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Line type="monotone" dataKey="connections" stroke="#2563eb" strokeWidth={2} />
              </LineChart>
            </ResponsiveContainer>
          </div>

          <div className="chart-section">
            <h3>Delivery Latency</h3>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={latencyData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Line type="monotone" dataKey="latency" stroke="#dc2626" strokeWidth={2} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Regional Distribution */}
        {Object.keys(metrics.connectionsByRegion).length > 0 && (
          <div className="chart-section">
            <h3>Connections by Region</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={Object.entries(metrics.connectionsByRegion).map(([region, count]) => ({ region, count }))}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="region" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="count" fill="#2563eb" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </main>
    </div>
  );
}

export default App;
