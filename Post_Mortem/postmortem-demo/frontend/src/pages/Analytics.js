import React from 'react';
import { TrendingUp, BarChart, PieChart } from 'lucide-react';

export const Analytics = () => {
  return (
    <div className="analytics-page">
      <div className="page-header">
        <div>
          <h1>Analytics</h1>
          <p>Insights and trends from incident data</p>
        </div>
      </div>

      <div className="analytics-grid">
        <div className="analytics-card">
          <div className="card-header">
            <TrendingUp className="card-icon" />
            <h3>Incident Trends</h3>
          </div>
          <div className="chart-placeholder">
            <p>Monthly incident trends would be displayed here</p>
          </div>
        </div>

        <div className="analytics-card">
          <div className="card-header">
            <BarChart className="card-icon" />
            <h3>Resolution Times</h3>
          </div>
          <div className="chart-placeholder">
            <p>Average resolution time by severity</p>
          </div>
        </div>

        <div className="analytics-card">
          <div className="card-header">
            <PieChart className="card-icon" />
            <h3>Root Causes</h3>
          </div>
          <div className="chart-placeholder">
            <p>Distribution of root causes</p>
          </div>
        </div>
      </div>
    </div>
  );
};
