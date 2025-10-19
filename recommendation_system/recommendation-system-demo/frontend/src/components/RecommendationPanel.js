import React, { useState } from 'react';

const RecommendationPanel = ({ recommendations, loading, onInteraction }) => {
  const [interacting, setInteracting] = useState({});
  if (loading) {
    return (
      <div className="card">
        <h3>Recommendations</h3>
        <div className="loading">Loading recommendations...</div>
      </div>
    );
  }

  return (
    <div className="card">
      <h3>Personalized Recommendations</h3>
      {recommendations.length === 0 ? (
        <p>No recommendations available. Try interacting with some items first!</p>
      ) : (
        recommendations.map((rec, index) => (
          <div key={index} className="recommendation-item">
            <div className="recommendation-title">{rec.title}</div>
            <div style={{ 
              color: '#64748b', 
              marginBottom: '0.75rem',
              fontSize: '1rem',
              fontWeight: '500',
              textTransform: 'uppercase',
              letterSpacing: '0.5px'
            }}>
              📂 {rec.category}
            </div>
            <div className="recommendation-meta">
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <span className="score">Score: {rec.score}</span>
                <span className="algorithm-badge">{rec.algorithm}</span>
              </div>
              <div className="rating-buttons">
                <button 
                  className={`rating-btn ${interacting[`${rec.item_id}-4`] ? 'interacting' : ''}`}
                  onClick={async () => {
                    setInteracting(prev => ({ ...prev, [`${rec.item_id}-4`]: true }));
                    await onInteraction(rec.item_id, 4.0);
                    setTimeout(() => setInteracting(prev => ({ ...prev, [`${rec.item_id}-4`]: false })), 1000);
                  }}
                  disabled={interacting[`${rec.item_id}-4`]}
                >
                  {interacting[`${rec.item_id}-4`] ? '⏳ Processing...' : '👍 Like (4.0)'}
                </button>
                <button 
                  className={`rating-btn ${interacting[`${rec.item_id}-5`] ? 'interacting' : ''}`}
                  onClick={async () => {
                    setInteracting(prev => ({ ...prev, [`${rec.item_id}-5`]: true }));
                    await onInteraction(rec.item_id, 5.0);
                    setTimeout(() => setInteracting(prev => ({ ...prev, [`${rec.item_id}-5`]: false })), 1000);
                  }}
                  disabled={interacting[`${rec.item_id}-5`]}
                >
                  {interacting[`${rec.item_id}-5`] ? '⏳ Processing...' : '❤️ Love (5.0)'}
                </button>
              </div>
            </div>
          </div>
        ))
      )}
    </div>
  );
};

export default RecommendationPanel;
