import React, { useState, useEffect } from 'react';
import './App.css';
import Dashboard from './components/Dashboard';
import UserSelector from './components/UserSelector';
import RecommendationPanel from './components/RecommendationPanel';
import PerformanceMetrics from './components/PerformanceMetrics';
import { getUsers, getRecommendations, createInteraction } from './services/api';

function App() {
  const [users, setUsers] = useState([]);
  const [selectedUser, setSelectedUser] = useState(null);
  const [recommendations, setRecommendations] = useState([]);
  const [algorithm, setAlgorithm] = useState('hybrid');
  const [loading, setLoading] = useState(false);
  const [interactionMessage, setInteractionMessage] = useState('');

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    try {
      const data = await getUsers();
      setUsers(data);
      if (data.length > 0) {
        setSelectedUser(data[0]);
      }
    } catch (error) {
      console.error('Error loading users:', error);
    }
  };

  const loadRecommendations = async () => {
    if (!selectedUser) return;
    
    setLoading(true);
    try {
      const data = await getRecommendations(selectedUser.id, algorithm);
      setRecommendations(data);
    } catch (error) {
      console.error('Error loading recommendations:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleInteraction = async (itemId, rating) => {
    if (!selectedUser) return;
    
    try {
      console.log(`Creating interaction: user=${selectedUser.id}, item=${itemId}, rating=${rating}`);
      await createInteraction(selectedUser.id, itemId, 'view', rating);
      console.log('Interaction created successfully, reloading recommendations...');
      
      // Show success message
      setInteractionMessage(`✅ Rating ${rating} recorded! Updating recommendations...`);
      setTimeout(() => setInteractionMessage(''), 3000);
      
      // Reload recommendations after interaction
      setTimeout(() => loadRecommendations(), 500);
    } catch (error) {
      console.error('Error creating interaction:', error);
      setInteractionMessage('❌ Error recording interaction. Please try again.');
      setTimeout(() => setInteractionMessage(''), 3000);
    }
  };

  useEffect(() => {
    loadRecommendations();
  }, [selectedUser, algorithm]);

  return (
    <div className="App">
      <header className="app-header">
        <h1>🎯 Recommendation System at Scale</h1>
        <p>Real-time hybrid recommendation engine with collaborative and content-based filtering</p>
      </header>
      
      <div className="app-content">
        <div className="control-panel">
          <UserSelector 
            users={users}
            selectedUser={selectedUser}
            onUserSelect={setSelectedUser}
          />
          
          <div className="algorithm-selector">
            <label>Algorithm:</label>
            <select value={algorithm} onChange={(e) => setAlgorithm(e.target.value)}>
              <option value="hybrid">Hybrid</option>
              <option value="collaborative">Collaborative Filtering</option>
              <option value="content_based">Content-Based</option>
            </select>
          </div>
        </div>
        
        {interactionMessage && (
          <div style={{
            background: 'linear-gradient(135deg, #10b981, #34d399)',
            color: 'white',
            padding: '1rem 2rem',
            borderRadius: '12px',
            marginBottom: '2rem',
            textAlign: 'center',
            fontWeight: '600',
            boxShadow: '0 4px 12px rgba(16, 185, 129, 0.3)',
            animation: 'slideDown 0.3s ease-out'
          }}>
            {interactionMessage}
          </div>
        )}
        
        <div className="main-content">
          <RecommendationPanel 
            recommendations={recommendations}
            loading={loading}
            onInteraction={handleInteraction}
          />
          
          <div className="metrics-section">
            <PerformanceMetrics />
            <Dashboard />
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
