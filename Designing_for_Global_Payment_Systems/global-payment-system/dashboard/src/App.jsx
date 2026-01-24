import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import './App.css';

const COLORS = ['#3B82F6', '#60A5FA', '#93C5FD', '#DBEAFE', '#EF4444'];

export default function App() {
  const [payments, setPayments] = useState([]);
  const [stats, setStats] = useState({ byState: [], byRegion: [] });
  const [metrics, setMetrics] = useState({ totalPayments: 0, successfulPayments: 0, authorizationRate: 0 });
  const [realtimeData, setRealtimeData] = useState([]);

  useEffect(() => {
    fetchPayments();
    fetchStats();
    fetchMetrics();
    
    const interval = setInterval(() => {
      fetchStats();
      fetchMetrics();
    }, 3000);

    // WebSocket for real-time updates
    let ws;
    try {
      ws = new WebSocket('ws://localhost:3001');
      
      ws.onopen = () => {
        console.log('WebSocket connected');
      };
      
      ws.onerror = (error) => {
        console.warn('WebSocket error:', error);
        // WebSocket connection failed, but continue without real-time updates
      };
      
      ws.onmessage = (event) => {
        try {
          const payment = JSON.parse(event.data);
          setPayments(prev => [payment, ...prev.slice(0, 49)]);
          
          // Update realtime chart
          setRealtimeData(prev => {
            const newData = [...prev, {
              time: new Date().toLocaleTimeString(),
              amount: parseFloat(payment.amount || payment.converted_amount || 0),
              convertedAmount: parseFloat(payment.convertedAmount || payment.converted_amount || 0)
            }].slice(-20);
            return newData;
          });
        } catch (err) {
          console.warn('Error parsing WebSocket message:', err);
        }
      };
      
      ws.onclose = () => {
        console.log('WebSocket disconnected');
      };
    } catch (error) {
      console.warn('Failed to create WebSocket connection:', error);
      // Continue without WebSocket - polling will still work
    }

    return () => {
      clearInterval(interval);
      if (ws) {
        ws.close();
      }
    };
  }, []);

  const fetchPayments = async () => {
    try {
      const res = await fetch('http://localhost:3001/api/payments?limit=50');
      if (!res.ok) {
        console.warn('Failed to fetch payments:', res.status, res.statusText);
        return;
      }
      const data = await res.json();
      setPayments(data);
      
      // Populate realtime chart with recent payments if empty
      setRealtimeData(prev => {
        if (prev.length === 0 && data.length > 0) {
          const chartData = data.slice(0, 20).reverse().map(payment => ({
            time: new Date(payment.created_at).toLocaleTimeString(),
            amount: parseFloat(payment.amount || 0),
            convertedAmount: parseFloat(payment.converted_amount || 0)
          }));
          return chartData;
        }
        return prev;
      });
    } catch (error) {
      console.warn('Error fetching payments:', error);
    }
  };

  const fetchStats = async () => {
    try {
      const res = await fetch('http://localhost:3001/api/stats');
      if (!res.ok) {
        console.warn('Failed to fetch stats:', res.status, res.statusText);
        return;
      }
      const data = await res.json();
      // Transform data to ensure count is a number
      const transformedData = {
        byState: (data.byState || []).map(item => ({
          ...item,
          count: parseInt(item.count) || 0
        })),
        byRegion: data.byRegion || []
      };
      setStats(transformedData);
    } catch (error) {
      console.warn('Error fetching stats:', error);
    }
  };

  const fetchMetrics = async () => {
    try {
      const res = await fetch('http://localhost:3000/api/metrics');
      if (!res.ok) {
        console.warn('Failed to fetch metrics:', res.status, res.statusText);
        return;
      }
      const data = await res.json();
      setMetrics(data);
    } catch (error) {
      console.warn('Error fetching metrics:', error);
    }
  };

  const getStateColor = (state) => {
    const colors = {
      'captured': '#10B981',
      'authorized': '#3B82F6',
      'validated': '#F59E0B',
      'rejected': '#EF4444',
      'pending': '#6B7280'
    };
    return colors[state] || '#6B7280';
  };

  return (
    <div className="app">
      <header className="header">
        <h1>🌍 Global Payment System</h1>
        <p>Real-time multi-region payment processing</p>
      </header>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-value">{metrics.totalPayments}</div>
          <div className="metric-label">Total Payments</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.successfulPayments}</div>
          <div className="metric-label">Successful</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.authorizationRate}%</div>
          <div className="metric-label">Authorization Rate</div>
        </div>
      </div>

      <div className="charts-grid">
        <div className="chart-card">
          <h3>Payment State Distribution</h3>
          {stats.byState && stats.byState.length > 0 ? (
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie
                  data={stats.byState}
                  dataKey="count"
                  nameKey="state"
                  cx="50%"
                  cy="50%"
                  outerRadius={80}
                  label={({ state, count }) => `${state}: ${count}`}
                >
                  {stats.byState.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={getStateColor(entry.state)} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <div style={{ height: 250, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#6B7280' }}>
              No payment data available yet
            </div>
          )}
        </div>

        <div className="chart-card">
          <h3>Real-time Payment Flow</h3>
          {realtimeData && realtimeData.length > 0 ? (
            <ResponsiveContainer width="100%" height={250}>
              <LineChart data={realtimeData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" />
                <XAxis dataKey="time" stroke="#6B7280" />
                <YAxis stroke="#6B7280" />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="amount" stroke="#3B82F6" name="Source Amount" strokeWidth={2} />
                <Line type="monotone" dataKey="convertedAmount" stroke="#10B981" name="Converted Amount" strokeWidth={2} />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <div style={{ height: 250, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#6B7280' }}>
              Waiting for payment data... Generate payments to see real-time flow
            </div>
          )}
        </div>
      </div>

      <div className="payments-card">
        <h3>Recent Payments</h3>
        <div className="payments-table">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Amount</th>
                <th>Currency</th>
                <th>Converted</th>
                <th>Region</th>
                <th>State</th>
                <th>Fraud Score</th>
              </tr>
            </thead>
            <tbody>
              {payments.slice(0, 15).map(payment => (
                <tr key={payment.id}>
                  <td>{new Date(payment.created_at).toLocaleTimeString()}</td>
                  <td>${parseFloat(payment.amount).toFixed(2)}</td>
                  <td>{payment.source_currency} → {payment.target_currency}</td>
                  <td>{parseFloat(payment.converted_amount).toFixed(2)}</td>
                  <td><span className="region-badge">{payment.region}</span></td>
                  <td>
                    <span className="state-badge" style={{ backgroundColor: getStateColor(payment.state) }}>
                      {payment.state}
                    </span>
                  </td>
                  <td className={parseFloat(payment.fraud_score) > 0.7 ? 'high-risk' : ''}>
                    {parseFloat(payment.fraud_score).toFixed(2)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
