import React, { useState, useEffect } from 'react';
import './App.css';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

function App() {
  const [nodes, setNodes] = useState({});
  const [selectedNode, setSelectedNode] = useState('node1');
  const [chainHistory, setChainHistory] = useState([]);
  const [ws, setWs] = useState(null);

  useEffect(() => {
    const wsConnections = {};
    const nodeIds = ['node1', 'node2', 'node3'];
    
    nodeIds.forEach(nodeId => {
      const port = nodeId === 'node1' ? 3001 : nodeId === 'node2' ? 3002 : 3003;
      const socket = new WebSocket(`ws://localhost:${port}`);
      
      socket.onopen = () => {
        console.log(`Connected to ${nodeId}`);
      };
      
      socket.onmessage = (event) => {
        const message = JSON.parse(event.data);
        
        setNodes(prev => ({
          ...prev,
          [nodeId]: message.data || message.stats
        }));

        if (message.type === 'block_added' && nodeId === selectedNode) {
          setChainHistory(prev => [
            ...prev,
            {
              time: new Date().toLocaleTimeString(),
              blocks: message.stats.chainLength,
              mempool: message.stats.mempoolSize
            }
          ].slice(-20));
        }
      };
      
      socket.onerror = (error) => {
        console.log(`${nodeId} connection error:`, error);
      };
      
      wsConnections[nodeId] = socket;
    });
    
    setWs(wsConnections);
    
    return () => {
      Object.values(wsConnections).forEach(socket => socket.close());
    };
  }, [selectedNode]);

  const currentNode = nodes[selectedNode];

  return (
    <div className="App">
      <div className="header">
        <h1>⛓️ Blockchain Network Monitor</h1>
        <p>Real-time distributed consensus and state replication</p>
      </div>

      <div className="node-selector">
        {['node1', 'node2', 'node3'].map(nodeId => (
          <button
            key={nodeId}
            className={`node-btn ${selectedNode === nodeId ? 'active' : ''}`}
            onClick={() => setSelectedNode(nodeId)}
          >
            {nodeId.toUpperCase()}
            {nodes[nodeId] && (
              <span className="badge">{nodes[nodeId].chainLength} blocks</span>
            )}
          </button>
        ))}
      </div>

      {currentNode && (
        <>
          <div className="stats-grid">
            <div className="stat-card">
              <div className="stat-icon">🔗</div>
              <div className="stat-content">
                <div className="stat-label">Chain Length</div>
                <div className="stat-value">{currentNode.chainLength}</div>
              </div>
            </div>
            
            <div className="stat-card">
              <div className="stat-icon">⏳</div>
              <div className="stat-content">
                <div className="stat-label">Mempool Size</div>
                <div className="stat-value">{currentNode.mempoolSize}</div>
              </div>
            </div>
            
            <div className="stat-card">
              <div className="stat-icon">💎</div>
              <div className="stat-content">
                <div className="stat-label">Validator Stake</div>
                <div className="stat-value">{currentNode.validatorStake}</div>
              </div>
            </div>
            
            <div className="stat-card">
              <div className="stat-icon">🔐</div>
              <div className="stat-content">
                <div className="stat-label">State Root</div>
                <div className="stat-value hash">{currentNode.latestBlock?.stateRoot || '0x00'}</div>
              </div>
            </div>
          </div>

          <div className="charts-section">
            <div className="chart-card">
              <h3>📊 Blockchain Growth & Mempool Activity</h3>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={chainHistory}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#4a5568" />
                  <XAxis dataKey="time" stroke="#cbd5e0" />
                  <YAxis stroke="#cbd5e0" />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#2d3748',
                      border: 'none',
                      borderRadius: '8px',
                      color: '#fff'
                    }}
                  />
                  <Legend />
                  <Line type="monotone" dataKey="blocks" stroke="#48bb78" strokeWidth={2} name="Blocks" />
                  <Line type="monotone" dataKey="mempool" stroke="#f6ad55" strokeWidth={2} name="Mempool" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="content-grid">
            <div className="section-card">
              <h3>📦 Latest Block</h3>
              <div className="block-info">
                <div className="info-row">
                  <span className="label">Block #:</span>
                  <span className="value">{currentNode.latestBlock.index}</span>
                </div>
                <div className="info-row">
                  <span className="label">Hash:</span>
                  <span className="value hash">{currentNode.latestBlock.hash.substring(0, 16)}...</span>
                </div>
                <div className="info-row">
                  <span className="label">Previous:</span>
                  <span className="value hash">{currentNode.latestBlock.previousHash.substring(0, 16)}...</span>
                </div>
                <div className="info-row">
                  <span className="label">Validator:</span>
                  <span className="value">{currentNode.latestBlock.validator}</span>
                </div>
                <div className="info-row">
                  <span className="label">Transactions:</span>
                  <span className="value">{currentNode.latestBlock.transactions.length}</span>
                </div>
              </div>
            </div>

            <div className="section-card">
              <h3>👥 Account Balances</h3>
              <div className="accounts-list">
                {Object.entries(currentNode.accounts).map(([name, account]) => (
                  <div key={name} className="account-row">
                    <div className="account-name">{name}</div>
                    <div className="account-balance">{account.balance.toFixed(2)} ETH</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

export default App;
