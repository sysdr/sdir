const express = require('express');
const cors = require('cors');
const http = require('http');
const socketIo = require('socket.io');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const Database = require('./database');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "http://localhost:3000",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 8000;

// Middleware
app.use(helmet());
app.use(compression());
app.use(morgan('combined'));
app.use(cors({
  origin: 'http://localhost:3000',
  credentials: true
}));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Initialize database
const db = new Database();

// Routes
const incidentsRouter = require('./routes/incidents');
const postmortemsRouter = require('./routes/postmortems');
const actionsRouter = require('./routes/actions');
const analyticsRouter = require('./routes/analytics');

app.use('/api/incidents', incidentsRouter);
app.use('/api/postmortems', postmortemsRouter);
app.use('/api/actions', actionsRouter);
app.use('/api/analytics', analyticsRouter);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Socket.io connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  
  socket.on('join-incident', (incidentId) => {
    socket.join(`incident-${incidentId}`);
  });
  
  socket.on('incident-update', (data) => {
    socket.to(`incident-${data.incidentId}`).emit('incident-updated', data);
  });
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: 'Internal Server Error',
    message: err.message || 'Something went wrong'
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Process terminated');
  });
});

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/api/health`);
});

module.exports = app;
