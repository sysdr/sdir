import React, { useState } from 'react';
import { X, AlertTriangle } from 'lucide-react';
import { apiService } from '../services/api';

export const IncidentModal = ({ onClose, onIncidentCreated }) => {
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    severity: 'medium',
    affected_services: [],
    reporter: 'user@company.com',
    customer_impact: ''
  });
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      const response = await apiService.createIncident(formData);
      onIncidentCreated(response.incident);
    } catch (error) {
      console.error('Failed to create incident:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleServiceToggle = (service) => {
    setFormData(prev => ({
      ...prev,
      affected_services: prev.affected_services.includes(service)
        ? prev.affected_services.filter(s => s !== service)
        : [...prev.affected_services, service]
    }));
  };

  const commonServices = [
    'user-service', 'payment-service', 'inventory-service',
    'notification-service', 'api-gateway', 'database'
  ];

  return (
    <div className="modal-overlay">
      <div className="modal">
        <div className="modal-header">
          <div className="modal-title">
            <AlertTriangle className="modal-icon" />
            <h2>Create New Incident</h2>
          </div>
          <button className="modal-close" onClick={onClose}>
            <X size={24} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-group">
            <label>Incident Title *</label>
            <input
              type="text"
              required
              value={formData.title}
              onChange={(e) => setFormData(prev => ({ ...prev, title: e.target.value }))}
              placeholder="Brief description of the incident"
            />
          </div>

          <div className="form-group">
            <label>Description</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              placeholder="Detailed description of what happened"
              rows={3}
            />
          </div>

          <div className="form-row">
            <div className="form-group">
              <label>Severity *</label>
              <select
                value={formData.severity}
                onChange={(e) => setFormData(prev => ({ ...prev, severity: e.target.value }))}
              >
                <option value="low">Low</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
                <option value="critical">Critical</option>
              </select>
            </div>

            <div className="form-group">
              <label>Reporter</label>
              <input
                type="email"
                value={formData.reporter}
                onChange={(e) => setFormData(prev => ({ ...prev, reporter: e.target.value }))}
              />
            </div>
          </div>

          <div className="form-group">
            <label>Affected Services</label>
            <div className="service-tags">
              {commonServices.map(service => (
                <label key={service} className="service-tag">
                  <input
                    type="checkbox"
                    checked={formData.affected_services.includes(service)}
                    onChange={() => handleServiceToggle(service)}
                  />
                  <span>{service}</span>
                </label>
              ))}
            </div>
          </div>

          <div className="form-group">
            <label>Customer Impact</label>
            <textarea
              value={formData.customer_impact}
              onChange={(e) => setFormData(prev => ({ ...prev, customer_impact: e.target.value }))}
              placeholder="Describe the impact on customers"
              rows={2}
            />
          </div>

          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? 'Creating...' : 'Create Incident'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
