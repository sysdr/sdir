const express = require('express');
const cors = require('cors');
const sqlite3 = require('sqlite3').verbose();
const { v4: uuidv4 } = require('uuid');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Initialize SQLite Database
const db = new sqlite3.Database('./data/runbooks.db');

// Create tables
db.serialize(() => {
  // Runbooks table
  db.run(`
    CREATE TABLE IF NOT EXISTS runbooks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      category TEXT,
      severity TEXT,
      estimated_time INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      steps TEXT,
      prerequisites TEXT,
      rollback_steps TEXT
    )
  `);

  // Executions table
  db.run(`
    CREATE TABLE IF NOT EXISTS executions (
      id TEXT PRIMARY KEY,
      runbook_id TEXT,
      executed_by TEXT,
      status TEXT,
      started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      completed_at DATETIME,
      current_step INTEGER DEFAULT 0,
      execution_log TEXT,
      FOREIGN KEY(runbook_id) REFERENCES runbooks(id)
    )
  `);

  // Templates table
  db.run(`
    CREATE TABLE IF NOT EXISTS templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT,
      template_structure TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // Insert sample data
  const sampleRunbooks = [
    {
      id: uuidv4(),
      title: 'Database Connection Recovery',
      description: 'Steps to recover database connectivity issues',
      category: 'Database',
      severity: 'High',
      estimated_time: 15,
      steps: JSON.stringify([
        'Check database server status',
        'Verify network connectivity',
        'Review connection pool settings',
        'Restart connection pool',
        'Validate database accessibility'
      ]),
      prerequisites: 'Database admin access, VPN connection',
      rollback_steps: JSON.stringify(['Revert connection pool changes', 'Notify team'])
    },
    {
      id: uuidv4(),
      title: 'API Gateway Timeout Resolution',
      description: 'Resolve API gateway timeout issues',
      category: 'Infrastructure',
      severity: 'Medium',
      estimated_time: 10,
      steps: JSON.stringify([
        'Check API gateway metrics',
        'Review upstream service health',
        'Adjust timeout configurations',
        'Test API endpoints',
        'Monitor response times'
      ]),
      prerequisites: 'Infrastructure access, monitoring dashboard access',
      rollback_steps: JSON.stringify(['Revert timeout changes', 'Scale down if needed'])
    }
  ];

  const sampleTemplates = [
    {
      id: uuidv4(),
      name: 'Service Recovery Template',
      category: 'Infrastructure',
      template_structure: JSON.stringify({
        steps: [
          'Identify affected service',
          'Check service health metrics',
          'Review recent deployments',
          'Execute recovery procedure',
          'Validate service restoration'
        ],
        prerequisites: ['Service access', 'Monitoring access'],
        rollback_steps: ['Revert changes', 'Notify stakeholders']
      })
    }
  ];

  // Insert sample runbooks
  const insertRunbook = db.prepare(`
    INSERT INTO runbooks (id, title, description, category, severity, estimated_time, steps, prerequisites, rollback_steps)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  sampleRunbooks.forEach(runbook => {
    insertRunbook.run(runbook.id, runbook.title, runbook.description, 
                     runbook.category, runbook.severity, runbook.estimated_time,
                     runbook.steps, runbook.prerequisites, runbook.rollback_steps);
  });

  insertRunbook.finalize();

  // Insert sample templates
  const insertTemplate = db.prepare(`
    INSERT INTO templates (id, name, category, template_structure)
    VALUES (?, ?, ?, ?)
  `);

  sampleTemplates.forEach(template => {
    insertTemplate.run(template.id, template.name, template.category, template.template_structure);
  });

  insertTemplate.finalize();
});

// API Routes

// Get all runbooks
app.get('/api/runbooks', (req, res) => {
  db.all('SELECT * FROM runbooks ORDER BY created_at DESC', (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(rows.map(row => ({
      ...row,
      steps: JSON.parse(row.steps || '[]'),
      rollback_steps: JSON.parse(row.rollback_steps || '[]')
    })));
  });
});

// Get runbook by ID
app.get('/api/runbooks/:id', (req, res) => {
  db.get('SELECT * FROM runbooks WHERE id = ?', [req.params.id], (err, row) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    if (!row) {
      return res.status(404).json({ error: 'Runbook not found' });
    }
    res.json({
      ...row,
      steps: JSON.parse(row.steps || '[]'),
      rollback_steps: JSON.parse(row.rollback_steps || '[]')
    });
  });
});

// Create new runbook
app.post('/api/runbooks', (req, res) => {
  const { title, description, category, severity, estimated_time, steps, prerequisites, rollback_steps } = req.body;
  const id = uuidv4();
  
  db.run(`
    INSERT INTO runbooks (id, title, description, category, severity, estimated_time, steps, prerequisites, rollback_steps)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, [id, title, description, category, severity, estimated_time, 
      JSON.stringify(steps), prerequisites, JSON.stringify(rollback_steps)], 
  function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(201).json({ id, message: 'Runbook created successfully' });
  });
});

// Start execution
app.post('/api/executions', (req, res) => {
  const { runbook_id, executed_by } = req.body;
  const id = uuidv4();
  
  db.run(`
    INSERT INTO executions (id, runbook_id, executed_by, status)
    VALUES (?, ?, ?, ?)
  `, [id, runbook_id, executed_by, 'in_progress'], function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.status(201).json({ id, message: 'Execution started' });
  });
});

// Update execution status
app.put('/api/executions/:id', (req, res) => {
  const { status, current_step, execution_log } = req.body;
  const completed_at = status === 'completed' ? new Date().toISOString() : null;
  
  db.run(`
    UPDATE executions 
    SET status = ?, current_step = ?, execution_log = ?, completed_at = ?
    WHERE id = ?
  `, [status, current_step, execution_log, completed_at, req.params.id], function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json({ message: 'Execution updated successfully' });
  });
});

// Get executions for runbook
app.get('/api/runbooks/:id/executions', (req, res) => {
  db.all(`
    SELECT e.*, r.title as runbook_title 
    FROM executions e 
    JOIN runbooks r ON e.runbook_id = r.id 
    WHERE e.runbook_id = ? 
    ORDER BY e.started_at DESC
  `, [req.params.id], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(rows);
  });
});

// Get analytics data
app.get('/api/analytics', (req, res) => {
  const queries = {
    totalRunbooks: 'SELECT COUNT(*) as count FROM runbooks',
    totalExecutions: 'SELECT COUNT(*) as count FROM executions',
    executionsByStatus: 'SELECT status, COUNT(*) as count FROM executions GROUP BY status',
    runbooksByCategory: 'SELECT category, COUNT(*) as count FROM runbooks GROUP BY category'
  };

  let results = {};
  let completed = 0;

  Object.entries(queries).forEach(([key, query]) => {
    db.all(query, (err, rows) => {
      if (err) {
        console.error(`Error in ${key}:`, err);
        results[key] = [];
      } else {
        results[key] = rows;
      }
      
      completed++;
      if (completed === Object.keys(queries).length) {
        res.json(results);
      }
    });
  });
});

// Get templates
app.get('/api/templates', (req, res) => {
  db.all('SELECT * FROM templates ORDER BY created_at DESC', (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(rows.map(row => ({
      ...row,
      template_structure: JSON.parse(row.template_structure || '{}')
    })));
  });
});

app.listen(PORT, () => {
  console.log(`🔧 Runbook Management Backend running on port ${PORT}`);
});
