import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

function App() {
  const [currentMetrics, setCurrentMetrics] = useState(null);
  const [history, setHistory] = useState([]);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    let ws = null;
    let historyInterval = null;
    let metricsInterval = null;
    let reconnectTimeout = null;
    
    // Function to fetch current metrics
    const fetchCurrentMetrics = () => {
      fetch('http://localhost:3002/metrics/current')
        .then(res => res.json())
        .then(data => {
          if (data && data.metrics) {
            // Force state update by creating new object
            setCurrentMetrics({ ...data.metrics });
            console.log('Metrics updated:', data.metrics.totalEvents);
          }
        })
        .catch(err => {
          console.error('Error fetching current metrics:', err);
        });
    };
    
    // Function to fetch historical data
    const fetchHistory = () => {
      fetch('http://localhost:3002/metrics/history')
        .then(res => res.json())
        .then(data => {
          // Always set history if windows array exists (even if empty or all zeros)
          if (data && data.windows) {
            // Force state update by creating new array
            setHistory([...data.windows]);
            console.log('History updated:', data.windows.length, 'windows');
          }
        })
        .catch(err => {
          console.error('Error fetching history:', err);
        });
    };

    // Function to setup WebSocket connection
    const setupWebSocket = () => {
      try {
        if (ws && ws.readyState === WebSocket.OPEN) {
          return; // Already connected
        }
        
        ws = new WebSocket('ws://localhost:3002');
        
        ws.onopen = () => {
          console.log('WebSocket connected');
          setConnected(true);
        };
        
        ws.onclose = (event) => {
          console.log('WebSocket disconnected, reconnecting...', event.code);
          setConnected(false);
          ws = null;
          // Reconnect after 2 seconds
          if (!reconnectTimeout) {
            reconnectTimeout = setTimeout(() => {
              reconnectTimeout = null;
              setupWebSocket();
            }, 2000);
          }
        };
        
        ws.onerror = (error) => {
          console.error('WebSocket error:', error);
          setConnected(false);
        };
        
        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (data && data.metrics) {
              setCurrentMetrics(data.metrics);
            }
          } catch (err) {
            console.error('Error parsing WebSocket message:', err);
          }
        };
      } catch (error) {
        console.error('Error setting up WebSocket:', error);
        setConnected(false);
      }
    };

    // Fetch data immediately
    fetchCurrentMetrics();
    fetchHistory();

    // Poll current metrics every 1 second - ALWAYS ACTIVE
    metricsInterval = setInterval(() => {
      console.log('Polling metrics at', new Date().toLocaleTimeString());
      fetchCurrentMetrics();
    }, 1000);

    // Refresh history every 2 seconds - ALWAYS ACTIVE
    historyInterval = setInterval(() => {
      console.log('Polling history at', new Date().toLocaleTimeString());
      fetchHistory();
    }, 2000);

    // Setup WebSocket connection
    setupWebSocket();

    return () => {
      if (historyInterval) clearInterval(historyInterval);
      if (metricsInterval) clearInterval(metricsInterval);
      if (reconnectTimeout) clearTimeout(reconnectTimeout);
      if (ws) {
        ws.close();
        ws = null;
      }
    };
  }, []);

  return (
    <div style={{
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      minHeight: '100vh',
      padding: '20px'
    }}>
      <div style={{ maxWidth: '1400px', margin: '0 auto' }}>
        <header style={{ 
          background: 'white', 
          padding: '30px', 
          borderRadius: '16px',
          boxShadow: '0 8px 32px rgba(0,0,0,0.1)',
          marginBottom: '20px'
        }}>
          <h1 style={{ margin: 0, color: '#1e293b', fontSize: '32px' }}>
            Real-Time Analytics Dashboard
          </h1>
          <p style={{ margin: '10px 0 0 0', color: '#64748b' }}>
            Stream Processing Pipeline • {connected ? '🟢 Connected' : '🔴 Disconnected'}
          </p>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '20px', marginBottom: '20px' }}>
          <MetricCard 
            title="Total Events" 
            value={currentMetrics?.totalEvents || 0}
            subtitle="Last 60 seconds"
            color="#3b82f6"
          />
          <MetricCard 
            title="Unique Users" 
            value={currentMetrics?.uniqueUsers || 0}
            subtitle="HyperLogLog estimation"
            color="#8b5cf6"
          />
          <MetricCard 
            title="Active Sessions" 
            value={currentMetrics?.activeSessions || 0}
            subtitle="Current window"
            color="#ec4899"
          />
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
          <ChartCard title="Event Volume Over Time">
            {history && history.length > 0 ? (
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={history}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis 
                    dataKey="timestamp" 
                    tickFormatter={(t) => {
                      try {
                        return new Date(t).toLocaleTimeString();
                      } catch {
                        return t;
                      }
                    }}
                    stroke="#64748b"
                  />
                  <YAxis stroke="#64748b" />
                  <Tooltip 
                    labelFormatter={(t) => {
                      try {
                        return new Date(t).toLocaleTimeString();
                      } catch {
                        return t;
                      }
                    }}
                    contentStyle={{ background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px' }}
                  />
                  <Line type="monotone" dataKey="totalEvents" stroke="#3b82f6" strokeWidth={3} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div style={{ 
                height: 300, 
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center', 
                color: '#64748b',
                fontSize: '14px'
              }}>
                No historical data available. Generate some events to see the chart.
              </div>
            )}
          </ChartCard>

          <ChartCard title="Top Pages (Current Window)">
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={currentMetrics?.topPages || []}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="page" stroke="#64748b" />
                <YAxis stroke="#64748b" />
                <Tooltip contentStyle={{ background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px' }} />
                <Bar dataKey="views" fill="#8b5cf6" radius={[8, 8, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
        </div>
      </div>
    </div>
  );
}

function MetricCard({ title, value, subtitle, color }) {
  return (
    <div style={{
      background: 'white',
      padding: '24px',
      borderRadius: '16px',
      boxShadow: '0 4px 16px rgba(0,0,0,0.08)'
    }}>
      <div style={{ fontSize: '14px', color: '#64748b', marginBottom: '8px' }}>{title}</div>
      <div style={{ fontSize: '36px', fontWeight: 'bold', color, marginBottom: '4px' }}>
        {value.toLocaleString()}
      </div>
      <div style={{ fontSize: '12px', color: '#94a3b8' }}>{subtitle}</div>
    </div>
  );
}

function ChartCard({ title, children }) {
  return (
    <div style={{
      background: 'white',
      padding: '24px',
      borderRadius: '16px',
      boxShadow: '0 4px 16px rgba(0,0,0,0.08)'
    }}>
      <h3 style={{ margin: '0 0 20px 0', color: '#1e293b', fontSize: '18px' }}>{title}</h3>
      {children}
    </div>
  );
}

export default App;
