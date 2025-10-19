import React, { useState, useEffect } from 'react';
import { getABTestingResults } from '../services/api';

const Dashboard = () => {
  const [abResults, setAbResults] = useState(null);

  useEffect(() => {
    const loadABResults = async () => {
      try {
        const data = await getABTestingResults();
        setAbResults(data);
      } catch (error) {
        console.error('Error loading A/B testing results:', error);
      }
    };

    loadABResults();
  }, []);

  if (!abResults) return <div className="card"><h3>A/B Testing</h3><p>Loading...</p></div>;

  return (
    <div className="card">
      <h3>A/B Testing Results</h3>
      <p><strong>Experiment:</strong> {abResults.experiment_name}</p>
      <p><strong>Winner:</strong> <span style={{
        background: 'linear-gradient(135deg, #10b981, #34d399)',
        color: 'white',
        padding: '0.5rem 1rem',
        borderRadius: '20px',
        textTransform: 'capitalize',
        fontWeight: '700',
        boxShadow: '0 4px 12px rgba(16, 185, 129, 0.3)',
        display: 'inline-block'
      }}>{abResults.winner}</span></p>
      <p><strong>Confidence:</strong> {(abResults.confidence * 100).toFixed(1)}%</p>
      
      <h4 style={{ marginTop: '2rem', marginBottom: '1rem' }}>Variant Performance</h4>
      {Object.entries(abResults.variants).map(([variant, metrics]) => (
        <div key={variant} style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '1.5rem',
          background: variant === abResults.winner 
            ? 'linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%)' 
            : 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
          marginBottom: '1rem',
          borderRadius: '16px',
          border: variant === abResults.winner ? '2px solid #10b981' : '1px solid #e2e8f0',
          boxShadow: variant === abResults.winner 
            ? '0 8px 25px rgba(16, 185, 129, 0.15)' 
            : '0 4px 12px rgba(0, 0, 0, 0.05)',
          transition: 'all 0.3s ease',
          position: 'relative',
          overflow: 'hidden'
        }}>
          <span style={{ 
            fontWeight: '700', 
            textTransform: 'capitalize',
            color: variant === abResults.winner ? '#065f46' : '#1e40af',
            fontSize: '1.1rem'
          }}>
            {variant.replace('_', ' ')}
            {variant === abResults.winner && ' 🏆'}
          </span>
          <div>
            <span style={{ marginRight: '1rem' }}>
              CTR: {(metrics.ctr * 100).toFixed(2)}%
            </span>
            <span>
              Engagement: {(metrics.engagement * 100).toFixed(1)}%
            </span>
          </div>
        </div>
      ))}
    </div>
  );
};

export default Dashboard;
