import React, { useState, useEffect } from 'react';
import { 
  AlertCircle, 
  CheckCircle, 
  Clock, 
  TrendingUp,
  Users,
  Server
} from 'lucide-react';
import { apiService } from '../services/api';

export const Dashboard = () => {
  const [metrics, setMetrics] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadMetrics();
  }, []);

  const loadMetrics = async () => {
    try {
      const data = await apiService.getDashboardMetrics();
      setMetrics(data);
    } catch (error) {
      console.error('Failed to load metrics:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="dashboard loading">
        <div className="spinner"></div>
        <p>Loading dashboard...</p>
      </div>
    );
  }

  const totalIncidents = metrics?.totalIncidents?.[0]?.count || 0;
  const activeIncidents = metrics?.activeIncidents?.[0]?.count || 0;
  const avgResolutionTime = metrics?.avgResolutionTime?.[0]?.hours || 0;

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h1>System Reliability Dashboard</h1>
        <p>Monitor incidents, post-mortems, and system learning</p>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-header">
            <AlertCircle className="metric-icon danger" />
            <h3>Total Incidents</h3>
          </div>
          <div className="metric-value">{totalIncidents}</div>
          <div className="metric-trend">
            <TrendingUp size={16} />
            <span>All time</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-header">
            <Clock className="metric-icon warning" />
            <h3>Active Incidents</h3>
          </div>
          <div className="metric-value">{activeIncidents}</div>
          <div className="metric-trend">
            <span className={activeIncidents > 0 ? 'high' : 'low'}>
              {activeIncidents > 0 ? 'Needs attention' : 'All clear'}
            </span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-header">
            <CheckCircle className="metric-icon success" />
            <h3>Avg Resolution</h3>
          </div>
          <div className="metric-value">{avgResolutionTime.toFixed(1)}h</div>
          <div className="metric-trend">
            <span>Time to resolve</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="metric-header">
            <Users className="metric-icon info" />
            <h3>Team Response</h3>
          </div>
          <div className="metric-value">98%</div>
          <div className="metric-trend">
            <span>SLA compliance</span>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2>Recent Activity</h2>
        <div className="activity-feed">
          <div className="activity-item">
            <div className="activity-icon resolved">
              <CheckCircle size={16} />
            </div>
            <div className="activity-content">
              <p><strong>Database Connection Pool</strong> incident resolved</p>
              <span className="activity-time">2 hours ago</span>
            </div>
          </div>
          
          <div className="activity-item">
            <div className="activity-icon created">
              <FileText size={16} />
            </div>
            <div className="activity-content">
              <p>Post-mortem created for <strong>API Gateway Timeout</strong></p>
              <span className="activity-time">4 hours ago</span>
            </div>
          </div>
          
          <div className="activity-item">
            <div className="activity-icon investigating">
              <AlertCircle size={16} />
            </div>
            <div className="activity-content">
              <p>New incident: <strong>Payment Service Degradation</strong></p>
              <span className="activity-time">6 hours ago</span>
            </div>
          </div>
        </div>
      </div>

      <div className="dashboard-grid">
        <div className="dashboard-card">
          <h3>Learning Progress</h3>
          <div className="progress-ring">
            <div className="progress-value">85%</div>
          </div>
          <p>Action items completed this month</p>
        </div>

        <div className="dashboard-card">
          <h3>System Health</h3>
          <div className="health-indicators">
            <div className="health-item">
              <Server size={16} />
              <span>API Services</span>
              <div className="health-status healthy"></div>
            </div>
            <div className="health-item">
              <Server size={16} />
              <span>Databases</span>
              <div className="health-status healthy"></div>
            </div>
            <div className="health-item">
              <Server size={16} />
              <span>Message Queue</span>
              <div className="health-status warning"></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
