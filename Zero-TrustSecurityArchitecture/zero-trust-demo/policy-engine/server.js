const express = require('express');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Policy definitions
const policies = [
  {
    id: 'pol-001',
    name: 'Production Database Access',
    resource: '/api/database',
    conditions: {
      roles: ['admin', 'engineer'],
      departments: ['platform', 'security'],
      minDeviceScore: 90,
      timeWindow: { start: 6, end: 22 }
    }
  },
  {
    id: 'pol-002',
    name: 'User Data Access',
    resource: '/api/users',
    conditions: {
      roles: ['admin'],
      minDeviceScore: 95
    }
  },
  {
    id: 'pol-003',
    name: 'Public API',
    resource: '/api/public',
    conditions: {
      roles: ['engineer', 'admin'],
      minDeviceScore: 70
    }
  }
];

// Decision log
const decisionLog = [];

// Policy evaluation
function evaluatePolicy(claims, resource, context) {
  console.log(`[Policy] Evaluating access to ${resource} for ${claims.email}`);
  
  // Find matching policy
  const policy = policies.find(p => resource.startsWith(p.resource));
  if (!policy) {
    console.log(`[Policy] No policy found for ${resource}, defaulting to deny`);
    return { allowed: false, reason: 'No matching policy', policy: null };
  }
  
  // Check role
  if (policy.conditions.roles && !policy.conditions.roles.includes(claims.role)) {
    console.log(`[Policy] Role check failed: ${claims.role} not in ${policy.conditions.roles}`);
    return { allowed: false, reason: 'Insufficient role', policy: policy.id };
  }
  
  // Check department
  if (policy.conditions.departments && !policy.conditions.departments.includes(claims.department)) {
    console.log(`[Policy] Department check failed: ${claims.department}`);
    return { allowed: false, reason: 'Department not authorized', policy: policy.id };
  }
  
  // Check device security score
  if (policy.conditions.minDeviceScore && claims.devicePosture < policy.conditions.minDeviceScore) {
    console.log(`[Policy] Device score too low: ${claims.devicePosture} < ${policy.conditions.minDeviceScore}`);
    return { allowed: false, reason: 'Device security score insufficient', policy: policy.id };
  }
  
  // Check time window
  if (policy.conditions.timeWindow) {
    const hour = new Date().getHours();
    const { start, end } = policy.conditions.timeWindow;
    if (hour < start || hour >= end) {
      console.log(`[Policy] Outside allowed time window: ${hour}:00`);
      return { allowed: false, reason: 'Outside allowed time window', policy: policy.id };
    }
  }
  
  // Check location risk (mock implementation)
  if (context.location && context.location.risk === 'high') {
    console.log(`[Policy] High-risk location detected`);
    return { allowed: false, reason: 'High-risk location', policy: policy.id };
  }
  
  console.log(`[Policy] Access granted to ${resource} for ${claims.email}`);
  return { allowed: true, reason: 'All checks passed', policy: policy.id };
}

// Policy evaluation endpoint
app.post('/policy/evaluate', (req, res) => {
  const { claims, resource, context = {} } = req.body;
  
  const startTime = Date.now();
  const decision = evaluatePolicy(claims, resource, context);
  const latency = Date.now() - startTime;
  
  const logEntry = {
    timestamp: new Date(),
    userId: claims.userId,
    email: claims.email,
    resource,
    decision: decision.allowed ? 'ALLOW' : 'DENY',
    reason: decision.reason,
    policy: decision.policy,
    latency
  };
  
  decisionLog.push(logEntry);
  if (decisionLog.length > 1000) decisionLog.shift();
  
  res.json({ ...decision, latency });
});

// Get policies
app.get('/policy/list', (req, res) => {
  res.json({ policies });
});

// Get decision log
app.get('/policy/decisions', (req, res) => {
  const recent = decisionLog.slice(-50).reverse();
  const stats = {
    total: decisionLog.length,
    allowed: decisionLog.filter(d => d.decision === 'ALLOW').length,
    denied: decisionLog.filter(d => d.decision === 'DENY').length
  };
  res.json({ decisions: recent, stats });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'policy-engine', 
    status: 'healthy',
    policiesLoaded: policies.length
  });
});

const PORT = 3002;
app.listen(PORT, () => {
  console.log(`[Policy Engine] Running on port ${PORT}`);
});
