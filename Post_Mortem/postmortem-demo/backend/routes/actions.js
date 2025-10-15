const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Database = require('../database');

const router = express.Router();
const db = new Database().getDatabase();

// Get action items for a post-mortem
router.get('/:postmortem_id', (req, res) => {
  const { postmortem_id } = req.params;
  
  const sql = 'SELECT * FROM action_items WHERE postmortem_id = ? ORDER BY priority, created_at';
  
  db.all(sql, [postmortem_id], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    res.json({ action_items: rows });
  });
});

// Create action item
router.post('/', (req, res) => {
  const {
    postmortem_id,
    title,
    description,
    priority,
    assignee,
    due_date
  } = req.body;

  const actionItem = {
    id: uuidv4(),
    postmortem_id,
    title,
    description,
    priority,
    status: 'open',
    assignee,
    due_date,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };

  const sql = `
    INSERT INTO action_items 
    (id, postmortem_id, title, description, priority, status, assignee, due_date, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  db.run(sql, Object.values(actionItem), function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    res.status(201).json({ action_item: actionItem });
  });
});

// Update action item status
router.patch('/:id', (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  
  let completedAt = null;
  if (status === 'completed') {
    completedAt = new Date().toISOString();
  }
  
  const sql = `
    UPDATE action_items 
    SET status = ?, completed_at = ?, updated_at = ?
    WHERE id = ?
  `;
  
  db.run(sql, [status, completedAt, new Date().toISOString(), id], function(err) {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    
    if (this.changes === 0) {
      return res.status(404).json({ error: 'Action item not found' });
    }
    
    res.json({ message: 'Action item updated successfully' });
  });
});

module.exports = router;
