const express = require('express');
const Database = require('../database');

const router = express.Router();
const db = new Database().getDatabase();

// Get dashboard metrics
router.get('/dashboard', (req, res) => {
  const queries = {
    totalIncidents: 'SELECT COUNT(*) as count FROM incidents',
    activeIncidents: "SELECT COUNT(*) as count FROM incidents WHERE status != 'resolved'",
    avgResolutionTime: `
      SELECT AVG(
        (julianday(resolved_at) - julianday(detected_at)) * 24
      ) as hours 
      FROM incidents 
      WHERE resolved_at IS NOT NULL
    `,
    incidentsBySeverity: `
      SELECT severity, COUNT(*) as count 
      FROM incidents 
      GROUP BY severity
    `,
    incidentsByMonth: `
      SELECT 
        strftime('%Y-%m', created_at) as month,
        COUNT(*) as count
      FROM incidents
      GROUP BY strftime('%Y-%m', created_at)
      ORDER BY month DESC
      LIMIT 6
    `,
    topImpactedServices: `
      SELECT 
        json_extract(value, '$') as service,
        COUNT(*) as count
      FROM incidents, json_each(affected_services)
      GROUP BY service
      ORDER BY count DESC
      LIMIT 5
    `
  };

  const results = {};
  let completedQueries = 0;

  Object.keys(queries).forEach(key => {
    db.all(queries[key], [], (err, rows) => {
      if (!err) {
        results[key] = rows;
      }
      
      completedQueries++;
      if (completedQueries === Object.keys(queries).length) {
        res.json(results);
      }
    });
  });
});

module.exports = router;
