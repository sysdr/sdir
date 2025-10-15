import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: `${API_BASE_URL}/api`,
  headers: {
    'Content-Type': 'application/json',
  },
});

export const apiService = {
  // Incidents
  getIncidents: () => api.get('/incidents').then(res => res.data),
  createIncident: (data) => api.post('/incidents', data).then(res => res.data),
  updateIncident: (id, data) => api.patch(`/incidents/${id}`, data).then(res => res.data),

  // Post-mortems
  getPostMortems: () => api.get('/postmortems').then(res => res.data),
  createPostMortem: (data) => api.post('/postmortems', data).then(res => res.data),
  approvePostMortem: (id, approver) => api.patch(`/postmortems/${id}/approve`, { approved_by: approver }).then(res => res.data),

  // Action items
  getActionItems: (postmortemId) => api.get(`/actions/${postmortemId}`).then(res => res.data),
  createActionItem: (data) => api.post('/actions', data).then(res => res.data),
  updateActionItem: (id, data) => api.patch(`/actions/${id}`, data).then(res => res.data),

  // Analytics
  getDashboardMetrics: () => api.get('/analytics/dashboard').then(res => res.data),
};
