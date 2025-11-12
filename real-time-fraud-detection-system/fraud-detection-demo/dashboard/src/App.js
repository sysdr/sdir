import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import './App.css';

function App() {
  const [transactions, setTransactions] = useState([]);
  const [stats, setStats] = useState({ total: 0, approved: 0, challenged: 0, blocked: 0 });
  const [riskDistribution, setRiskDistribution] = useState([]);
  const [recentDecisions, setRecentDecisions] = useState([]);

  useEffect(() => {
    fetchTransactions();
    fetchStats();
    
    // WebSocket for real-time updates
    let ws;
    try {
      ws = new WebSocket('ws://localhost:3001');
      
      ws.onopen = () => {
        console.log('WebSocket connected');
      };
      
      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'decision') {
            setRecentDecisions(prev => [msg.data, ...prev].slice(0, 10));
            fetchStats();
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };
      
      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
      };
      
      ws.onclose = () => {
        console.log('WebSocket disconnected');
      };
    } catch (error) {
      console.error('Failed to create WebSocket:', error);
    }

    const interval = setInterval(() => {
      fetchTransactions();
      fetchStats();
    }, 3000);

    return () => {
      clearInterval(interval);
      if (ws) {
        ws.close();
      }
    };
  }, []);

  const fetchTransactions = async () => {
    try {
      const res = await fetch('http://localhost:3001/api/transactions');
      const data = await res.json();
      setTransactions(data);
      
      // Calculate risk distribution
      const distribution = [
        { range: '0-39 (Approve)', count: data.filter(t => t.risk_score < 40).length, fill: '#10b981' },
        { range: '40-74 (Challenge)', count: data.filter(t => t.risk_score >= 40 && t.risk_score < 75).length, fill: '#f59e0b' },
        { range: '75-100 (Block)', count: data.filter(t => t.risk_score >= 75).length, fill: '#ef4444' }
      ];
      setRiskDistribution(distribution);
      
      // Populate recent decisions from transactions that have decisions (fallback if WebSocket not working)
      const decisionsWithScores = data
        .filter(t => t.risk_score !== null && t.decision)
        .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
        .slice(0, 10)
        .map(t => {
          let features = null;
          try {
            features = t.features ? JSON.parse(t.features) : null;
          } catch (e) {
            console.error('Error parsing features:', e);
          }
          return {
            transactionId: t.transaction_id,
            userId: t.user_id,
            amount: parseFloat(t.amount),
            riskScore: t.risk_score,
            decision: t.decision,
            mlScore: features?.mlScore || (features?.features?.mlScore) || 0,
            triggeredRules: features?.triggeredRules || []
          };
        });
      
      // Update decisions from API (this ensures we show decisions even if WebSocket missed them)
      // Only update if we have decisions and we don't have any yet, or periodically refresh
      if (decisionsWithScores.length > 0) {
        setRecentDecisions(prev => {
          // If we have WebSocket decisions, keep them and add new ones from API
          if (prev.length > 0) {
            const existingIds = new Set(prev.map(d => d.transactionId));
            const newFromApi = decisionsWithScores.filter(d => !existingIds.has(d.transactionId));
            return [...prev, ...newFromApi].slice(0, 10);
          }
          // Otherwise, use API decisions
          return decisionsWithScores;
        });
      }
    } catch (error) {
      console.error('Error fetching transactions:', error);
    }
  };

  const fetchStats = async () => {
    try {
      const res = await fetch('http://localhost:3001/api/stats');
      const data = await res.json();
      setStats(data);
    } catch (error) {
      console.error('Error fetching stats:', error);
    }
  };

  const submitTransaction = async (isFraud = false) => {
    const transaction = isFraud ? {
      userId: `user-${Math.floor(Math.random() * 100)}`,
      amount: Math.random() * 1000 + 500,
      merchant: "Suspicious Merchant",
      deviceId: `device-${Math.floor(Math.random() * 1000)}`,
      ipAddress: "192.168.1." + Math.floor(Math.random() * 255),
      latitude: 40.7128 + (Math.random() - 0.5) * 50,
      longitude: -74.0060 + (Math.random() - 0.5) * 50
    } : {
      userId: `user-${Math.floor(Math.random() * 50)}`,
      amount: Math.random() * 200 + 10,
      merchant: "Amazon",
      deviceId: `device-${Math.floor(Math.random() * 100)}`,
      ipAddress: "192.168.1." + Math.floor(Math.random() * 255),
      latitude: 40.7128 + (Math.random() - 0.5) * 2,
      longitude: -74.0060 + (Math.random() - 0.5) * 2
    };

    await fetch('http://localhost:3001/api/transactions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(transaction)
    });
  };

  const decisionData = [
    { name: 'Approved', value: stats.approved, fill: '#10b981' },
    { name: 'Challenged', value: stats.challenged, fill: '#f59e0b' },
    { name: 'Blocked', value: stats.blocked, fill: '#ef4444' }
  ];

  return (
    <div className="App">
      <header className="header">
        <h1>🛡️ Fraud Detection System</h1>
        <div className="stats-bar">
          <div className="stat">
            <span className="stat-value">{stats.total}</span>
            <span className="stat-label">Total (1h)</span>
          </div>
          <div className="stat approved">
            <span className="stat-value">{stats.approved}</span>
            <span className="stat-label">Approved</span>
          </div>
          <div className="stat challenged">
            <span className="stat-value">{stats.challenged}</span>
            <span className="stat-label">Challenged</span>
          </div>
          <div className="stat blocked">
            <span className="stat-value">{stats.blocked}</span>
            <span className="stat-label">Blocked</span>
          </div>
        </div>
      </header>

      <div className="controls">
        <button onClick={() => submitTransaction(false)} className="btn-submit">
          Submit Normal Transaction
        </button>
        <button onClick={() => submitTransaction(true)} className="btn-fraud">
          Submit Suspicious Transaction
        </button>
      </div>

      <div className="dashboard-grid">
        <div className="card">
          <h2>Decision Distribution</h2>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie data={decisionData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} label />
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <h2>Risk Score Distribution</h2>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={riskDistribution}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="range" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="count" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="card full-width">
          <h2>Real-Time Decisions</h2>
          <div className="decisions-stream">
            {recentDecisions.length > 0 ? (
              recentDecisions.map((decision, idx) => (
                <div key={idx} className={`decision-item ${decision.decision.toLowerCase()}`}>
                  <div className="decision-header">
                    <span className="txn-id">{decision.transactionId}</span>
                    <span className={`decision-badge ${decision.decision.toLowerCase()}`}>
                      {decision.decision}
                    </span>
                    <span className="risk-score">Score: {decision.riskScore}</span>
                  </div>
                  <div className="decision-details">
                    <span>User: {decision.userId}</span>
                    <span>Amount: ${decision.amount?.toFixed(2) || decision.amount}</span>
                    <span>ML Score: {decision.mlScore || 'N/A'}</span>
                  </div>
                  {decision.triggeredRules && decision.triggeredRules.length > 0 && (
                    <div className="triggered-rules">
                      {decision.triggeredRules.join(', ')}
                    </div>
                  )}
                </div>
              ))
            ) : (
              <div style={{ 
                padding: '40px', 
                textAlign: 'center', 
                color: '#64748b',
                fontStyle: 'italic' 
              }}>
                No decisions yet. Submit a transaction to see real-time fraud detection in action.
              </div>
            )}
          </div>
        </div>

        <div className="card full-width">
          <h2>Recent Transactions</h2>
          <div className="table-container">
            <table>
              <thead>
                <tr>
                  <th>Transaction ID</th>
                  <th>User</th>
                  <th>Amount</th>
                  <th>Risk Score</th>
                  <th>Decision</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {transactions.slice(0, 15).map((txn) => (
                  <tr key={txn.id}>
                    <td className="mono">{txn.transaction_id}</td>
                    <td>{txn.user_id}</td>
                    <td>${txn.amount}</td>
                    <td>
                      <span className={`score-badge ${
                        txn.risk_score < 40 ? 'low' :
                        txn.risk_score < 75 ? 'medium' : 'high'
                      }`}>
                        {txn.risk_score || '-'}
                      </span>
                    </td>
                    <td>
                      <span className={`status-badge ${(txn.decision || '').toLowerCase()}`}>
                        {txn.decision || 'PENDING'}
                      </span>
                    </td>
                    <td>{new Date(txn.timestamp).toLocaleTimeString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
