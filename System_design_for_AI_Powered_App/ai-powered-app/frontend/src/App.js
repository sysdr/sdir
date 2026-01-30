import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import './App.css';

const BACKEND_URL = 'http://localhost:5000';
const WS_URL = 'ws://localhost:5000';

function App() {
  const [text1, setText1] = useState('');
  const [text2, setText2] = useState('');
  const [model, setModel] = useState('auto');
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [metrics, setMetrics] = useState({
    totalRequests: 0,
    cacheHits: 0,
    fastModelCalls: 0,
    heavyModelCalls: 0,
    avgLatency: 0,
    cacheHitRate: 0,
    totalCost: 0,
    costPerRequest: 0
  });
  const [history, setHistory] = useState([]);
  const [latencyData, setLatencyData] = useState([]);

  const fetchHistory = async () => {
    try {
      const response = await fetch(`${BACKEND_URL}/api/history`);
      const data = await response.json();
      setHistory(data.slice(0, 20));
      
      const chartData = data.slice(0, 10).reverse().map((item, idx) => ({
        name: `Req ${idx + 1}`,
        latency: item.latency_ms,
        cached: item.cached ? item.latency_ms : 0
      }));
      setLatencyData(chartData);
    } catch (error) {
      console.error('Error fetching history:', error);
    }
  };

  useEffect(() => {
    const ws = new WebSocket(WS_URL);
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'metrics') {
        setMetrics(data.data);
        // Refresh history & chart when metrics update (new request made)
        fetchHistory();
      }
    };
    return () => ws.close();
  }, []);

  useEffect(() => {
    fetchHistory();
  }, []);

  const handleSimilarity = async () => {
    if (!text1 || !text2) return;
    
    setLoading(true);
    try {
      const response = await fetch(`${BACKEND_URL}/api/similarity`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text1,
          text2,
          model: model === 'auto' ? null : model
        })
      });
      const data = await response.json();
      setResult(data);
      fetchHistory();
    } catch (error) {
      console.error('Error:', error);
    }
    setLoading(false);
  };

  const pieData = [
    { name: 'Cache Hits', value: metrics.cacheHits },
    { name: 'Fast Model', value: metrics.fastModelCalls },
    { name: 'Heavy Model', value: metrics.heavyModelCalls }
  ];

  const COLORS = ['#10b981', '#3b82f6', '#8b5cf6'];

  return (
    <div className="app">
      <header className="header">
        <h1>🤖 AI-Powered Application</h1>
        <p>Real-time Model Serving with Intelligent Caching</p>
      </header>

      <div className="container">
        <div className="metrics-grid">
          <div className="metric-card primary">
            <div className="metric-value">{metrics.totalRequests}</div>
            <div className="metric-label">Total Requests</div>
          </div>
          <div className="metric-card success">
            <div className="metric-value">{metrics.cacheHitRate}%</div>
            <div className="metric-label">Cache Hit Rate</div>
          </div>
          <div className="metric-card info">
            <div className="metric-value">{metrics.avgLatency.toFixed(0)}ms</div>
            <div className="metric-label">Avg Latency</div>
          </div>
          <div className="metric-card warning">
            <div className="metric-value">${(metrics.totalCost || 0).toFixed(4)}</div>
            <div className="metric-label">Total Cost</div>
          </div>
        </div>

        <div className="main-content">
          <div className="query-section">
            <h2>Semantic Similarity Tester</h2>
            <div className="input-group">
              <label>Text 1:</label>
              <textarea
                value={text1}
                onChange={(e) => setText1(e.target.value)}
                placeholder="Enter first text..."
                rows="3"
              />
            </div>
            <div className="input-group">
              <label>Text 2:</label>
              <textarea
                value={text2}
                onChange={(e) => setText2(e.target.value)}
                placeholder="Enter second text..."
                rows="3"
              />
            </div>
            <div className="input-group">
              <label>Model Selection:</label>
              <select value={model} onChange={(e) => setModel(e.target.value)}>
                <option value="auto">Auto (Smart Routing)</option>
                <option value="fast">Fast Model (50ms)</option>
                <option value="heavy">Heavy Model (500ms)</option>
              </select>
            </div>
            <button onClick={handleSimilarity} disabled={loading} className="btn-primary">
              {loading ? 'Processing...' : 'Compare Texts'}
            </button>

            {result && (
              <div className="result-card">
                <h3>Results</h3>
                <div className="result-grid">
                  <div>
                    <strong>Similarity Score:</strong>
                    <div className="score">{(result.similarity * 100).toFixed(1)}%</div>
                  </div>
                  <div>
                    <strong>Model Used:</strong> {result.model}
                  </div>
                  <div>
                    <strong>Latency:</strong> {result.total_latency_ms?.toFixed(0)}ms
                  </div>
                  <div>
                    <strong>Cost:</strong> ${result.cost_usd?.toFixed(6)}
                  </div>
                  <div>
                    <strong>Text 1 Cached:</strong> {result.text1_cached ? '✓ Yes' : '✗ No'}
                  </div>
                  <div>
                    <strong>Text 2 Cached:</strong> {result.text2_cached ? '✓ Yes' : '✗ No'}
                  </div>
                </div>
              </div>
            )}
          </div>

          <div className="charts-section">
            <div className="chart-card">
              <h3>Request Distribution</h3>
              <ResponsiveContainer width="100%" height={200}>
                <PieChart>
                  <Pie
                    data={pieData}
                    cx="50%"
                    cy="50%"
                    labelLine={false}
                    label={({ name, value }) => `${name}: ${value}`}
                    outerRadius={70}
                    fill="#8884d8"
                    dataKey="value"
                  >
                    {pieData.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </div>

            <div className="chart-card">
              <h3>Recent Latency Trends</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={latencyData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line type="monotone" dataKey="latency" stroke="#3b82f6" name="Total" />
                  <Line type="monotone" dataKey="cached" stroke="#10b981" name="Cached" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        <div className="history-section">
          <h2>Recent Requests</h2>
          <div className="table-container">
            <table>
              <thead>
                <tr>
                  <th>Query</th>
                  <th>Model</th>
                  <th>Latency</th>
                  <th>Cached</th>
                  <th>Cost</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {history.map((item) => (
                  <tr key={item.id}>
                    <td className="query-text">{item.query_text?.substring(0, 40)}...</td>
                    <td>
                      <span className={`badge ${item.model_used}`}>{item.model_used}</span>
                    </td>
                    <td>{item.latency_ms?.toFixed(0)}ms</td>
                    <td>{item.cached ? '✓' : '✗'}</td>
                    <td>${item.cost_units?.toFixed(6)}</td>
                    <td>{new Date(item.created_at).toLocaleTimeString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
