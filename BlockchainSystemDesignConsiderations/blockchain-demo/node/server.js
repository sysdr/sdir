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
