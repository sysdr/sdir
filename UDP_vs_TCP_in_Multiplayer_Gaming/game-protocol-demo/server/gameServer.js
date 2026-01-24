const dgram = require('dgram');
const net = require('net');
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const TICK_RATE = 30; // 30 updates per second
const TICK_INTERVAL = 1000 / TICK_RATE;

class GameServer {
  constructor() {
    this.players = new Map();
    this.udpSocket = dgram.createSocket('udp4');
    this.tcpServer = net.createServer();
    this.tickNumber = 0;
    this.metrics = {
      udpPacketsSent: 0,
      tcpPacketsSent: 0,
      udpPacketsReceived: 0,
      tcpPacketsReceived: 0,
      activeConnections: 0
    };

    // Express server for metrics and WebSocket
    this.app = express();
    this.httpServer = http.createServer(this.app);
    this.io = new Server(this.httpServer, {
      cors: { origin: '*' }
    });

    this.setupRoutes();
    this.setupWebSocket();
  }

  setupRoutes() {
    // Enable CORS for all routes
    this.app.use((req, res, next) => {
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      res.header('Access-Control-Allow-Headers', 'Content-Type');
      if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
      }
      next();
    });

    this.app.get('/metrics', (req, res) => {
      res.json({
        metrics: this.metrics,
        tickNumber: this.tickNumber,
        playerCount: this.players.size,
        players: Array.from(this.players.entries()).map(([id, p]) => ({
          id,
          protocol: p.protocol,
          x: p.x,
          y: p.y,
          latency: p.latency || 0,
          packetsLost: p.packetsLost || 0
        }))
      });
    });
  }

  setupWebSocket() {
    this.io.on('connection', (socket) => {
      console.log('📊 Dashboard connected');
      socket.on('disconnect', () => {
        console.log('📊 Dashboard disconnected');
      });
    });
  }

  start() {
    // UDP Server
    this.udpSocket.on('message', (msg, rinfo) => {
      this.handleUDPMessage(msg, rinfo);
    });

    this.udpSocket.bind(9001, () => {
      console.log('🎯 UDP Game Server listening on port 9001');
    });

    // TCP Server
    this.tcpServer.on('connection', (socket) => {
      this.handleTCPConnection(socket);
    });

    this.tcpServer.listen(9002, () => {
      console.log('🎯 TCP Game Server listening on port 9002');
    });

    // HTTP Server
    this.httpServer.listen(3000, () => {
      console.log('📊 Metrics server listening on port 3000');
    });

    // Game loop
    setInterval(() => this.tick(), TICK_INTERVAL);

    // Metrics broadcast
    setInterval(() => this.broadcastMetrics(), 100);
  }

  handleUDPMessage(msg, rinfo) {
    try {
      const data = JSON.parse(msg.toString());
      this.metrics.udpPacketsReceived++;

      const playerId = `${rinfo.address}:${rinfo.port}`;
      
      if (data.type === 'join') {
        this.players.set(playerId, {
          id: playerId,
          protocol: 'UDP',
          x: Math.random() * 800,
          y: Math.random() * 600,
          vx: 0,
          vy: 0,
          address: rinfo.address,
          port: rinfo.port,
          lastUpdate: Date.now(),
          sequenceNumber: 0
        });
        this.metrics.activeConnections++;
        console.log(`✅ UDP Player joined: ${playerId}`);
      } else if (data.type === 'input') {
        const player = this.players.get(playerId);
        if (player) {
          player.vx = data.vx;
          player.vy = data.vy;
          player.lastUpdate = Date.now();
        }
      }
    } catch (err) {
      console.error('UDP message error:', err.message);
    }
  }

  handleTCPConnection(socket) {
    const playerId = `${socket.remoteAddress}:${socket.remotePort}`;
    
    this.players.set(playerId, {
      id: playerId,
      protocol: 'TCP',
      x: Math.random() * 800,
      y: Math.random() * 600,
      vx: 0,
      vy: 0,
      socket: socket,
      lastUpdate: Date.now(),
      buffer: '',
      sequenceNumber: 0
    });

    this.metrics.activeConnections++;
    console.log(`✅ TCP Player connected: ${playerId}`);

    socket.on('data', (data) => {
      const player = this.players.get(playerId);
      if (!player) return;

      player.buffer += data.toString();
      
      let newlineIndex;
      while ((newlineIndex = player.buffer.indexOf('\n')) !== -1) {
        const message = player.buffer.slice(0, newlineIndex);
        player.buffer = player.buffer.slice(newlineIndex + 1);

        try {
          const parsed = JSON.parse(message);
          this.metrics.tcpPacketsReceived++;

          if (parsed.type === 'input') {
            player.vx = parsed.vx;
            player.vy = parsed.vy;
            player.lastUpdate = Date.now();
          }
        } catch (err) {
          console.error('TCP parse error:', err.message);
        }
      }
    });

    socket.on('close', () => {
      this.players.delete(playerId);
      this.metrics.activeConnections--;
      console.log(`❌ TCP Player disconnected: ${playerId}`);
    });

    socket.on('error', (err) => {
      console.error(`TCP socket error for ${playerId}:`, err.message);
    });
  }

  tick() {
    this.tickNumber++;

    // Update physics
    this.players.forEach((player) => {
      player.x += player.vx;
      player.y += player.vy;

      // Boundary checking
      player.x = Math.max(0, Math.min(800, player.x));
      player.y = Math.max(0, Math.min(600, player.y));

      player.sequenceNumber++;
    });

    // Broadcast state
    this.broadcastState();
  }

  broadcastState() {
    const state = {
      tick: this.tickNumber,
      timestamp: Date.now(),
      players: []
    };

    this.players.forEach((player) => {
      state.players.push({
        id: player.id,
        x: Math.round(player.x),
        y: Math.round(player.y),
        protocol: player.protocol,
        seq: player.sequenceNumber
      });
    });

    const stateJson = JSON.stringify(state);

    // Send to UDP clients
    this.players.forEach((player) => {
      if (player.protocol === 'UDP') {
        this.udpSocket.send(
          stateJson,
          player.port,
          player.address.replace('::ffff:', ''),
          (err) => {
            if (!err) this.metrics.udpPacketsSent++;
          }
        );
      } else if (player.protocol === 'TCP' && player.socket) {
        try {
          player.socket.write(stateJson + '\n');
          this.metrics.tcpPacketsSent++;
        } catch (err) {
          console.error('TCP write error:', err.message);
        }
      }
    });
  }

  broadcastMetrics() {
    this.io.emit('metrics', {
      metrics: this.metrics,
      tickNumber: this.tickNumber,
      playerCount: this.players.size
    });
  }
}

const server = new GameServer();
server.start();
