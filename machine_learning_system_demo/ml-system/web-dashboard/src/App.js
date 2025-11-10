import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

const App = () => {
  const [stats, setStats] = useState({});
  const [models, setModels] = useState([]);
  const [jobs, setJobs] = useState([]);
  const [drift, setDrift] = useState({});
  const [inferenceStats, setInferenceStats] = useState({});
  const [predictionData, setPredictionData] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [statsRes, modelsRes, jobsRes, driftRes, inferenceRes] = await Promise.all([
          fetch('http://localhost:8001/stats'),
          fetch('http://localhost:8002/models'),
          fetch('http://localhost:8002/jobs'),
          fetch('http://localhost:8004/drift_detection'),
          fetch('http://localhost:8003/stats')
        ]);
        
        setStats(await statsRes.json());
        setModels(await modelsRes.json());
        setJobs(await jobsRes.json());
        setDrift(await driftRes.json());
        
        const inferenceStatsData = await inferenceRes.json();
        setInferenceStats(inferenceStatsData);
        
        // Always add data point, even if values are 0, to show real-time updates
        const newDataPoint = {
          time: new Date().toLocaleTimeString(),
          predictions: inferenceStatsData.predictions_last_hour || 0,
          latency: inferenceStatsData.avg_latency_ms || 0
        };
        
        setPredictionData(prev => {
          const updated = [...prev, newDataPoint];
          // Keep last 50 data points for better visualization
          return updated.slice(-50);
        });
        
      } catch (err) {
        console.error('Error fetching data:', err);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  const trainModel = async (modelType) => {
    try {
      await fetch(`http://localhost:8002/train?model_type=${modelType}`, { method: 'POST' });
      alert(`Training ${modelType} started!`);
    } catch (err) {
      alert('Error starting training');
    }
  };

  const makePrediction = async () => {
    const userId = `user_${Math.floor(Math.random() * 1000)}`;
    try {
      const res = await fetch('http://localhost:8003/predict', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ user_id: userId })
      });
      const data = await res.json();
      alert(`Prediction for ${userId}: ${(data.prediction * 100).toFixed(1)}% (${data.latency_ms.toFixed(1)}ms)`);
    } catch (err) {
      alert('Error making prediction');
    }
  };

  return (
    <div style={{ 
      padding: '24px', 
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
      background: '#F5F7FA',
      minHeight: '100vh'
    }}>
      <div style={{ maxWidth: '1400px', margin: '0 auto' }}>
        <div style={{ marginBottom: '32px' }}>
          <h1 style={{ 
            fontSize: '2rem', 
            marginBottom: '8px',
            color: '#1E293B',
            fontWeight: '700',
            letterSpacing: '-0.02em'
          }}>
            ML System Dashboard
          </h1>
          <p style={{
            color: '#64748B',
            fontSize: '0.95rem',
            margin: 0
          }}>
            Monitor and manage your machine learning infrastructure
          </p>
        </div>

        {/* System Overview */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', 
          gap: '20px',
          marginBottom: '30px'
        }}>
          <MetricCard 
            title="Feature Store" 
            value={stats.total_features || 0}
            subtitle="Features Computed"
            color="#3B82F6"
          />
          <MetricCard 
            title="Models" 
            value={models.length}
            subtitle="Total Models"
            color="#6366F1"
          />
          <MetricCard 
            title="Predictions" 
            value={inferenceStats.total_predictions || 0}
            subtitle="Total Served"
            color="#0EA5E9"
          />
          <MetricCard 
            title="Drift Score" 
            value={(drift.drift_score * 100 || 0).toFixed(1) + '%'}
            subtitle={drift.drift_detected ? '⚠️ Drift Detected' : '✅ Healthy'}
            color={drift.drift_detected ? '#EF4444' : '#10B981'}
          />
        </div>

        {/* Actions */}
        <div style={{ 
          background: 'white', 
          padding: '24px', 
          borderRadius: '8px',
          marginBottom: '24px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #E2E8F0'
        }}>
          <h2 style={{ marginBottom: '16px', color: '#1E293B', fontSize: '1.25rem', fontWeight: '600' }}>Actions</h2>
          <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
            <ActionButton onClick={() => trainModel('random_forest')}>
              🌲 Train Random Forest
            </ActionButton>
            <ActionButton onClick={() => trainModel('gradient_boosting')}>
              📈 Train Gradient Boosting
            </ActionButton>
            <ActionButton onClick={makePrediction}>
              🔮 Make Prediction
            </ActionButton>
          </div>
        </div>

        {/* Charts */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: '1fr 1fr', 
          gap: '20px',
          marginBottom: '30px'
        }}>
          <ChartCard title="Prediction Throughput">
            <ResponsiveContainer width="100%" height={250}>
              <LineChart data={predictionData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="predictions" stroke="#3B82F6" strokeWidth={2} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title="Latency Monitoring">
            <ResponsiveContainer width="100%" height={250}>
              <LineChart data={predictionData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="latency" stroke="#6366F1" strokeWidth={2} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </ChartCard>
        </div>

        {/* Models Table */}
        <div style={{ 
          background: 'white', 
          padding: '24px', 
          borderRadius: '8px',
          marginBottom: '24px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #E2E8F0'
        }}>
          <h2 style={{ marginBottom: '16px', color: '#1E293B', fontSize: '1.25rem', fontWeight: '600' }}>Model Registry</h2>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  <th style={tableHeaderStyle}>Model</th>
                  <th style={tableHeaderStyle}>Version</th>
                  <th style={tableHeaderStyle}>Accuracy</th>
                  <th style={tableHeaderStyle}>Samples</th>
                  <th style={tableHeaderStyle}>Status</th>
                </tr>
              </thead>
              <tbody>
                {models.map(model => (
                  <tr key={model.model_id} style={{ borderBottom: '1px solid #E2E8F0' }}>
                    <td style={tableCellStyle}>{model.model_name}</td>
                    <td style={tableCellStyle}>{model.version}</td>
                    <td style={tableCellStyle}>{(model.accuracy * 100).toFixed(1)}%</td>
                    <td style={tableCellStyle}>{model.training_samples}</td>
                    <td style={tableCellStyle}>
                      <span style={{
                        padding: '4px 12px',
                        borderRadius: '6px',
                        background: model.is_production ? '#D1FAE5' : '#F1F5F9',
                        color: model.is_production ? '#065F46' : '#475569',
                        fontSize: '0.8125rem',
                        fontWeight: '500'
                      }}>
                        {model.is_production ? 'Production' : 'Standby'}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Training Jobs */}
        <div style={{ 
          background: 'white', 
          padding: '24px', 
          borderRadius: '8px',
          boxShadow: '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)',
          border: '1px solid #E2E8F0'
        }}>
          <h2 style={{ marginBottom: '16px', color: '#1E293B', fontSize: '1.25rem', fontWeight: '600' }}>Recent Training Jobs</h2>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  <th style={tableHeaderStyle}>Job ID</th>
                  <th style={tableHeaderStyle}>Type</th>
                  <th style={tableHeaderStyle}>Status</th>
                  <th style={tableHeaderStyle}>Accuracy</th>
                  <th style={tableHeaderStyle}>Started</th>
                </tr>
              </thead>
              <tbody>
                {jobs.slice(0, 5).map(job => (
                  <tr key={job.job_id} style={{ borderBottom: '1px solid #E2E8F0' }}>
                    <td style={tableCellStyle}>#{job.job_id}</td>
                    <td style={tableCellStyle}>{job.model_type}</td>
                    <td style={tableCellStyle}>
                      <span style={{
                        padding: '4px 12px',
                        borderRadius: '6px',
                        background: job.status === 'completed' ? '#D1FAE5' : job.status === 'running' ? '#DBEAFE' : '#FEE2E2',
                        color: job.status === 'completed' ? '#065F46' : job.status === 'running' ? '#1E40AF' : '#991B1B',
                        fontSize: '0.8125rem',
                        fontWeight: '500',
                        textTransform: 'capitalize'
                      }}>
                        {job.status}
                      </span>
                    </td>
                    <td style={tableCellStyle}>
                      {job.accuracy ? `${(job.accuracy * 100).toFixed(1)}%` : '-'}
                    </td>
                    <td style={tableCellStyle}>
                      {new Date(job.started_at).toLocaleTimeString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};

const MetricCard = ({ title, value, subtitle, color }) => (
  <div style={{
    background: 'white',
    padding: '20px',
    borderRadius: '8px',
    boxShadow: '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)',
    border: '1px solid #E2E8F0',
    borderLeft: `4px solid ${color}`,
    transition: 'transform 0.2s, box-shadow 0.2s'
  }}
  onMouseEnter={(e) => {
    e.currentTarget.style.transform = 'translateY(-2px)';
    e.currentTarget.style.boxShadow = '0 4px 6px rgba(0,0,0,0.1), 0 2px 4px rgba(0,0,0,0.06)';
  }}
  onMouseLeave={(e) => {
    e.currentTarget.style.transform = 'translateY(0)';
    e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)';
  }}
  >
    <div style={{ fontSize: '0.8125rem', color: '#64748B', marginBottom: '8px', fontWeight: '500', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
      {title}
    </div>
    <div style={{ fontSize: '2rem', fontWeight: '700', color: '#1E293B', marginBottom: '4px', lineHeight: '1.2' }}>
      {value}
    </div>
    <div style={{ fontSize: '0.875rem', color: '#94A3B8' }}>
      {subtitle}
    </div>
  </div>
);

const ChartCard = ({ title, children }) => (
  <div style={{
    background: 'white',
    padding: '24px',
    borderRadius: '8px',
    boxShadow: '0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)',
    border: '1px solid #E2E8F0'
  }}>
    <h3 style={{ marginBottom: '20px', color: '#1E293B', fontSize: '1.125rem', fontWeight: '600' }}>{title}</h3>
    {children}
  </div>
);

const ActionButton = ({ onClick, children }) => (
  <button
    onClick={onClick}
    style={{
      padding: '10px 20px',
      background: '#3B82F6',
      color: 'white',
      border: 'none',
      borderRadius: '6px',
      cursor: 'pointer',
      fontSize: '0.875rem',
      fontWeight: '500',
      transition: 'all 0.2s',
      boxShadow: '0 1px 2px rgba(0,0,0,0.05)'
    }}
    onMouseOver={(e) => {
      e.target.style.background = '#2563EB';
      e.target.style.transform = 'translateY(-1px)';
      e.target.style.boxShadow = '0 4px 6px rgba(0,0,0,0.1)';
    }}
    onMouseOut={(e) => {
      e.target.style.background = '#3B82F6';
      e.target.style.transform = 'translateY(0)';
      e.target.style.boxShadow = '0 1px 2px rgba(0,0,0,0.05)';
    }}
  >
    {children}
  </button>
);

const tableHeaderStyle = {
  padding: '12px',
  textAlign: 'left',
  fontSize: '0.75rem',
  fontWeight: '600',
  color: '#64748B',
  textTransform: 'uppercase',
  letterSpacing: '0.05em',
  borderBottom: '1px solid #E2E8F0'
};

const tableCellStyle = {
  padding: '12px',
  fontSize: '0.875rem',
  color: '#1E293B'
};

export default App;
