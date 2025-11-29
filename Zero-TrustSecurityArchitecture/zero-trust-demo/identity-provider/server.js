const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(express.json());
app.use(cors());

const JWT_SECRET = 'zero-trust-secret-key-2024';
const REFRESH_SECRET = 'zero-trust-refresh-key-2024';

// Mock user database with device fingerprints
const users = new Map([
  ['alice@company.com', {
    id: '1',
    email: 'alice@company.com',
    password: bcrypt.hashSync('password123', 10),
    role: 'engineer',
    department: 'platform',
    devices: new Set(['device-001'])
  }],
  ['bob@company.com', {
    id: '2',
    email: 'bob@company.com',
    password: bcrypt.hashSync('password456', 10),
    role: 'admin',
    department: 'security',
    devices: new Set(['device-002'])
  }]
]);

// Active sessions tracking
const activeSessions = new Map();

// Device posture checks
function checkDevicePosture(deviceId) {
  const devicePosture = {
    'device-001': { secure: true, osPatched: true, encryptionEnabled: true, score: 95 },
    'device-002': { secure: true, osPatched: true, encryptionEnabled: true, score: 98 },
    'device-003': { secure: false, osPatched: false, encryptionEnabled: true, score: 45 }
  };
  return devicePosture[deviceId] || { secure: false, osPatched: false, encryptionEnabled: false, score: 0 };
}

// Authentication endpoint
app.post('/auth/login', (req, res) => {
  const { email, password, deviceId, location } = req.body;
  
  console.log(`[Identity] Login attempt: ${email} from device ${deviceId}`);
  
  const user = users.get(email);
  if (!user || !bcrypt.compareSync(password, user.password)) {
    console.log(`[Identity] Authentication failed for ${email}`);
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  
  // Check device posture
  const devicePosture = checkDevicePosture(deviceId);
  if (!devicePosture.secure || devicePosture.score < 70) {
    console.log(`[Identity] Device posture check failed for ${deviceId}: score ${devicePosture.score}`);
    return res.status(403).json({ 
      error: 'Device security posture insufficient',
      posture: devicePosture
    });
  }
  
  // Generate session
  const sessionId = uuidv4();
  const accessToken = jwt.sign({
    userId: user.id,
    email: user.email,
    role: user.role,
    department: user.department,
    deviceId,
    sessionId,
    devicePosture: devicePosture.score
  }, JWT_SECRET, { expiresIn: '15m' });
  
  const refreshToken = jwt.sign({
    userId: user.id,
    sessionId
  }, REFRESH_SECRET, { expiresIn: '7d' });
  
  activeSessions.set(sessionId, {
    userId: user.id,
    email: user.email,
    deviceId,
    location,
    loginTime: new Date(),
    lastActivity: new Date()
  });
  
  console.log(`[Identity] Authentication successful for ${email}, session: ${sessionId}`);
  
  res.json({
    accessToken,
    refreshToken,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      department: user.department
    },
    devicePosture
  });
});

// Token validation endpoint
app.post('/auth/validate', (req, res) => {
  const { token } = req.body;
  
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const session = activeSessions.get(decoded.sessionId);
    
    if (!session) {
      return res.status(401).json({ valid: false, error: 'Session not found' });
    }
    
    // Update last activity
    session.lastActivity = new Date();
    
    console.log(`[Identity] Token validated for ${decoded.email}`);
    res.json({ valid: true, claims: decoded });
  } catch (error) {
    console.log(`[Identity] Token validation failed: ${error.message}`);
    res.status(401).json({ valid: false, error: error.message });
  }
});

// Session management
app.get('/auth/sessions', (req, res) => {
  const sessions = Array.from(activeSessions.entries()).map(([id, session]) => ({
    sessionId: id,
    ...session,
    age: Math.floor((Date.now() - session.loginTime) / 1000)
  }));
  res.json({ sessions, count: sessions.length });
});

app.delete('/auth/sessions/:sessionId', (req, res) => {
  const { sessionId } = req.params;
  if (activeSessions.delete(sessionId)) {
    console.log(`[Identity] Session ${sessionId} terminated`);
    res.json({ success: true });
  } else {
    res.status(404).json({ error: 'Session not found' });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'identity-provider', 
    status: 'healthy',
    activeSessions: activeSessions.size
  });
});

const PORT = 3001;
app.listen(PORT, () => {
  console.log(`[Identity Provider] Running on port ${PORT}`);
});
