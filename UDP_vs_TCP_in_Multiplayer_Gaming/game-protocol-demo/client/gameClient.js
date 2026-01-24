const dgram = require('dgram');
const net = require('net');

class GameClient {
  constructor(protocol, clientId, packetLossRate = 0) {
    this.protocol = protocol;
    this.clientId = clientId;
    this.packetLossRate = packetLossRate;
    this.x = 0;
    this.y = 0;
    this.vx = 0;
    this.vy = 0;
    this.latency = 0;
    this.packetsReceived = 0;
    this.packetsLost = 0;
    this.lastSequence = -1;

    if (protocol === 'UDP') {
      this.setupUDP();
    } else {
      this.setupTCP();
    }
  }

  setupUDP() {
    this.socket = dgram.createSocket('udp4');

    this.socket.on('message', (msg) => {
      // Simulate packet loss
      if (Math.random() < this.packetLossRate) {
        this.packetsLost++;
        return;
      }

      try {
        const state = JSON.parse(msg.toString());
        this.handleStateUpdate(state);
        this.packetsReceived++;
      } catch (err) {
        console.error(`UDP ${this.clientId} parse error:`, err.message);
      }
    });

    this.socket.bind(() => {
      const joinMsg = JSON.stringify({ type: 'join', clientId: this.clientId });
      const serverHost = process.env.GAME_SERVER_HOST || 'localhost';
      this.socket.send(joinMsg, 9001, serverHost);
      console.log(`🎮 UDP Client ${this.clientId} joined (${this.packetLossRate * 100}% loss)`);
    });

    // Send inputs
    this.inputInterval = setInterval(() => {
      this.updateInput();
      const inputMsg = JSON.stringify({
        type: 'input',
        vx: this.vx,
        vy: this.vy,
        clientId: this.clientId
      });
      const serverHost = process.env.GAME_SERVER_HOST || 'localhost';
      this.socket.send(inputMsg, 9001, serverHost);
    }, 50);
  }

  setupTCP() {
    const serverHost = process.env.GAME_SERVER_HOST || 'localhost';
    this.socket = net.createConnection({ port: 9002, host: serverHost });
    this.buffer = '';

    this.socket.on('connect', () => {
      console.log(`🎮 TCP Client ${this.clientId} connected (${this.packetLossRate * 100}% loss)`);
    });

    this.socket.on('data', (data) => {
      // Simulate packet loss (artificially drop data)
      if (Math.random() < this.packetLossRate) {
        this.packetsLost++;
        return;
      }

      this.buffer += data.toString();
      
      let newlineIndex;
      while ((newlineIndex = this.buffer.indexOf('\n')) !== -1) {
        const message = this.buffer.slice(0, newlineIndex);
        this.buffer = this.buffer.slice(newlineIndex + 1);

        try {
          const state = JSON.parse(message);
          this.handleStateUpdate(state);
          this.packetsReceived++;
        } catch (err) {
          console.error(`TCP ${this.clientId} parse error:`, err.message);
        }
      }
    });

    this.socket.on('close', () => {
      clearInterval(this.inputInterval);
      console.log(`❌ TCP Client ${this.clientId} disconnected`);
    });

    // Send inputs
    this.inputInterval = setInterval(() => {
      this.updateInput();
      const inputMsg = JSON.stringify({
        type: 'input',
        vx: this.vx,
        vy: this.vy,
        clientId: this.clientId
      });
      this.socket.write(inputMsg + '\n');
    }, 50);
  }

  updateInput() {
    // Random movement pattern
    if (Math.random() < 0.1) {
      this.vx = (Math.random() - 0.5) * 10;
      this.vy = (Math.random() - 0.5) * 10;
    }
  }

  handleStateUpdate(state) {
    const myPlayer = state.players.find(p => p.id.includes(this.clientId));
    if (myPlayer) {
      // Detect packet loss via sequence numbers
      if (this.lastSequence !== -1 && myPlayer.seq > this.lastSequence + 1) {
        this.packetsLost += (myPlayer.seq - this.lastSequence - 1);
      }
      this.lastSequence = myPlayer.seq;

      this.x = myPlayer.x;
      this.y = myPlayer.y;
    }
  }

  getStats() {
    return {
      clientId: this.clientId,
      protocol: this.protocol,
      packetsReceived: this.packetsReceived,
      packetsLost: this.packetsLost,
      lossRate: this.packetsReceived > 0 
        ? (this.packetsLost / (this.packetsReceived + this.packetsLost) * 100).toFixed(1)
        : 0
    };
  }

  disconnect() {
    clearInterval(this.inputInterval);
    if (this.socket) {
      if (this.protocol === 'UDP') {
        this.socket.close();
      } else {
        this.socket.end();
      }
    }
  }
}

// Create clients with different packet loss rates
const clients = [
  new GameClient('UDP', 'udp-1', 0.05),
  new GameClient('UDP', 'udp-2', 0.15),
  new GameClient('TCP', 'tcp-1', 0.05),
  new GameClient('TCP', 'tcp-2', 0.15)
];

// Report stats every 5 seconds
setInterval(() => {
  console.log('\n📊 Client Statistics:');
  clients.forEach(client => {
    const stats = client.getStats();
    console.log(`  ${stats.protocol} ${stats.clientId}: ` +
                `${stats.packetsReceived} received, ` +
                `${stats.packetsLost} lost (${stats.lossRate}%)`);
  });
}, 5000);

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down clients...');
  clients.forEach(client => client.disconnect());
  process.exit(0);
});
