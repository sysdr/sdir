import React, { useState, useEffect } from 'react';
import { X, FileText } from 'lucide-react';
import { apiService } from '../services/api';

export const PostMortemModal = ({ onClose, onSuccess }) => {
  const [incidents, setIncidents] = useState([]);
  const [formData, setFormData] = useState({
    incident_id: '',
    title: '',
    summary: '',
    timeline: '',
    root_cause: '',
    contributing_factors: '',
    lessons_learned: '',
    author: 'user@company.com'
  });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadIncidents();
  }, []);

  const loadIncidents = async () => {
    try {
      const response = await apiService.getIncidents();
      setIncidents(response.incidents);
    } catch (error) {
      console.error('Failed to load incidents:', error);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      await apiService.createPostMortem(formData);
      onSuccess();
      onClose();
    } catch (error) {
      console.error('Failed to create post-mortem:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay">
      <div className="modal large">
        <div className="modal-header">
          <div className="modal-title">
            <FileText className="modal-icon" />
            <h2>Create Post-Mortem</h2>
          </div>
          <button className="modal-close" onClick={onClose}>
            <X size={24} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-group">
            <label>Related Incident *</label>
            <select
              required
              value={formData.incident_id}
              onChange={(e) => setFormData(prev => ({ ...prev, incident_id: e.target.value }))}
            >
              <option value="">Select an incident</option>
              {incidents.map(incident => (
                <option key={incident.id} value={incident.id}>
                  {incident.id}: {incident.title}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label>Post-Mortem Title *</label>
            <input
              type="text"
              required
              value={formData.title}
              onChange={(e) => setFormData(prev => ({ ...prev, title: e.target.value }))}
              placeholder="Post-mortem title"
            />
          </div>

          <div className="form-group">
            <label>Executive Summary</label>
            <textarea
              value={formData.summary}
              onChange={(e) => setFormData(prev => ({ ...prev, summary: e.target.value }))}
              placeholder="Brief summary of the incident and resolution"
              rows={3}
            />
          </div>

          <div className="form-group">
            <label>Timeline</label>
            <textarea
              value={formData.timeline}
              onChange={(e) => setFormData(prev => ({ ...prev, timeline: e.target.value }))}
              placeholder="Chronological timeline of events"
              rows={4}
            />
          </div>

          <div className="form-group">
            <label>Root Cause</label>
            <textarea
              value={formData.root_cause}
              onChange={(e) => setFormData(prev => ({ ...prev, root_cause: e.target.value }))}
              placeholder="Primary root cause of the incident"
              rows={3}
            />
          </div>

          <div className="form-group">
            <label>Contributing Factors</label>
            <textarea
              value={formData.contributing_factors}
              onChange={(e) => setFormData(prev => ({ ...prev, contributing_factors: e.target.value }))}
              placeholder="Additional factors that contributed to the incident"
              rows={3}
            />
          </div>

          <div className="form-group">
            <label>Lessons Learned</label>
            <textarea
              value={formData.lessons_learned}
              onChange={(e) => setFormData(prev => ({ ...prev, lessons_learned: e.target.value }))}
              placeholder="Key takeaways and learnings"
              rows={3}
            />
          </div>

          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? 'Creating...' : 'Create Post-Mortem'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
