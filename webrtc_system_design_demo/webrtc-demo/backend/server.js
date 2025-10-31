const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());

// Store active rooms and users
const rooms = new Map();
const users = new Map();

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    activeRooms: rooms.size,
    activeUsers: users.size,
    timestamp: new Date().toISOString()
  });
});

// Get room statistics
app.get('/api/stats', (req, res) => {
  const roomStats = Array.from(rooms.entries()).map(([roomId, room]) => ({
    roomId,
    userCount: room.users.length,
    createdAt: room.createdAt
  }));

  res.json({
    totalRooms: rooms.size,
    totalUsers: users.size,
    rooms: roomStats
  });
});

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);
  
  // Store user info
  users.set(socket.id, {
    id: socket.id,
    connectedAt: new Date(),
    currentRoom: null
  });

  // Join room
  socket.on('join-room', (data) => {
    const { roomId, userName } = data;
    console.log(`${userName} (${socket.id}) joining room: ${roomId}`);
    
    // Leave previous room if any
    const user = users.get(socket.id);
    if (user && user.currentRoom) {
      socket.leave(user.currentRoom);
      removeUserFromRoom(user.currentRoom, socket.id);
    }
    
    // Join new room
    socket.join(roomId);
    user.currentRoom = roomId;
    user.userName = userName;
    
    // Create room if doesn't exist
    if (!rooms.has(roomId)) {
      rooms.set(roomId, {
        id: roomId,
        users: [],
        createdAt: new Date()
      });
    }
    
    const room = rooms.get(roomId);
    const userInfo = { id: socket.id, userName, joinedAt: new Date() };
    room.users.push(userInfo);
    
    // Notify existing users about new user
    socket.to(roomId).emit('user-joined', userInfo);
    
    // Send existing users to new user
    const existingUsers = room.users.filter(u => u.id !== socket.id);
    socket.emit('existing-users', existingUsers);
    
    console.log(`Room ${roomId} now has ${room.users.length} users`);
  });

  // WebRTC signaling
  socket.on('webrtc-offer', (data) => {
    console.log(`Offer from ${socket.id} to ${data.targetUserId}`);
    socket.to(data.targetUserId).emit('webrtc-offer', {
      offer: data.offer,
      fromUserId: socket.id,
      fromUserName: users.get(socket.id)?.userName
    });
  });

  socket.on('webrtc-answer', (data) => {
    console.log(`Answer from ${socket.id} to ${data.targetUserId}`);
    socket.to(data.targetUserId).emit('webrtc-answer', {
      answer: data.answer,
      fromUserId: socket.id
    });
  });

  socket.on('webrtc-ice-candidate', (data) => {
    socket.to(data.targetUserId).emit('webrtc-ice-candidate', {
      candidate: data.candidate,
      fromUserId: socket.id
    });
  });

  // Chat messages
  socket.on('chat-message', (data) => {
    const user = users.get(socket.id);
    if (user && user.currentRoom) {
      io.to(user.currentRoom).emit('chat-message', {
        message: data.message,
        userName: user.userName,
        userId: socket.id,
        timestamp: new Date()
      });
    }
  });

  // Handle disconnect
  socket.on('disconnect', () => {
    console.log(`User disconnected: ${socket.id}`);
    
    const user = users.get(socket.id);
    if (user && user.currentRoom) {
      removeUserFromRoom(user.currentRoom, socket.id);
      socket.to(user.currentRoom).emit('user-left', { userId: socket.id });
    }
    
    users.delete(socket.id);
  });
});

function removeUserFromRoom(roomId, userId) {
  const room = rooms.get(roomId);
  if (room) {
    room.users = room.users.filter(user => user.id !== userId);
    if (room.users.length === 0) {
      rooms.delete(roomId);
      console.log(`Room ${roomId} deleted (empty)`);
    }
  }
}

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`🚀 WebRTC Signaling Server running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`📈 Stats endpoint: http://localhost:${PORT}/api/stats`);
});
