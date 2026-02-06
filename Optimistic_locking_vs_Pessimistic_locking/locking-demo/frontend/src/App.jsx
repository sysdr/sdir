import React, { useState, useEffect, useRef } from 'react';
import './App.css';

const API_URL = 'http://localhost:3001';
const WS_URL = 'ws://localhost:3001';

function App() {
  const [accountBalance, setAccountBalance] = useState(1000);
  const [accountVersion, setAccountVersion] = useState(0);
  const [transactions, setTransactions] = useState([]);
  const [stats, setStats] = useState({
    pessimistic: { total: 0, successful: 0, failed: 0, avgDuration: 0, avgLockWait: 0 },
    optimistic: { total: 0, successful: 0, failed: 0, avgDuration: 0, avgRetries: 0 }
  });
  const [isRunning, setIsRunning] = useState(false);
  const wsRef = useRef(null);

  useEffect(() => {
    fetchAccount();
    
    // WebSocket connection
    wsRef.current = new WebSocket(WS_URL);
    
    wsRef.current.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      if (data.type === 'transaction') {
        setTransactions(prev => [data, ...prev].slice(0, 50));
        
        setStats(prev => {
          const mode = data.mode;
          const modeStats = prev[mode];
          const total = modeStats.total + 1;
          const successful = modeStats.successful + (data.success ? 1 : 0);
          const failed = modeStats.failed + (data.success ? 0 : 1);
          
          let avgDuration = modeStats.avgDuration;
          let avgLockWait = modeStats.avgLockWait;
          let avgRetries = modeStats.avgRetries;
          
          if (data.success) {
            avgDuration = ((modeStats.avgDuration * modeStats.successful) + data.duration) / successful;
            
            if (mode === 'pessimistic') {
              avgLockWait = ((modeStats.avgLockWait * modeStats.successful) + data.lockWaitTime) / successful;
            } else {
              avgRetries = ((modeStats.avgRetries * modeStats.successful) + data.retries) / successful;
            }
          }
          
          return {
            ...prev,
            [mode]: {
              total,
              successful,
              failed,
              avgDuration: Math.round(avgDuration),
              avgLockWait: Math.round(avgLockWait),
              avgRetries: Math.round(avgRetries * 10) / 10
            }
          };
        });
      }
      
      if (data.type === 'reset') {
        setAccountBalance(data.balance);
        setAccountVersion(data.version);
        setTransactions([]);
        setStats({
          pessimistic: { total: 0, successful: 0, failed: 0, avgDuration: 0, avgLockWait: 0 },
          optimistic: { total: 0, successful: 0, failed: 0, avgDuration: 0, avgRetries: 0 }
        });
      }
      
      if (data.type === 'batch_complete') {
        setStats(prev => {
          const mode = data.mode;
          const modeStats = prev[mode];
          return {
            ...prev,
            [mode]: {
              ...modeStats,
              total: data.total,
              successful: data.successful,
              failed: data.failed
            }
          };
        });
      }
      
      if (data.success && data.newBalance !== undefined) {
        setAccountBalance(data.newBalance);
      }
    };
    
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const fetchAccount = async () => {
    try {
      const response = await fetch(`${API_URL}/api/account`);
      const data = await response.json();
      setAccountBalance(data.balance);
      setAccountVersion(data.version);
    } catch (error) {
      console.error('Failed to fetch account:', error);
    }
  };

  const runBatch = async (mode) => {
    setIsRunning(true);
    try {
      await fetch(`${API_URL}/api/batch`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mode,
          count: 100,
          amount: Math.random() > 0.5 ? 10 : -10
        })
      });
    } catch (error) {
      console.error('Batch failed:', error);
    } finally {
      setIsRunning(false);
      fetchAccount();
    }
  };

  const resetAccount = async () => {
    try {
      await fetch(`${API_URL}/api/reset`, { method: 'POST' });
      fetchAccount();
    } catch (error) {
      console.error('Reset failed:', error);
    }
  };

  return (
    <div className="app">
      <header className="header">
        <h1>🔒 Locking Strategies Demo</h1>
        <p>Optimistic vs Pessimistic Concurrency Control</p>
      </header>

      <div className="account-card">
        <div className="account-info">
          <h2>Account Balance</h2>
          <div className="balance">${accountBalance.toFixed(2)}</div>
          <div className="version">Version: {accountVersion}</div>
        </div>
        <button onClick={resetAccount} className="btn btn-reset">
          Reset Account
        </button>
      </div>

      <div className="controls">
        <button 
          onClick={() => runBatch('pessimistic')} 
          disabled={isRunning}
          className="btn btn-pessimistic"
        >
          Run 100 Pessimistic Transactions
        </button>
        <button 
          onClick={() => runBatch('optimistic')} 
          disabled={isRunning}
          className="btn btn-optimistic"
        >
          Run 100 Optimistic Transactions
        </button>
      </div>

      <div className="stats-grid">
        <div className="stat-card pessimistic">
          <h3>⛔ Pessimistic Locking</h3>
          <div className="stat-row">
            <span>Total:</span>
            <span>{stats.pessimistic.total}</span>
          </div>
          <div className="stat-row success">
            <span>Successful:</span>
            <span>{stats.pessimistic.successful}</span>
          </div>
          <div className="stat-row failed">
            <span>Failed:</span>
            <span>{stats.pessimistic.failed}</span>
          </div>
          <div className="stat-row">
            <span>Avg Duration:</span>
            <span>{stats.pessimistic.total > 0 ? `${stats.pessimistic.avgDuration}ms` : '—'}</span>
          </div>
          <div className="stat-row">
            <span>Avg Lock Wait:</span>
            <span>{stats.pessimistic.total > 0 ? `${stats.pessimistic.avgLockWait}ms` : '—'}</span>
          </div>
          <div className="stat-description">
            Blocks concurrent access with SELECT FOR UPDATE
          </div>
        </div>

        <div className="stat-card optimistic">
          <h3>✅ Optimistic Locking</h3>
          <div className="stat-row">
            <span>Total:</span>
            <span>{stats.optimistic.total}</span>
          </div>
          <div className="stat-row success">
            <span>Successful:</span>
            <span>{stats.optimistic.successful}</span>
          </div>
          <div className="stat-row failed">
            <span>Failed:</span>
            <span>{stats.optimistic.failed}</span>
          </div>
          <div className="stat-row">
            <span>Avg Duration:</span>
            <span>{stats.optimistic.total > 0 ? `${stats.optimistic.avgDuration}ms` : '—'}</span>
          </div>
          <div className="stat-row">
            <span>Avg Retries:</span>
            <span>{stats.optimistic.total > 0 ? stats.optimistic.avgRetries : '—'}</span>
          </div>
          <div className="stat-description">
            Detects conflicts with version checking
          </div>
        </div>
      </div>

      <div className="transactions-panel">
        <h3>Recent Transactions</h3>
        <div className="transactions-list">
          {transactions.map((tx, index) => (
            <div key={index} className={`transaction-item ${tx.mode} ${tx.success ? 'success' : 'failed'}`}>
              <div className="tx-header">
                <span className="tx-mode">{tx.mode}</span>
                <span className={`tx-status ${tx.success ? 'success' : 'failed'}`}>
                  {tx.success ? '✓' : '✗'}
                </span>
              </div>
              <div className="tx-details">
                {tx.success ? (
                  <>
                    <span>Amount: ${tx.amount > 0 ? '+' : ''}{tx.amount.toFixed(2)}</span>
                    <span>Duration: {tx.duration}ms</span>
                    {tx.mode === 'pessimistic' && <span>Lock Wait: {tx.lockWaitTime}ms</span>}
                    {tx.mode === 'optimistic' && tx.retries > 0 && <span>Retries: {tx.retries}</span>}
                  </>
                ) : (
                  <span className="error">{tx.error}</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
