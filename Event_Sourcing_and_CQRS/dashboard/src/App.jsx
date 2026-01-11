import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import './App.css';

const API_BASE = 'http://localhost:3002';
const QUERY_API = 'http://localhost:3003';
const EVENT_STORE = 'http://localhost:3001';
const PROJECTION_API = 'http://localhost:3004';

function App() {
  const [accounts, setAccounts] = useState([]);
  const [events, setEvents] = useState([]);
  const [projectionStats, setProjectionStats] = useState(null);
  const [commandLog, setCommandLog] = useState([]);
  const [newAccount, setNewAccount] = useState({ id: '', balance: 1000 });
  const [transaction, setTransaction] = useState({ accountId: '', amount: 0 });
  const wsRef = useRef(null);

  useEffect(() => {
    loadAccounts();
    loadEvents();
    loadCommandLog();
    loadProjectionStats();
    connectWebSocket();

    const interval = setInterval(() => {
      loadAccounts();
      loadEvents();
      loadCommandLog();
      loadProjectionStats();
    }, 2000);

    return () => {
      clearInterval(interval);
      if (wsRef.current) wsRef.current.close();
    };
  }, []);

  const connectWebSocket = () => {
    wsRef.current = new WebSocket('ws://localhost:3001');
    
    wsRef.current.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'NEW_EVENT') {
        setEvents(prev => [data.event, ...prev].slice(0, 15));
      }
    };

    wsRef.current.onclose = () => {
      setTimeout(connectWebSocket, 3000);
    };
  };

  const loadAccounts = async () => {
    try {
      const res = await axios.get(`${QUERY_API}/accounts`);
      setAccounts(res.data);
    } catch (err) {
      console.error('Error loading accounts:', err);
    }
  };

  const loadEvents = async () => {
    try {
      const res = await axios.get(`${EVENT_STORE}/events/all/stream`);
      setEvents(res.data.slice(-15).reverse());
    } catch (err) {
      console.error('Error loading events:', err);
    }
  };

  const loadCommandLog = async () => {
    try {
      const res = await axios.get(`${API_BASE}/commands/log`);
      setCommandLog(res.data.reverse());
    } catch (err) {
      console.error('Error loading command log:', err);
    }
  };

  const loadProjectionStats = async () => {
    try {
      const res = await axios.get(`${PROJECTION_API}/stats`);
      setProjectionStats(res.data);
    } catch (err) {
      console.error('Error loading projection stats:', err);
    }
  };

  const createAccount = async () => {
    try {
      await axios.post(`${API_BASE}/commands/create-account`, {
        accountId: newAccount.id,
        initialBalance: parseFloat(newAccount.balance)
      });
      setNewAccount({ id: '', balance: 1000 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error creating account');
    }
  };

  const deposit = async () => {
    try {
      await axios.post(`${API_BASE}/commands/deposit`, {
        accountId: transaction.accountId,
        amount: parseFloat(transaction.amount)
      });
      setTransaction({ accountId: '', amount: 0 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error depositing');
    }
  };

  const withdraw = async () => {
    try {
      await axios.post(`${API_BASE}/commands/withdraw`, {
        accountId: transaction.accountId,
        amount: parseFloat(transaction.amount)
      });
      setTransaction({ accountId: '', amount: 0 });
    } catch (err) {
      alert(err.response?.data?.error || 'Error withdrawing');
    }
  };

  const replay = async () => {
    if (!confirm('Replay projection from scratch? This will rebuild all read models.')) return;
    try {
      await axios.post(`${PROJECTION_API}/replay`);
      alert('Projection replay started! Watch the stats update.');
    } catch (err) {
      alert('Error replaying projection');
    }
  };

  return (
    <div className="app">
      <div className="header">
        <h1>⚡ Event Sourcing & CQRS</h1>
        <p className="subtitle">Watch commands flow through the CQRS pipeline in real-time</p>
      </div>

      <div className="grid">
        {/* Commands Section */}
        <div className="card">
          <h2>📝 Commands (Write Side)</h2>
          <div className="command-form">
            <h3>Create Account</h3>
            <input
              type="text"
              placeholder="Account ID"
              value={newAccount.id}
              onChange={(e) => setNewAccount({...newAccount, id: e.target.value})}
            />
            <input
              type="number"
              placeholder="Initial Balance"
              value={newAccount.balance}
              onChange={(e) => setNewAccount({...newAccount, balance: e.target.value})}
            />
            <button onClick={createAccount}>Create</button>
          </div>

          <div className="command-form">
            <h3>Transactions</h3>
            <input
              type="text"
              placeholder="Account ID"
              value={transaction.accountId}
              onChange={(e) => setTransaction({...transaction, accountId: e.target.value})}
            />
            <input
              type="number"
              placeholder="Amount"
              value={transaction.amount}
              onChange={(e) => setTransaction({...transaction, amount: e.target.value})}
            />
            <div className="button-group">
              <button onClick={deposit}>Deposit</button>
              <button onClick={withdraw}>Withdraw</button>
            </div>
          </div>

          <div className="command-log">
            <h3>Recent Commands</h3>
            {commandLog.slice(0, 8).map((cmd, i) => (
              <div key={i} className="log-entry">
                <span className="command-type">{cmd.command}</span>
                <span className="command-detail">{cmd.accountId}</span>
                {cmd.amount && <span className="command-amount">${cmd.amount}</span>}
              </div>
            ))}
          </div>
        </div>

        {/* Event Store Section */}
        <div className="card">
          <h2>📦 Event Store (Immutable Log)</h2>
          <div className="events-list">
            {events.map((event) => (
              <div key={event.event_id || event.eventId} className="event-entry">
                <div className="event-header">
                  <span className="event-type">{event.event_type || event.type}</span>
                  <span className="event-seq">#{event.sequence_number || event.sequenceNumber}</span>
                </div>
                <div className="event-data">
                  {event.aggregate_id || event.aggregateId}
                </div>
                <div className="event-time">
                  {new Date(event.timestamp).toLocaleTimeString()}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Projection Stats Section */}
        <div className="card">
          <h2>⚙️ Projection Service</h2>
          {projectionStats && (
            <div className="stats-grid">
              <div className="stat-card">
                <div className="stat-value">{projectionStats.lastProcessedSequence}</div>
                <div className="stat-label">Last Processed</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.totalProcessed}</div>
                <div className="stat-label">Total Processed</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.lagMs}ms</div>
                <div className="stat-label">Projection Lag</div>
              </div>
              <div className="stat-card">
                <div className="stat-value">{projectionStats.errors}</div>
                <div className="stat-label">Errors</div>
              </div>
            </div>
          )}
          <button className="replay-btn" onClick={replay}>🔄 Replay Projection</button>
        </div>

        {/* Query Section */}
        <div className="card">
          <h2>🔍 Query Service (Read Models)</h2>
          <div className="accounts-list">
            {accounts.map((account) => (
              <div key={account.accountId} className="account-card">
                <div className="account-header">
                  <h3>{account.accountId}</h3>
                  <div className="account-balance">${account.balance.toFixed(2)}</div>
                </div>
                <div className="account-details">
                  <span>Transactions: {account.transactionCount}</span>
                  <span className="account-time">
                    Updated: {new Date(account.lastUpdated).toLocaleTimeString()}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="info-panel">
        <h3>💡 Key Concepts</h3>
        <ul>
          <li><strong>Commands</strong> → Generate events based on business rules</li>
          <li><strong>Event Store</strong> → Immutable, append-only log of all changes</li>
          <li><strong>Projections</strong> → Asynchronously build read models from events</li>
          <li><strong>Queries</strong> → Read optimized views (eventual consistency)</li>
          <li><strong>Replay</strong> → Rebuild projections from scratch to recover or add new views</li>
        </ul>
      </div>
    </div>
  );
}

export default App;
