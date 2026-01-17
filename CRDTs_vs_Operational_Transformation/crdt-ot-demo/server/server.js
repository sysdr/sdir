import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';

const app = express();
app.use(cors());
app.use(express.json());

const server = createServer(app);
const wss = new WebSocketServer({ server });

// Document state for OT
let otDocument = {
  content: "Start typing here...",
  version: 0,
  operations: []
};

// Connected clients
const clients = new Set();

// Operational Transformation functions
class OTOperation {
  constructor(type, position, value, version) {
    this.id = uuidv4();
    this.type = type; // 'insert' or 'delete'
    this.position = position;
    this.value = value;
    this.version = version;
    this.timestamp = Date.now();
  }
}

function transformOperation(op1, op2) {
  // Transform op1 against op2
  const transformed = { ...op1 };
  
  if (op1.type === 'insert' && op2.type === 'insert') {
    if (op2.position <= op1.position) {
      transformed.position += op2.value.length;
    }
  } else if (op1.type === 'insert' && op2.type === 'delete') {
    if (op2.position < op1.position) {
      transformed.position -= op2.value.length;
    }
  } else if (op1.type === 'delete' && op2.type === 'insert') {
    if (op2.position <= op1.position) {
      transformed.position += op2.value.length;
    }
  } else if (op1.type === 'delete' && op2.type === 'delete') {
    if (op2.position < op1.position) {
      transformed.position -= op2.value.length;
    }
  }
  
  return transformed;
}

function applyOperation(content, op) {
  if (op.type === 'insert') {
    return content.slice(0, op.position) + op.value + content.slice(op.position);
  } else if (op.type === 'delete') {
    return content.slice(0, op.position) + content.slice(op.position + op.value.length);
  }
  return content;
}

// WebSocket connection handler
wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`Client connected. Total: ${clients.size}`);
  
  // Send current state
  ws.send(JSON.stringify({
    type: 'init',
    content: otDocument.content,
    version: otDocument.version
  }));
  
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data);
      
      if (message.type === 'operation') {
        const op = message.operation;
        
        // Transform against any concurrent operations
        let transformedOp = op;
        for (let i = op.version; i < otDocument.version; i++) {
          transformedOp = transformOperation(transformedOp, otDocument.operations[i]);
        }
        
        // Apply to document
        otDocument.content = applyOperation(otDocument.content, transformedOp);
        otDocument.version++;
        
        // Store operation
        const storedOp = new OTOperation(
          transformedOp.type,
          transformedOp.position,
          transformedOp.value,
          otDocument.version - 1
        );
        otDocument.operations.push(storedOp);
        
        // Broadcast to all clients
        const broadcast = JSON.stringify({
          type: 'operation',
          operation: storedOp,
          content: otDocument.content,
          version: otDocument.version
        });
        
        clients.forEach(client => {
          if (client.readyState === 1) {
            client.send(broadcast);
          }
        });
      }
    } catch (err) {
      console.error('Error processing message:', err);
    }
  });
  
  ws.on('close', () => {
    clients.delete(ws);
    console.log(`Client disconnected. Total: ${clients.size}`);
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    clients: clients.size,
    version: otDocument.version,
    operations: otDocument.operations.length
  });
});

// Get document state
app.get('/document', (req, res) => {
  res.json(otDocument);
});

const PORT = 3001;
server.listen(PORT, () => {
  console.log(`OT Server running on port ${PORT}`);
});
