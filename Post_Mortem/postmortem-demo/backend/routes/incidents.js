const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Database = require('../database');

const router = express.Router();
const db = new Database().getDatabase();

// Get all incidents
router.get('/', (req, res) => {
  const sql = 'SELECT * FROM incidents ORDER BY created_at DESC';
  db.all(sql, [], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    const incidents = rows.map(row => ({
      ...row,
      affected_services: JSON.parse(row.affected_services || '[]')
    }));
    
    res.json({ incidents });
  });
});

// Create new incident
router.post('/', (req, res) => {
  const {
    title,
    description,
    severity,
    affected_services,
    reporter,
    customer_impact
  } = req.body;

  const incident = {
    id: `INC-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`,
    title,
    description,
    severity,
    status: 'investigating',
    detected_at: new Date().toISOString(),
    affected_services: JSON.stringify(affected_services || []),
    reporter,
    customer_impact,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const sql = `
    INSERT INTO incidents 
    (id, title, description, severity, status, detected_at, affected_services, reporter, customer_impact, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  db.run(sql, [
    incident.id, incident.title, incident.description, incident.severity,
    incident.status, incident.detected_at, incident.affected_services,
    incident.reporter, incident.customer_impact, incident.created_at, incident.updated_at
  ], function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    res.status(201).json({ 
      incident: {
        ...incident,
        affected_services: JSON.parse(incident.affected_services)
      }
    });
  });
});

// Update incident status
router.patch('/:id', (req, res) => {
  const { id } = req.params;
  const updates = req.body;
  
  const allowedUpdates = ['status', 'resolver', 'resolved_at'];
  const updateFields = [];
  const values = [];
  
  Object.keys(updates).forEach(key => {
    if (allowedUpdates.includes(key)) {
      updateFields.push(`${key} = ?`);
      values.push(updates[key]);
    }
  });
  
  if (updateFields.length === 0) {
    return res.status(400).json({ error: 'No valid fields to update' });
  }
  
  updateFields.push('updated_at = ?');
  values.push(new Date().toISOString());
  values.push(id);
  
  const sql = `UPDATE incidents SET ${updateFields.join(', ')} WHERE id = ?`;
  
  db.run(sql, values, function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    if (this.changes === 0) {
      return res.status(404).json({ error: 'Incident not found' });
    }
    
    res.json({ message: 'Incident updated successfully' });
  });
});

module.exports = router;
