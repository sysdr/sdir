import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export const getUsers = async () => {
  const response = await api.get('/users');
  return response.data;
};

export const getItems = async () => {
  const response = await api.get('/items');
  return response.data;
};

export const getRecommendations = async (userId, algorithm = 'hybrid') => {
  const response = await api.get(`/recommendations/${userId}?algorithm=${algorithm}`);
  return response.data;
};

export const createInteraction = async (userId, itemId, interactionType = 'view', rating = null) => {
  const response = await api.post('/interactions', null, {
    params: {
      user_id: userId,
      item_id: itemId,
      interaction_type: interactionType,
      rating: rating
    }
  });
  return response.data;
};

export const getPerformanceMetrics = async () => {
  const response = await api.get('/analytics/performance');
  return response.data;
};

export const getABTestingResults = async () => {
  const response = await api.get('/analytics/ab-testing');
  return response.data;
};
