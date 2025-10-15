import React, { useState, useEffect } from 'react';
import { FileText, Plus, Search, Eye } from 'lucide-react';
import { apiService } from '../services/api';
import { PostMortemModal } from '../components/PostMortemModal';
import { formatDistance } from 'date-fns';

export const PostMortems = () => {
  const [postmortems, setPostmortems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);

  useEffect(() => {
    loadPostMortems();
  }, []);

  const loadPostMortems = async () => {
    try {
      const response = await apiService.getPostMortems();
      setPostmortems(response.postmortems);
    } catch (error) {
      console.error('Failed to load post-mortems:', error);
    } finally {
      setLoading(false);
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'draft': return 'draft';
      case 'under-review': return 'review';
      case 'approved': return 'approved';
      default: return 'draft';
    }
  };

  if (loading) {
    return (
      <div className="page-loading">
        <div className="spinner"></div>
        <p>Loading post-mortems...</p>
      </div>
    );
  }

  return (
    <div className="postmortems-page">
      <div className="page-header">
        <div>
          <h1>Post-Mortems</h1>
          <p>Learn from incidents and improve system reliability</p>
        </div>
        <button 
          className="btn btn-primary"
          onClick={() => setShowModal(true)}
        >
          <Plus size={20} />
          New Post-Mortem
        </button>
      </div>

      <div className="postmortems-list">
        {postmortems.map(postmortem => (
          <div key={postmortem.id} className="postmortem-card">
            <div className="postmortem-header">
              <div className="postmortem-icon">
                <FileText size={24} />
              </div>
              <div className="postmortem-info">
                <h3>{postmortem.title}</h3>
                <p className="incident-title">
                  Related to: <strong>{postmortem.incident_title}</strong>
                </p>
              </div>
              <div className={`status-badge ${getStatusColor(postmortem.status)}`}>
                {postmortem.status}
              </div>
            </div>

            <div className="postmortem-summary">
              <p>{postmortem.summary || 'No summary available'}</p>
            </div>

            <div className="postmortem-meta">
              <div className="meta-group">
                <span className="meta-label">Author:</span>
                <span>{postmortem.author}</span>
              </div>
              
              <div className="meta-group">
                <span className="meta-label">Created:</span>
                <span>{formatDistance(new Date(postmortem.created_at), new Date(), { addSuffix: true })}</span>
              </div>

              {postmortem.approved_at && (
                <div className="meta-group">
                  <span className="meta-label">Approved:</span>
                  <span>{formatDistance(new Date(postmortem.approved_at), new Date(), { addSuffix: true })}</span>
                </div>
              )}
            </div>

            <div className="postmortem-actions">
              <button className="btn btn-secondary">
                <Eye size={16} />
                View Details
              </button>
            </div>
          </div>
        ))}
      </div>

      {postmortems.length === 0 && (
        <div className="empty-state">
          <FileText size={48} />
          <h3>No Post-Mortems Yet</h3>
          <p>Create your first post-mortem to start learning from incidents</p>
          <button 
            className="btn btn-primary"
            onClick={() => setShowModal(true)}
          >
            <Plus size={20} />
            Create Post-Mortem
          </button>
        </div>
      )}

      {showModal && (
        <PostMortemModal
          onClose={() => setShowModal(false)}
          onSuccess={loadPostMortems}
        />
      )}
    </div>
  );
};
