const express = require('express')
const cors = require('cors')
const redis = require('redis')
const { v4: uuidv4 } = require('uuid')
const { addMinutes, subMinutes, format } = require('date-fns')

const app = express()
const port = 8080

// Redis client
const redisClient = redis.createClient({
  url: 'redis://redis:6379'
})

redisClient.on('error', (err) => {
  console.log('Redis Client Error', err)
})

redisClient.connect()

app.use(cors())
app.use(express.json())

// Simulated services
const services = [
  { name: 'User Service', baseLatency: 150, errorRate: 0.02 },
  { name: 'Payment Service', baseLatency: 300, errorRate: 0.01 },
  { name: 'Inventory Service', baseLatency: 100, errorRate: 0.03 },
  { name: 'Notification Service', baseLatency: 250, errorRate: 0.02 },
  { name: 'Analytics Service', baseLatency: 500, errorRate: 0.01 }
]

// Generate realistic metrics
function generateMetrics() {
  const now = new Date()
  
  services.forEach(service => {
    // Simulate varying load and performance
    const jitter = (Math.random() - 0.5) * 0.1
    const availability = Math.max(95, 99.5 + jitter)
    const latency = service.baseLatency * (1 + jitter)
    const errorRate = Math.max(0, service.errorRate + jitter * 0.01)
    
    const metrics = {
      timestamp: now.toISOString(),
      availability: availability,
      latency: latency,
      errorRate: errorRate * 100,
      uptime: availability,
      status: availability > 99 ? 'healthy' : availability > 97 ? 'warning' : 'critical'
    }
    
    // Store in Redis with expiration
    redisClient.setEx(`metrics:${service.name}`, 300, JSON.stringify(metrics))
  })
}

// Generate sample incidents
function generateIncidents() {
  const incidents = [
    {
      id: uuidv4(),
      title: 'Payment Service Latency Spike',
      severity: 'high',
      status: 'resolved',
      startTime: subMinutes(new Date(), 45).toISOString(),
      endTime: subMinutes(new Date(), 20).toISOString(),
      impact: 'Checkout flow experiencing 2x normal latency',
      services: ['Payment Service', 'User Service'],
      timeline: [
        {
          timestamp: subMinutes(new Date(), 45).toISOString(),
          action: 'Incident detected - latency alerts triggered',
          author: 'AlertManager'
        },
        {
          timestamp: subMinutes(new Date(), 40).toISOString(),
          action: 'Investigation started - checking database connections',
          author: 'SRE-OnCall'
        },
        {
          timestamp: subMinutes(new Date(), 25).toISOString(),
          action: 'Root cause identified - database connection pool exhaustion',
          author: 'SRE-OnCall'
        },
        {
          timestamp: subMinutes(new Date(), 20).toISOString(),
          action: 'Fix deployed - increased connection pool size',
          author: 'SRE-OnCall'
        }
      ]
    },
    {
      id: uuidv4(),
      title: 'User Service Error Rate Increase',
      severity: 'medium',
      status: 'investigating',
      startTime: subMinutes(new Date(), 15).toISOString(),
      impact: '5% of login requests failing',
      services: ['User Service'],
      timeline: [
        {
          timestamp: subMinutes(new Date(), 15).toISOString(),
          action: 'Alert triggered - error rate above threshold',
          author: 'AlertManager'
        },
        {
          timestamp: subMinutes(new Date(), 10).toISOString(),
          action: 'Investigating authentication service dependencies',
          author: 'SRE-OnCall'
        }
      ]
    }
  ]
  
  redisClient.setEx('incidents', 300, JSON.stringify(incidents))
}

// Generate alerts
function generateAlerts() {
  const alerts = [
    {
      id: uuidv4(),
      severity: 'warning',
      title: 'High Memory Usage',
      description: 'Analytics Service memory usage above 80%',
      service: 'Analytics Service',
      timestamp: subMinutes(new Date(), 5).toISOString(),
      status: 'active'
    },
    {
      id: uuidv4(),
      severity: 'info',
      title: 'Deployment Complete',
      description: 'User Service v2.1.3 deployed successfully',
      service: 'User Service',
      timestamp: subMinutes(new Date(), 30).toISOString(),
      status: 'active'
    }
  ]
  
  redisClient.setEx('alerts', 300, JSON.stringify(alerts))
}

// API Routes

// Dashboard stats
app.get('/api/dashboard/stats', async (req, res) => {
  const healthyServices = services.filter(service => Math.random() > 0.1).length
  
  res.json({
    totalServices: services.length,
    healthyServices: healthyServices,
    activeIncidents: Math.floor(Math.random() * 3),
    errorBudgetHealth: 85 + Math.random() * 10
  })
})

// SLO metrics
app.get('/api/slo/metrics', async (req, res) => {
  const now = new Date()
  const metrics = []
  
  for (let i = 11; i >= 0; i--) {
    const timestamp = subMinutes(now, i * 5)
    metrics.push({
      timestamp: timestamp.toISOString(),
      availability: 99.5 + Math.random() * 0.4,
      latency: 180 + Math.random() * 40,
      errorRate: Math.random() * 0.2
    })
  }
  
  res.json(metrics)
})

// Error budget data
app.get('/api/error-budget', async (req, res) => {
  const errorBudgets = services.map(service => ({
    service: service.name,
    budgetRemaining: 70 + Math.random() * 25,
    burnRate: 0.5 + Math.random() * 1.5,
    status: Math.random() > 0.8 ? 'warning' : Math.random() > 0.95 ? 'critical' : 'healthy'
  }))
  
  res.json(errorBudgets)
})

// Service health
app.get('/api/services/health', async (req, res) => {
  const serviceHealth = services.map(service => ({
    name: service.name,
    status: Math.random() > 0.85 ? 'warning' : Math.random() > 0.95 ? 'critical' : 'healthy',
    uptime: 98.5 + Math.random() * 1.4,
    latency: service.baseLatency + Math.random() * 50,
    errorRate: service.errorRate * 100 + Math.random() * 0.1,
    lastChecked: new Date().toISOString()
  }))
  
  res.json(serviceHealth)
})

// Alerts
app.get('/api/alerts', async (req, res) => {
  try {
    const alertsData = await redisClient.get('alerts')
    const alerts = alertsData ? JSON.parse(alertsData) : []
    res.json(alerts)
  } catch (error) {
    res.json([])
  }
})

// Incidents
app.get('/api/incidents', async (req, res) => {
  try {
    const incidentsData = await redisClient.get('incidents')
    const incidents = incidentsData ? JSON.parse(incidentsData) : []
    res.json(incidents)
  } catch (error) {
    res.json([])
  }
})

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() })
})

// Start server and generate data
app.listen(port, () => {
  console.log(`SRE Backend running on port ${port}`)
  
  // Generate initial data
  generateMetrics()
  generateIncidents()
  generateAlerts()
  
  // Update data periodically
  setInterval(generateMetrics, 10000)
  setInterval(generateIncidents, 30000)
  setInterval(generateAlerts, 20000)
})
