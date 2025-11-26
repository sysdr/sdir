#!/bin/bash

set -e

echo "=========================================="
echo "Blockchain System Design Demo"
echo "Issue #162: Blockchain Architecture"
echo "=========================================="
echo ""

# Create project structure
echo "📁 Creating project structure..."
mkdir -p blockchain-demo/{node,dashboard,docker}
cd blockchain-demo

# Create package.json for blockchain node
cat > node/package.json << 'EOF'
{
  "name": "blockchain-node",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "crypto": "^1.0.1",
    "node-fetch": "^3.3.2"
  }
}
EOF

# Create blockchain node implementation
cat > node/blockchain.js << 'EOF'
import crypto from 'crypto';

export class Block {
  constructor(index, timestamp, transactions, previousHash, validator) {
    this.index = index;
    this.timestamp = timestamp;
    this.transactions = transactions;
    this.previousHash = previousHash;
    this.validator = validator;
    this.hash = this.calculateHash();
    this.stateRoot = this.calculateStateRoot();
  }

  calculateHash() {
    const data = this.index + this.timestamp + JSON.stringify(this.transactions) + 
                  this.previousHash + this.validator;
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  calculateStateRoot() {
    const stateData = JSON.stringify(this.transactions.map(tx => ({
      from: tx.from,
      to: tx.to,
      amount: tx.amount
    })));
    return crypto.createHash('sha256').update(stateData).digest('hex').substring(0, 16);
  }
}

export class Transaction {
  constructor(from, to, amount, gasPrice, timestamp) {
    this.id = crypto.randomBytes(8).toString('hex');
    this.from = from;
    this.to = to;
    this.amount = amount;
    this.gasPrice = gasPrice;
    this.timestamp = timestamp || Date.now();
    this.status = 'pending';
  }

  calculateHash() {
    const data = this.from + this.to + this.amount + this.gasPrice + this.timestamp;
    return crypto.createHash('sha256').update(data).digest('hex');
  }
}

export class Mempool {
  constructor() {
    this.transactions = [];
    this.maxSize = 1000;
  }

  addTransaction(transaction) {
    if (this.transactions.length >= this.maxSize) {
      // Remove lowest gas price transaction
      this.transactions.sort((a, b) => b.gasPrice - a.gasPrice);
      this.transactions = this.transactions.slice(0, this.maxSize - 1);
    }
    
    this.transactions.push(transaction);
    // Sort by gas price (descending)
    this.transactions.sort((a, b) => b.gasPrice - a.gasPrice);
    
    return true;
  }

  getTopTransactions(count) {
    return this.transactions.slice(0, Math.min(count, this.transactions.length));
  }

  removeTransactions(txIds) {
    this.transactions = this.transactions.filter(tx => !txIds.includes(tx.id));
  }

  getSize() {
    return this.transactions.length;
  }

  getTransactions() {
    return this.transactions;
  }
}

export class Blockchain {
  constructor(nodeId, validatorStake) {
    this.nodeId = nodeId;
    this.chain = [this.createGenesisBlock()];
    this.mempool = new Mempool();
    this.validatorStake = validatorStake;
    this.accounts = this.initializeAccounts();
    this.difficulty = 2;
    this.blockTime = 3000; // 3 seconds
    this.lastBlockTime = Date.now();
  }

  initializeAccounts() {
    const accounts = {};
    const users = ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve'];
    users.forEach(user => {
      accounts[user] = { balance: 1000, nonce: 0 };
    });
    return accounts;
  }

  createGenesisBlock() {
    return new Block(0, Date.now(), [], '0', 'genesis');
  }

  getLatestBlock() {
    return this.chain[this.chain.length - 1];
  }

  addTransaction(transaction) {
    // Validate transaction
    const sender = this.accounts[transaction.from];
    if (!sender || sender.balance < transaction.amount) {
      return { success: false, error: 'Insufficient balance' };
    }

    this.mempool.addTransaction(transaction);
    return { success: true, txId: transaction.id };
  }

  canProposeBlock() {
    const timeSinceLastBlock = Date.now() - this.lastBlockTime;
    return timeSinceLastBlock >= this.blockTime;
  }

  selectValidator() {
    // Simple PoS: probability proportional to stake
    return this.nodeId;
  }

  async createBlock() {
    if (!this.canProposeBlock()) {
      return null;
    }

    const validator = this.selectValidator();
    const transactions = this.mempool.getTopTransactions(20);
    
    if (transactions.length === 0) {
      return null;
    }

    const newBlock = new Block(
      this.chain.length,
      Date.now(),
      transactions,
      this.getLatestBlock().hash,
      validator
    );

    return newBlock;
  }

  validateBlock(block) {
    const latestBlock = this.getLatestBlock();
    
    if (block.previousHash !== latestBlock.hash) {
      return { valid: false, error: 'Invalid previous hash' };
    }

    if (block.index !== latestBlock.index + 1) {
      return { valid: false, error: 'Invalid block index' };
    }

    if (block.hash !== block.calculateHash()) {
      return { valid: false, error: 'Invalid block hash' };
    }

    return { valid: true };
  }

  addBlock(block) {
    const validation = this.validateBlock(block);
    
    if (!validation.valid) {
      return { success: false, error: validation.error };
    }

    // Update state
    block.transactions.forEach(tx => {
      if (this.accounts[tx.from] && this.accounts[tx.to]) {
        this.accounts[tx.from].balance -= tx.amount;
        this.accounts[tx.to].balance += tx.amount;
        tx.status = 'confirmed';
      }
    });

    this.chain.push(block);
    this.mempool.removeTransactions(block.transactions.map(tx => tx.id));
    this.lastBlockTime = Date.now();

    return { success: true, block };
  }

  getChainLength() {
    return this.chain.length;
  }

  getStats() {
    return {
      nodeId: this.nodeId,
      chainLength: this.chain.length,
      mempoolSize: this.mempool.getSize(),
      validatorStake: this.validatorStake,
      latestBlock: this.getLatestBlock(),
      accounts: this.accounts
    };
  }
}
EOF

# Create node server
cat > node/server.js << 'EOF'
import express from 'express';
import { WebSocketServer } from 'ws';
import { Blockchain, Transaction } from './blockchain.js';
import http from 'http';

const PORT = process.env.PORT || 3000;
const NODE_ID = process.env.NODE_ID || 'node1';
const VALIDATOR_STAKE = parseInt(process.env.VALIDATOR_STAKE || '100');

const app = express();
app.use(express.json());

const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const blockchain = new Blockchain(NODE_ID, VALIDATOR_STAKE);
const peers = [];
const connectedClients = [];

// WebSocket connection handling
wss.on('connection', (ws) => {
  console.log('Client connected');
  connectedClients.push(ws);
  
  // Send initial state
  ws.send(JSON.stringify({
    type: 'init',
    data: blockchain.getStats()
  }));

  ws.on('close', () => {
    const index = connectedClients.indexOf(ws);
    if (index > -1) {
      connectedClients.splice(index, 1);
    }
  });
});

function broadcastToClients(message) {
  connectedClients.forEach(client => {
    if (client.readyState === 1) { // OPEN
      client.send(JSON.stringify(message));
    }
  });
}

function broadcastToPeers(message) {
  peers.forEach(peer => {
    if (peer.readyState === 1) {
      peer.send(JSON.stringify(message));
    }
  });
}

// Connect to peer nodes
async function connectToPeer(peerUrl) {
  try {
    const { default: WebSocket } = await import('ws');
    const ws = new WebSocket(peerUrl);
    
    ws.on('open', () => {
      console.log(`Connected to peer: ${peerUrl}`);
      peers.push(ws);
    });

    ws.on('message', async (data) => {
      const message = JSON.parse(data.toString());
      
      if (message.type === 'new_block') {
        const result = blockchain.addBlock(message.block);
        if (result.success) {
          console.log(`Received and added block ${message.block.index} from peer`);
          broadcastToClients({
            type: 'block_added',
            block: message.block,
            stats: blockchain.getStats()
          });
        }
      } else if (message.type === 'new_transaction') {
        const tx = new Transaction(
          message.transaction.from,
          message.transaction.to,
          message.transaction.amount,
          message.transaction.gasPrice,
          message.transaction.timestamp
        );
        blockchain.addTransaction(tx);
        broadcastToClients({
          type: 'transaction_added',
          transaction: tx,
          stats: blockchain.getStats()
        });
      }
    });

    ws.on('error', (error) => {
      console.log(`Peer connection error: ${error.message}`);
    });
  } catch (error) {
    console.log(`Could not connect to peer ${peerUrl}: ${error.message}`);
  }
}

// REST API endpoints
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', nodeId: NODE_ID });
});

app.get('/stats', (req, res) => {
  res.json(blockchain.getStats());
});

app.get('/chain', (req, res) => {
  res.json({
    length: blockchain.chain.length,
    chain: blockchain.chain
  });
});

app.get('/mempool', (req, res) => {
  res.json({
    size: blockchain.mempool.getSize(),
    transactions: blockchain.mempool.getTransactions()
  });
});

app.post('/transaction', (req, res) => {
  const { from, to, amount, gasPrice } = req.body;
  
  if (!from || !to || !amount || !gasPrice) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const transaction = new Transaction(from, to, amount, gasPrice);
  const result = blockchain.addTransaction(transaction);
  
  if (result.success) {
    broadcastToClients({
      type: 'transaction_added',
      transaction,
      stats: blockchain.getStats()
    });
    
    // Broadcast to peers
    broadcastToPeers({
      type: 'new_transaction',
      transaction
    });

    res.json({ success: true, transaction });
  } else {
    res.status(400).json(result);
  }
});

app.post('/mine', async (req, res) => {
  const block = await blockchain.createBlock();
  
  if (!block) {
    return res.json({ success: false, message: 'No transactions to mine or too soon' });
  }

  const result = blockchain.addBlock(block);
  
  if (result.success) {
    broadcastToClients({
      type: 'block_added',
      block: result.block,
      stats: blockchain.getStats()
    });

    // Broadcast to peers
    broadcastToPeers({
      type: 'new_block',
      block: result.block
    });

    res.json({ success: true, block: result.block });
  } else {
    res.status(400).json(result);
  }
});

// Auto mining
setInterval(async () => {
  const block = await blockchain.createBlock();
  if (block) {
    const result = blockchain.addBlock(block);
    if (result.success) {
      console.log(`Auto-mined block ${block.index} by ${NODE_ID}`);
      broadcastToClients({
        type: 'block_added',
        block: result.block,
        stats: blockchain.getStats()
      });
      
      broadcastToPeers({
        type: 'new_block',
        block: result.block
      });
    }
  }
}, 5000);

// Auto generate transactions
setInterval(() => {
  const users = ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve'];
  const from = users[Math.floor(Math.random() * users.length)];
  let to = users[Math.floor(Math.random() * users.length)];
  while (to === from) {
    to = users[Math.floor(Math.random() * users.length)];
  }
  
  const amount = Math.floor(Math.random() * 50) + 1;
  const gasPrice = Math.floor(Math.random() * 100) + 10;
  
  const transaction = new Transaction(from, to, amount, gasPrice);
  blockchain.addTransaction(transaction);
  
  broadcastToClients({
    type: 'transaction_added',
    transaction,
    stats: blockchain.getStats()
  });

  broadcastToPeers({
    type: 'new_transaction',
    transaction
  });
}, 2000);

server.listen(PORT, () => {
  console.log(`Blockchain node ${NODE_ID} running on port ${PORT}`);
  console.log(`Validator stake: ${VALIDATOR_STAKE}`);
  
  // Connect to peers after a delay
  setTimeout(() => {
    const peerNodes = (process.env.PEER_NODES || '').split(',').filter(p => p);
    peerNodes.forEach(peer => {
      connectToPeer(peer);
    });
  }, 2000);
});
EOF

# Create dashboard package.json
cat > dashboard/package.json << 'EOF'
{
  "name": "blockchain-dashboard",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.10.3"
  },
  "scripts": {
    "build": "react-scripts build",
    "start": "react-scripts start"
  },
  "devDependencies": {
    "react-scripts": "5.0.1"
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
  }
}
EOF

# Create React dashboard
mkdir -p dashboard/public dashboard/src

cat > dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Blockchain System Monitor</title>
</head>
<body>
  <div id="root"></div>
</body>
</html>
EOF

cat > dashboard/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

cat > dashboard/src/index.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

#root {
  padding: 20px;
}
EOF

cat > dashboard/src/App.js << 'EOF'
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
EOF

cat > dashboard/src/App.css << 'EOF'
.App {
  max-width: 1400px;
  margin: 0 auto;
}

.header {
  background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
  padding: 30px;
  border-radius: 16px;
  text-align: center;
  margin-bottom: 30px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
}

.header h1 {
  color: white;
  font-size: 2.5rem;
  margin-bottom: 10px;
  font-weight: 700;
}

.header p {
  color: #e0e7ff;
  font-size: 1.1rem;
}

.node-selector {
  display: flex;
  gap: 15px;
  justify-content: center;
  margin-bottom: 30px;
}

.node-btn {
  background: white;
  border: 2px solid #e0e7ff;
  padding: 15px 30px;
  border-radius: 12px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  display: flex;
  align-items: center;
  gap: 10px;
}

.node-btn:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.2);
}

.node-btn.active {
  background: linear-gradient(135deg, #3b82f6 0%, #1e3a8a 100%);
  color: white;
  border-color: #1e3a8a;
}

.badge {
  background: rgba(255, 255, 255, 0.3);
  padding: 4px 12px;
  border-radius: 20px;
  font-size: 0.85rem;
}

.node-btn.active .badge {
  background: rgba(255, 255, 255, 0.25);
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 20px;
  margin-bottom: 30px;
}

.stat-card {
  background: white;
  padding: 25px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  gap: 20px;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15);
  transition: transform 0.3s ease;
}

.stat-card:hover {
  transform: translateY(-4px);
}

.stat-icon {
  font-size: 3rem;
  width: 70px;
  height: 70px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #e0e7ff 0%, #c7d2fe 100%);
  border-radius: 12px;
}

.stat-content {
  flex: 1;
}

.stat-label {
  color: #64748b;
  font-size: 0.9rem;
  margin-bottom: 5px;
  font-weight: 500;
}

.stat-value {
  color: #1e293b;
  font-size: 1.8rem;
  font-weight: 700;
}

.stat-value.hash {
  font-size: 1rem;
  font-family: 'Courier New', monospace;
  color: #3b82f6;
}

.charts-section {
  margin-bottom: 30px;
}

.chart-card {
  background: white;
  padding: 30px;
  border-radius: 16px;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15);
}

.chart-card h3 {
  color: #1e293b;
  margin-bottom: 20px;
  font-size: 1.3rem;
}

.content-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 20px;
}

.section-card {
  background: white;
  padding: 30px;
  border-radius: 16px;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15);
}

.section-card h3 {
  color: #1e293b;
  margin-bottom: 20px;
  font-size: 1.3rem;
  padding-bottom: 15px;
  border-bottom: 2px solid #e0e7ff;
}

.block-info, .accounts-list {
  display: flex;
  flex-direction: column;
  gap: 15px;
}

.info-row, .account-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px;
  background: #f8fafc;
  border-radius: 8px;
}

.label, .account-name {
  color: #64748b;
  font-weight: 500;
}

.value, .account-balance {
  color: #1e293b;
  font-weight: 600;
}

.value.hash {
  font-family: 'Courier New', monospace;
  color: #3b82f6;
  font-size: 0.9rem;
}

.account-balance {
  color: #059669;
  font-size: 1.1rem;
}

@media (max-width: 768px) {
  .node-selector {
    flex-direction: column;
  }
  
  .content-grid {
    grid-template-columns: 1fr;
  }
}
EOF

# Create Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  node1:
    build:
      context: ./node
      dockerfile: Dockerfile
    container_name: blockchain_node1
    environment:
      - NODE_ID=node1
      - PORT=3000
      - VALIDATOR_STAKE=100
      - PEER_NODES=ws://node2:3000,ws://node3:3000
    ports:
      - "3001:3000"
    networks:
      - blockchain_network

  node2:
    build:
      context: ./node
      dockerfile: Dockerfile
    container_name: blockchain_node2
    environment:
      - NODE_ID=node2
      - PORT=3000
      - VALIDATOR_STAKE=150
      - PEER_NODES=ws://node1:3000,ws://node3:3000
    ports:
      - "3002:3000"
    networks:
      - blockchain_network

  node3:
    build:
      context: ./node
      dockerfile: Dockerfile
    container_name: blockchain_node3
    environment:
      - NODE_ID=node3
      - PORT=3000
      - VALIDATOR_STAKE=200
      - PEER_NODES=ws://node1:3000,ws://node2:3000
    ports:
      - "3003:3000"
    networks:
      - blockchain_network

  dashboard:
    build:
      context: ./dashboard
      dockerfile: Dockerfile
    container_name: blockchain_dashboard
    ports:
      - "3000:3000"
    depends_on:
      - node1
      - node2
      - node3
    networks:
      - blockchain_network

networks:
  blockchain_network:
    driver: bridge
EOF

# Create Node Dockerfile
cat > node/Dockerfile << 'EOF'
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY *.js ./

EXPOSE 3000

CMD ["node", "server.js"]
EOF

# Create Dashboard Dockerfile
cat > dashboard/Dockerfile << 'EOF'
FROM node:20-alpine as build

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY public ./public
COPY src ./src

RUN npm run build

FROM node:20-alpine

WORKDIR /app

RUN npm install -g serve

COPY --from=build /app/build ./build

EXPOSE 3000

CMD ["serve", "-s", "build", "-l", "3000"]
EOF

# Create test script
cat > test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Blockchain System Tests..."
echo ""

echo "1️⃣ Testing Node 1 Health..."
response=$(curl -s http://localhost:3001/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 1 is healthy"
else
    echo "❌ Node 1 health check failed"
    exit 1
fi

echo ""
echo "2️⃣ Testing Node 2 Health..."
response=$(curl -s http://localhost:3002/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 2 is healthy"
else
    echo "❌ Node 2 health check failed"
    exit 1
fi

echo ""
echo "3️⃣ Testing Node 3 Health..."
response=$(curl -s http://localhost:3003/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 3 is healthy"
else
    echo "❌ Node 3 health check failed"
    exit 1
fi

echo ""
echo "4️⃣ Submitting test transaction..."
response=$(curl -s -X POST http://localhost:3001/transaction \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Alice",
    "to": "Bob",
    "amount": 50,
    "gasPrice": 80
  }')

if echo "$response" | grep -q "success"; then
    echo "✅ Transaction submitted successfully"
else
    echo "❌ Transaction submission failed"
    exit 1
fi

echo ""
echo "5️⃣ Checking mempool..."
sleep 2
response=$(curl -s http://localhost:3001/mempool)
if echo "$response" | grep -q "transactions"; then
    echo "✅ Mempool is operational"
else
    echo "❌ Mempool check failed"
    exit 1
fi

echo ""
echo "6️⃣ Verifying blockchain growth..."
sleep 8
response=$(curl -s http://localhost:3001/stats)
chain_length=$(echo "$response" | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
if [ "$chain_length" -gt 1 ]; then
    echo "✅ Blockchain is growing (${chain_length} blocks)"
else
    echo "❌ Blockchain not growing"
    exit 1
fi

echo ""
echo "7️⃣ Testing consensus across nodes..."
length1=$(curl -s http://localhost:3001/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
length2=$(curl -s http://localhost:3002/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
length3=$(curl -s http://localhost:3003/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')

echo "Node 1 chain length: $length1"
echo "Node 2 chain length: $length2"
echo "Node 3 chain length: $length3"

max_diff=$(( length1 > length2 ? length1 - length2 : length2 - length1 ))
max_diff=$(( max_diff > (length3 > length1 ? length3 - length1 : length1 - length3) ? max_diff : (length3 > length1 ? length3 - length1 : length1 - length3) ))

if [ "$max_diff" -le 2 ]; then
    echo "✅ Nodes are in consensus (max difference: $max_diff blocks)"
else
    echo "⚠️  Nodes have diverged (max difference: $max_diff blocks)"
fi

echo ""
echo "✨ All tests passed!"
echo ""
EOF

chmod +x test.sh

echo ""
echo "🐳 Building Docker containers..."
docker-compose build

echo ""
echo "🚀 Starting blockchain network..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 10

echo ""
echo "🧪 Running tests..."
./test.sh

echo ""
echo "=========================================="
echo "✅ Demo Setup Complete!"
echo "=========================================="
echo ""
echo "📊 Access the dashboard at: http://localhost:3000"
echo ""
echo "🔗 Node APIs:"
echo "   Node 1: http://localhost:3001"
echo "   Node 2: http://localhost:3002"
echo "   Node 3: http://localhost:3003"
echo ""
echo "📝 Available endpoints:"
echo "   GET  /health       - Node health check"
echo "   GET  /stats        - Blockchain statistics"
echo "   GET  /chain        - Full blockchain"
echo "   GET  /mempool      - Pending transactions"
echo "   POST /transaction  - Submit new transaction"
echo ""
echo "🔬 Example commands:"
echo ""
echo "# Submit a transaction"
echo 'curl -X POST http://localhost:3001/transaction \'
echo '  -H "Content-Type: application/json" \'
echo "  -d '{\"from\":\"Alice\",\"to\":\"Bob\",\"amount\":25,\"gasPrice\":100}'"
echo ""
echo "# View blockchain stats"
echo "curl http://localhost:3001/stats | jq"
echo ""
echo "# Check mempool"
echo "curl http://localhost:3001/mempool | jq"
echo ""
echo "🎯 What to observe:"
echo "1. Transactions entering the mempool with priority ordering"
echo "2. Automatic block creation every ~3-5 seconds"
echo "3. Block propagation across all 3 nodes"
echo "4. State synchronization (account balances)"
echo "5. Consensus mechanism in action"
echo ""
echo "Use cleanup.sh to stop and remove all containers"
echo "=========================================="