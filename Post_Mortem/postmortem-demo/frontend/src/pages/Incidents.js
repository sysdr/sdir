import React, { useState, useEffect } from 'react';
import { Plus, Search, Filter } from 'lucide-react';
import { apiService } from '../services/api';
import { IncidentModal } from '../components/IncidentModal';
import { formatDistance } from 'date-fns';

export const Incidents = () => {
  const [incidents, setIncidents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');

  useEffect(() => {
    loadIncidents();
  }, []);

  const loadIncidents = async () => {
    try {
      const response = await apiService.getIncidents();
      setIncidents(response.incidents);
    } catch (error) {
      console.error('Failed to load incidents:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleIncidentCreated = (newIncident) => {
    setIncidents(prev => [newIncident, ...prev]);
    setShowModal(false);
  };

  const filteredIncidents = incidents.filter(incident => {
    const matchesSearch = incident.title.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesStatus = statusFilter === 'all' || incident.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  const getSeverityColor = (severity) => {
    switch (severity) {
      case 'critical': return 'critical';
      case 'high': return 'high';
      case 'medium': return 'medium';
      case 'low': return 'low';
      default: return 'medium';
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'investigating': return 'investigating';
      case 'identified': return 'identified';
      case 'monitoring': return 'monitoring';
      case 'resolved': return 'resolved';
      default: return 'investigating';
    }
  };

  if (loading) {
    return (
      <div className="page-loading">
        <div className="spinner"></div>
        <p>Loading incidents...</p>
      </div>
    );
  }

  return (
    <div className="incidents-page">
      <div className="page-header">
        <div>
          <h1>Incidents</h1>
          <p>Track and manage system incidents</p>
        </div>
        <button 
          className="btn btn-primary"
          onClick={() => setShowModal(true)}
        >
          <Plus size={20} />
          New Incident
        </button>
      </div>

      <div className="page-controls">
        <div className="search-box">
          <Search size={20} />
          <input
            type="text"
            placeholder="Search incidents..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>

        <div className="filter-group">
          <Filter size={20} />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <option value="all">All Status</option>
            <option value="investigating">Investigating</option>
            <option value="identified">Identified</option>
            <option value="monitoring">Monitoring</option>
            <option value="resolved">Resolved</option>
          </select>
        </div>
      </div>

      <div className="incidents-grid">
        {filteredIncidents.map(incident => (
          <div key={incident.id} className="incident-card">
            <div className="incident-header">
              <div className="incident-id">{incident.id}</div>
              <div className={`severity-badge ${getSeverityColor(incident.severity)}`}>
                {incident.severity}
              </div>
            </div>
            
            <h3 className="incident-title">{incident.title}</h3>
            <p className="incident-description">{incident.description}</p>
            
            <div className="incident-meta">
              <div className="meta-item">
                <span className="meta-label">Status:</span>
                <span className={`status-badge ${getStatusColor(incident.status)}`}>
                  {incident.status}
                </span>
              </div>
              
              <div className="meta-item">
                <span className="meta-label">Reporter:</span>
                <span>{incident.reporter}</span>
              </div>
              
              <div className="meta-item">
                <span className="meta-label">Detected:</span>
                <span>{formatDistance(new Date(incident.detected_at), new Date(), { addSuffix: true })}</span>
              </div>
              
              {incident.resolved_at && (
                <div className="meta-item">
                  <span className="meta-label">Resolved:</span>
                  <span>{formatDistance(new Date(incident.resolved_at), new Date(), { addSuffix: true })}</span>
                </div>
              )}
            </div>

            <div className="incident-services">
              <span className="services-label">Affected Services:</span>
              <div className="services-list">
                {incident.affected_services?.map(service => (
                  <span key={service} className="service-tag">{service}</span>
                ))}
              </div>
            </div>
          </div>
        ))}
      </div>

      {showModal && (
        <IncidentModal
          onClose={() => setShowModal(false)}
          onIncidentCreated={handleIncidentCreated}
        />
      )}
    </div>
  );
};
