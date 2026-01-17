import * as Y from 'yjs';

// OT Connection
let otWs = null;
let otVersion = 0;
let otOperations = 0;
const otEditor = document.getElementById('ot-editor');

function connectOT() {
  otWs = new WebSocket('ws://localhost:3001');
  
  otWs.onopen = () => {
    console.log('OT connected');
    document.getElementById('ot-status').textContent = 'Connected';
  };
  
  otWs.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    if (data.type === 'init') {
      otEditor.value = data.content;
      otVersion = data.version;
      updateMetric('ot-version', otVersion);
    } else if (data.type === 'operation') {
      otEditor.value = data.content;
      otVersion = data.version;
      otOperations++;
      updateMetric('ot-version', otVersion);
      updateMetric('ot-ops', otOperations);
      
      logOperation('OT', `${data.operation.type} at pos ${data.operation.position}`, 'ot');
    }
  };
  
  otWs.onclose = () => {
    document.getElementById('ot-status').textContent = 'Disconnected';
    setTimeout(connectOT, 2000);
  };
}

// CRDT (Yjs) Setup
const ydoc = new Y.Doc();
const ytext = ydoc.getText('content');
const crdtEditor = document.getElementById('crdt-editor');
let crdtUpdates = 0;

// Initialize CRDT editor
ytext.insert(0, 'Start typing here...');
crdtEditor.value = ytext.toString();

ytext.observe(() => {
  crdtEditor.value = ytext.toString();
  crdtUpdates++;
  updateMetric('crdt-updates', crdtUpdates);
  
  const stateSize = (Y.encodeStateAsUpdate(ydoc).length / 1024).toFixed(2);
  updateMetric('crdt-size', stateSize);
  
  logOperation('CRDT', 'State synchronized', 'crdt');
});

// Manual edit handlers
let lastOTContent = otEditor.value;
let lastCRDTContent = crdtEditor.value;

otEditor.addEventListener('input', (e) => {
  const content = e.target.value;
  const oldContent = lastOTContent;
  
  if (content.length > oldContent.length) {
    // Insert
    const position = content.length - oldContent.length;
    const value = content.slice(oldContent.length);
    
    sendOTOperation('insert', position, value);
  } else if (content.length < oldContent.length) {
    // Delete
    const position = 0;
    const value = oldContent.slice(content.length);
    
    sendOTOperation('delete', position, value);
  }
  
  lastOTContent = content;
});

crdtEditor.addEventListener('input', (e) => {
  const content = e.target.value;
  const oldContent = lastCRDTContent;
  
  ydoc.transact(() => {
    if (content.length > oldContent.length) {
      const diff = content.length - oldContent.length;
      const insertPos = content.length - diff;
      const insertText = content.slice(insertPos, insertPos + diff);
      ytext.insert(insertPos, insertText);
    } else if (content.length < oldContent.length) {
      const diff = oldContent.length - content.length;
      ytext.delete(0, diff);
    }
  });
  
  lastCRDTContent = content;
});

function sendOTOperation(type, position, value) {
  if (otWs && otWs.readyState === WebSocket.OPEN) {
    const startTime = Date.now();
    otWs.send(JSON.stringify({
      type: 'operation',
      operation: { type, position, value, version: otVersion }
    }));
    
    const latency = Date.now() - startTime;
    updateMetric('ot-latency', latency);
  }
}

// Simulation functions
window.simulateInsert = (user, position) => {
  highlightUser(user);
  
  const words = ['Hello', 'World', '!', 'Test', '123'];
  const text = words[Math.floor(Math.random() * words.length)];
  
  // OT insert
  const otContent = otEditor.value;
  const otPos = position === -1 ? otContent.length : position;
  sendOTOperation('insert', otPos, text);
  
  // CRDT insert
  ydoc.transact(() => {
    const crdtPos = position === -1 ? ytext.length : position;
    ytext.insert(crdtPos, text);
  });
  
  logOperation(user, `Inserted "${text}" at position ${position}`, 'sim');
};

window.simulateDelete = (user, position, length) => {
  highlightUser(user);
  
  // OT delete
  const otContent = otEditor.value;
  const otDeleteText = otContent.slice(position, position + length);
  if (otDeleteText) {
    sendOTOperation('delete', position, otDeleteText);
  }
  
  // CRDT delete
  ydoc.transact(() => {
    if (position < ytext.length) {
      ytext.delete(position, Math.min(length, ytext.length - position));
    }
  });
  
  logOperation(user, `Deleted ${length} chars at position ${position}`, 'sim');
};

function highlightUser(user) {
  document.querySelectorAll('.user-card').forEach(card => {
    card.classList.remove('active');
  });
  
  const userMap = { 'Alice': 'user1', 'Bob': 'user2', 'Carol': 'user3' };
  const cardId = userMap[user];
  if (cardId) {
    document.getElementById(cardId).classList.add('active');
    setTimeout(() => {
      document.getElementById(cardId).classList.remove('active');
    }, 1000);
  }
}

function updateMetric(id, value) {
  const element = document.getElementById(id);
  if (element) {
    element.textContent = value;
  }
}

function logOperation(source, message, type) {
  const logs = document.getElementById('logs');
  const entry = document.createElement('div');
  entry.className = `log-entry log-${type}`;
  
  const timestamp = new Date().toLocaleTimeString();
  entry.innerHTML = `<span class="timestamp">[${timestamp}]</span> <strong>${source}:</strong> ${message}`;
  
  logs.insertBefore(entry, logs.firstChild);
  
  // Keep only last 20 logs
  while (logs.children.length > 20) {
    logs.removeChild(logs.lastChild);
  }
}

// Initialize connections
connectOT();
updateMetric('crdt-peers', 1);

// Simulate concurrent edits every 5 seconds
setInterval(() => {
  const users = ['Alice', 'Bob', 'Carol'];
  const user = users[Math.floor(Math.random() * users.length)];
  const actions = ['insert', 'delete'];
  const action = actions[Math.floor(Math.random() * actions.length)];
  
  if (action === 'insert') {
    simulateInsert(user, Math.floor(Math.random() * 10));
  } else {
    simulateDelete(user, Math.floor(Math.random() * 10), 3);
  }
}, 5000);
