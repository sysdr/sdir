const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Database = require('../database');

const router = express.Router();
const db = new Database().getDatabase();

// Get all post-mortems
router.get('/', (req, res) => {
  const sql = `
    SELECT p.*, i.title as incident_title, i.severity 
    FROM postmortems p 
    JOIN incidents i ON p.incident_id = i.id 
    ORDER BY p.created_at DESC
  `;
  
  db.all(sql, [], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    res.json({ postmortems: rows });
  });
});

// Create new post-mortem
router.post('/', (req, res) => {
  const {
    incident_id,
    title,
    summary,
    timeline,
    root_cause,
    contributing_factors,
    lessons_learned,
    author
  } = req.body;

  const postmortem = {
    id: uuidv4(),
    incident_id,
    title,
    summary,
    timeline,
    root_cause,
    contributing_factors,
    lessons_learned,
    status: 'draft',
    author,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const sql = `
    INSERT INTO postmortems 
    (id, incident_id, title, summary, timeline, root_cause, contributing_factors, lessons_learned, status, author, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  db.run(sql, Object.values(postmortem), function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    res.status(201).json({ postmortem });
  });
});

// Approve post-mortem
router.patch('/:id/approve', (req, res) => {
  const { id } = req.params;
  const { approved_by } = req.body;
  
  const sql = `
    UPDATE postmortems 
    SET status = 'approved', approved_by = ?, approved_at = ?, updated_at = ?
    WHERE id = ?
  `;
  
  const now = new Date().toISOString();
  
  db.run(sql, ['approved', approved_by, now, now, id], function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    if (this.changes === 0) {
      return res.status(404).json({ error: 'Post-mortem not found' });
    }
    
    res.json({ message: 'Post-mortem approved successfully' });
  });
});

module.exports = router;
