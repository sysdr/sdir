import React, { useState, useEffect } from 'react';
import styled from 'styled-components';
import axios from 'axios';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, BarChart, Bar } from 'recharts';

const Container = styled.div`
  padding: 20px;
  max-width: 1400px;
  margin: 0 auto;
  color: white;
`;

const Header = styled.div`
  text-align: center;
  margin-bottom: 30px;
`;

const Title = styled.h1`
  font-size: 2.5rem;
  margin: 0;
  text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
`;

const Subtitle = styled.p`
  font-size: 1.2rem;
  opacity: 0.9;
  margin: 10px 0;
`;

const Grid = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 20px;
  margin-bottom: 20px;
`;

const Card = styled.div`
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  padding: 20px;
  box-shadow: 0 8px 32px rgba(0,0,0,0.1);
  color: #333;
`;

const CardTitle = styled.h3`
  margin: 0 0 15px 0;
  color: #2c3e50;
  border-bottom: 2px solid #3498db;
  padding-bottom: 8px;
`;

const ControlPanel = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 15px;
`;

const ControlGroup = styled.div`
  display: flex;
  flex-direction: column;
`;

const Label = styled.label`
  font-weight: bold;
  margin-bottom: 5px;
  color: #2c3e50;
`;

const Input = styled.input`
  padding: 8px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
`;

const Select = styled.select`
  padding: 8px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
`;

const Button = styled.button`
  padding: 10px 20px;
  background: ${props => props.danger ? '#e74c3c' : '#3498db'};
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
  font-weight: bold;
  transition: background 0.3s;
  
  &:hover {
    background: ${props => props.danger ? '#c0392b' : '#2980b9'};
  }
  
  &:disabled {
    background: #95a5a6;
    cursor: not-allowed;
  }
`;

const StatusBadge = styled.span`
  padding: 4px 12px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: bold;
  background: ${props => {
    switch(props.status) {
      case 'CLOSED': return '#27ae60';
      case 'OPEN': return '#e74c3c';
      case 'HALF_OPEN': return '#f39c12';
      default: return '#95a5a6';
    }
  }};
  color: white;
`;

const MetricCard = styled.div`
  text-align: center;
  padding: 15px;
  margin: 10px 0;
  background: linear-gradient(135deg, #3498db, #2c3e50);
  border-radius: 8px;
  color: white;
`;

const MetricValue = styled.div`
  font-size: 2rem;
  font-weight: bold;
`;

const MetricLabel = styled.div`
  font-size: 0.9rem;
  opacity: 0.9;
`;

function App() {
  const [metrics, setMetrics] = useState([]);
  const [gatewayStatus, setGatewayStatus] = useState({});
  const [backendConfig, setBackendConfig] = useState({ failure_rate: 0, latency_ms: 100 });
  const [gatewayConfig, setGatewayConfig] = useState({
    retry: {
      enabled: true,
      max_attempts: 3,
      base_delay_ms: 100,
      exponential_backoff: true,
      jitter: true
    },
    circuit_breaker: {
      enabled: true,
      failure_threshold: 5,
      recovery_timeout_ms: 30000
    }
  });
  const [loadConfig, setLoadConfig] = useState({ rps: 10, duration_seconds: 60, concurrent_clients: 5 });
  const [loadStats, setLoadStats] = useState({});
  const [isLoadRunning, setIsLoadRunning] = useState(false);

  useEffect(() => {
    const interval = setInterval(fetchMetrics, 1000);
    return () => clearInterval(interval);
  }, []);

  const fetchMetrics = async () => {
    try {
      // Fetch gateway status
      const statusRes = await axios.get('http://localhost:8000/status');
      setGatewayStatus(statusRes.data);

      // Fetch load generator stats
      const loadRes = await axios.get('http://localhost:8002/stats');
      setLoadStats(loadRes.data.stats);
      setIsLoadRunning(loadRes.data.is_running);

      // Add current metrics to chart data
      const now = new Date().toLocaleTimeString();
      setMetrics(prev => {
        const newMetrics = [...prev, {
          time: now,
          success_rate: loadRes.data.stats.requests_sent > 0 ? 
            (loadRes.data.stats.requests_successful / loadRes.data.stats.requests_sent * 100) : 100,
          avg_latency: loadRes.data.stats.average_latency_ms || 0,
          requests_per_second: loadRes.data.stats.requests_sent || 0,
          circuit_breaker_state: statusRes.data.circuit_breaker_state === 'CLOSED' ? 0 : 
                                statusRes.data.circuit_breaker_state === 'HALF_OPEN' ? 1 : 2
        }].slice(-30); // Keep last 30 points
        return newMetrics;
      });
    } catch (error) {
      console.error('Error fetching metrics:', error);
    }
  };

  const updateBackendConfig = async () => {
    try {
      await axios.post('http://localhost:8001/config', backendConfig);
    } catch (error) {
      console.error('Error updating backend config:', error);
    }
  };

  const updateGatewayConfig = async () => {
    try {
      await axios.post('http://localhost:8000/config', gatewayConfig);
    } catch (error) {
      console.error('Error updating gateway config:', error);
    }
  };

  const startLoadTest = async () => {
    try {
      await axios.post('http://localhost:8002/start', loadConfig);
    } catch (error) {
      console.error('Error starting load test:', error);
    }
  };

  const stopLoadTest = async () => {
    try {
      await axios.post('http://localhost:8002/stop');
    } catch (error) {
      console.error('Error stopping load test:', error);
    }
  };

  return (
    <Container>
      <Header>
        <Title>🔄 Retry Storms Demo</Title>
        <Subtitle>Prevention and Mitigation in Action</Subtitle>
      </Header>

      <Grid>
        <Card>
          <CardTitle>📊 Real-time Metrics</CardTitle>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={metrics}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="success_rate" stroke="#27ae60" name="Success Rate %" />
              <Line type="monotone" dataKey="avg_latency" stroke="#e74c3c" name="Avg Latency (ms)" />
            </LineChart>
          </ResponsiveContainer>
        </Card>

        <Card>
          <CardTitle>⚡ System Status</CardTitle>
          <div>
            <MetricCard>
              <MetricValue>{loadStats.requests_successful || 0}</MetricValue>
              <MetricLabel>Successful Requests</MetricLabel>
            </MetricCard>
            <MetricCard>
              <MetricValue>{loadStats.requests_failed || 0}</MetricValue>
              <MetricLabel>Failed Requests</MetricLabel>
            </MetricCard>
            <div style={{marginTop: '15px', textAlign: 'center'}}>
              <Label>Circuit Breaker: </Label>
              <StatusBadge status={gatewayStatus.circuit_breaker_state}>
                {gatewayStatus.circuit_breaker_state || 'UNKNOWN'}
              </StatusBadge>
            </div>
          </div>
        </Card>

        <Card>
          <CardTitle>🎛️ Backend Configuration</CardTitle>
          <ControlPanel>
            <ControlGroup>
              <Label>Failure Rate</Label>
              <Input
                type="number"
                min="0"
                max="1"
                step="0.1"
                value={backendConfig.failure_rate}
                onChange={(e) => setBackendConfig({...backendConfig, failure_rate: parseFloat(e.target.value)})}
              />
            </ControlGroup>
            <ControlGroup>
              <Label>Latency (ms)</Label>
              <Input
                type="number"
                min="0"
                value={backendConfig.latency_ms}
                onChange={(e) => setBackendConfig({...backendConfig, latency_ms: parseInt(e.target.value)})}
              />
            </ControlGroup>
            <ControlGroup>
              <Button onClick={updateBackendConfig}>Apply Config</Button>
            </ControlGroup>
          </ControlPanel>
        </Card>

        <Card>
          <CardTitle>🛡️ Gateway Protection</CardTitle>
          <ControlPanel>
            <ControlGroup>
              <Label>Max Retry Attempts</Label>
              <Input
                type="number"
                min="1"
                max="10"
                value={gatewayConfig.retry.max_attempts}
                onChange={(e) => setGatewayConfig({
                  ...gatewayConfig,
                  retry: {...gatewayConfig.retry, max_attempts: parseInt(e.target.value)}
                })}
              />
            </ControlGroup>
            <ControlGroup>
              <Label>Circuit Breaker Threshold</Label>
              <Input
                type="number"
                min="1"
                max="20"
                value={gatewayConfig.circuit_breaker.failure_threshold}
                onChange={(e) => setGatewayConfig({
                  ...gatewayConfig,
                  circuit_breaker: {...gatewayConfig.circuit_breaker, failure_threshold: parseInt(e.target.value)}
                })}
              />
            </ControlGroup>
            <ControlGroup>
              <Button onClick={updateGatewayConfig}>Apply Config</Button>
            </ControlGroup>
          </ControlPanel>
        </Card>

        <Card>
          <CardTitle>🚀 Load Generator</CardTitle>
          <ControlPanel>
            <ControlGroup>
              <Label>Requests per Second</Label>
              <Input
                type="number"
                min="1"
                max="100"
                value={loadConfig.rps}
                onChange={(e) => setLoadConfig({...loadConfig, rps: parseInt(e.target.value)})}
              />
            </ControlGroup>
            <ControlGroup>
              <Label>Concurrent Clients</Label>
              <Input
                type="number"
                min="1"
                max="20"
                value={loadConfig.concurrent_clients}
                onChange={(e) => setLoadConfig({...loadConfig, concurrent_clients: parseInt(e.target.value)})}
              />
            </ControlGroup>
            <ControlGroup>
              {!isLoadRunning ? (
                <Button onClick={startLoadTest}>Start Load Test</Button>
              ) : (
                <Button danger onClick={stopLoadTest}>Stop Load Test</Button>
              )}
            </ControlGroup>
          </ControlPanel>
        </Card>
      </Grid>
    </Container>
  );
}

export default App;
