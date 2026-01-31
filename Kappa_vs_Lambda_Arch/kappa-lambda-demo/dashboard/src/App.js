import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [lambdaStats, setLambdaStats] = useState(null);
  const [kappaStats, setKappaStats] = useState(null);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const [lambda, kappa] = await Promise.all([
          fetch('http://localhost:3005/lambda/merged').then(r => r.json()),
          fetch('http://localhost:3005/kappa/stats').then(r => r.json())
        ]);
        setLambdaStats(lambda);
        setKappaStats(kappa);
      } catch (err) {
        console.error('Error fetching stats:', err);
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 2000);
    return () => clearInterval(interval);
  }, []);

  const [replayStatus, setReplayStatus] = useState(null);
  const triggerReplay = async () => {
    setReplayStatus(null);
    try {
      const res = await fetch('http://localhost:3005/replay', { method: 'POST' });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        setReplayStatus('success');
        setTimeout(() => setReplayStatus(null), 3000);
      } else {
        setReplayStatus(data.error || 'Replay failed');
      }
    } catch (err) {
      setReplayStatus('Request failed — check serving layer');
      setTimeout(() => setReplayStatus(null), 4000);
    }
  };

  return (
    <div className="app">
      <header>
        <h1>🏗️ Kappa vs Lambda Architecture</h1>
        <p>Real-time comparison of big data processing patterns</p>
      </header>

      <div className="architectures">
        <div className="architecture lambda">
          <h2>Lambda Architecture</h2>
          <div className="subtitle">Batch + Speed Layers</div>
          
          {lambdaStats && (
            <>
              {lambdaStats.error && (
                <div className="metric-card" style={{ background: '#fed7d7', color: '#9b2c2c' }}>
                  {lambdaStats.error} — ensure producer and batch/speed layers are running.
                </div>
              )}
              <div className="metric-card">
                <div className="metric-label">Total Events</div>
                <div className="metric-value">{lambdaStats.totalEvents?.toLocaleString() ?? '0'}</div>
                {!lambdaStats.error && (lambdaStats.totalEvents ?? 0) === 0 && (
                  <div className="waiting-msg">Waiting for events… run demo or wait for producer.</div>
                )}
              </div>

              <div className="metric-card drift">
                <div className="metric-label">Avg Session Duration</div>
                <div className="dual-values">
                  <div>
                    <span className="layer-tag batch">Batch</span>
                    <span className="value">{lambdaStats.avgSessionDuration?.batch?.toFixed(2)}s</span>
                  </div>
                  <div>
                    <span className="layer-tag speed">Speed</span>
                    <span className="value">{lambdaStats.avgSessionDuration?.speed?.toFixed(2)}s</span>
                  </div>
                </div>
                {lambdaStats.avgSessionDuration?.drift > 0 && (
                  <div className="drift-warning">
                    ⚠️ Drift: {lambdaStats.avgSessionDuration.drift.toFixed(2)}s
                  </div>
                )}
              </div>

              <div className="metric-card">
                <div className="metric-label">Top Pages</div>
                <div className="breakdown">
                  {Object.entries(lambdaStats.pageViews || {})
                    .sort((a, b) => b[1] - a[1])
                    .slice(0, 3)
                    .map(([page, count]) => (
                      <div key={page} className="breakdown-item">
                        <span>{page}</span>
                        <span>{count}</span>
                      </div>
                    ))}
                </div>
              </div>
            </>
          )}
        </div>

        <div className="architecture kappa">
          <h2>Kappa Architecture</h2>
          <div className="subtitle">Unified Stream Processing</div>
          
          {kappaStats && (
            <>
              {kappaStats.error && (
                <div className="metric-card" style={{ background: '#fed7d7', color: '#9b2c2c' }}>
                  {kappaStats.error} — ensure kappa-processor is running.
                </div>
              )}
              <div className="metric-card">
                <div className="metric-label">Total Events</div>
                <div className="metric-value">{kappaStats.totalEvents?.toLocaleString() ?? '0'}</div>
                {!kappaStats.error && (kappaStats.totalEvents ?? 0) === 0 && (
                  <div className="waiting-msg">Waiting for events… run demo or wait for producer.</div>
                )}
              </div>

              <div className="metric-card">
                <div className="metric-label">Avg Session Duration</div>
                <div className="metric-value large">
                  {kappaStats.avgSessionDuration != null ? kappaStats.avgSessionDuration.toFixed(2) + 's' : '—'}
                </div>
                <div className="consistency">✓ Single source of truth</div>
              </div>

              <div className="metric-card">
                <div className="metric-label">Processor Version</div>
                <div className="version">
                  {kappaStats.processorVersion}
                  {kappaStats.replayMode && <span className="replay-badge">Replaying...</span>}
                </div>
              </div>

              <button className="replay-btn" onClick={triggerReplay}>
                🔄 Trigger Replay (Redeploy)
              </button>
              {replayStatus && (
                <div className={`replay-status ${replayStatus === 'success' ? 'success' : 'error'}`}>
                  {replayStatus === 'success' ? '✓ Replay started' : replayStatus}
                </div>
              )}

              <div className="metric-card">
                <div className="metric-label">Top Pages</div>
                <div className="breakdown">
                  {Object.entries(kappaStats.pageViews || {})
                    .sort((a, b) => b[1] - a[1])
                    .slice(0, 3)
                    .map(([page, count]) => (
                      <div key={page} className="breakdown-item">
                        <span>{page}</span>
                        <span>{count}</span>
                      </div>
                    ))}
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="insights">
        <div className="insight-card">
          <h3>📊 What You're Seeing</h3>
          <p><strong>Lambda</strong> shows drift between batch and speed layers due to different rounding logic—this happens in production when implementations diverge.</p>
          <p><strong>Kappa</strong> maintains consistency with a single codebase. Click "Trigger Replay" to see atomic redeployment.</p>
        </div>
      </div>
    </div>
  );
}

export default App;
