import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [events, setEvents] = useState([]);
  const [state, setState] = useState(null);
  const [windows, setWindows] = useState([]);
  const [lateEvents, setLateEvents] = useState([]);
  
  useEffect(() => {
    // Connect to event producer
    const producerWs = new WebSocket('ws://localhost:3000');
    producerWs.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      if (data.type === 'event') {
        setEvents(prev => [...prev.slice(-50), data.data]);
      }
    };
    
    // Connect to processor
    const processorWs = new WebSocket('ws://localhost:3001');
    processorWs.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      
      if (data.type === 'state_update') {
        setState(data.data);
      } else if (data.type === 'window_triggered') {
        setWindows(prev => [...prev.slice(-10), { ...data.data, type: 'triggered' }]);
      } else if (data.type === 'window_updated') {
        setWindows(prev => [...prev.slice(-10), { ...data.data, type: 'updated' }]);
      } else if (data.type === 'late_event_dropped') {
        setLateEvents(prev => [...prev.slice(-20), data.data]);
      }
    };
    
    // HTTP fallback: poll processor stats so dashboard metrics update even if WebSocket is slow
    const pollStats = () => {
      fetch('http://localhost:3001/stats')
        .then(res => res.json())
        .then(stats => {
          setState(prev => {
            if (prev) return prev;
            return {
              watermark: stats.watermark,
              maxEventTime: stats.maxEventTime,
              watermarkLag: stats.watermarkLag != null ? stats.watermarkLag : (stats.maxEventTime - stats.watermark),
              activeWindows: (stats.windows || []).map(w => ({
                start: w.windowStart,
                end: w.windowEnd,
                eventCount: w.totalEvents,
                triggered: true,
                updates: w.updates || 0
              })),
              totalLateEvents: stats.totalLateEvents
            };
          });
        })
        .catch(() => {});
    };
    pollStats();
    const statsInterval = setInterval(pollStats, 2000);
    
    return () => {
      producerWs.close();
      processorWs.close();
      clearInterval(statsInterval);
    };
  }, []);
  
  const formatTime = (timestamp) => {
    return new Date(timestamp).toLocaleTimeString('en-US', { 
      hour12: false, 
      hour: '2-digit', 
      minute: '2-digit', 
      second: '2-digit' 
    });
  };
  
  const formatDuration = (ms) => {
    return `${(ms / 1000).toFixed(1)}s`;
  };
  
  return (
    <div className="app">
      <header>
        <h1>🌊 Watermarks & Late Data Stream Processing</h1>
        <p>Real-time demonstration of event-time processing with watermarks</p>
      </header>
      
      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-label">Current Watermark</div>
          <div className="metric-value">{state ? formatTime(state.watermark) : '--'}</div>
          <div className="metric-sub">Completeness boundary</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Watermark Lag</div>
          <div className="metric-value">{state ? formatDuration(state.watermarkLag) : '--'}</div>
          <div className="metric-sub">Behind latest event</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Active Windows</div>
          <div className="metric-value">{state?.activeWindows.length || 0}</div>
          <div className="metric-sub">In memory</div>
        </div>
        
        <div className="metric-card">
          <div className="metric-label">Late Events Dropped</div>
          <div className="metric-value">{state?.totalLateEvents ?? lateEvents.length}</div>
          <div className="metric-sub">Beyond allowed lateness</div>
        </div>
      </div>
      
      <div className="content-grid">
        <div className="panel">
          <h2>📊 Recent Events</h2>
          <div className="event-stream">
            {events.slice(-15).reverse().map((evt, idx) => (
              <div key={idx} className={`event-item ${evt.isLate ? 'late' : 'ontime'}`}>
                <div className="event-header">
                  <span className="event-type">{evt.type}</span>
                  <span className="event-time">{formatTime(evt.eventTime)}</span>
                </div>
                {evt.isLate && (
                  <div className="late-badge">
                    ⚠️ Late by {formatDuration(evt.lateBy)}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
        
        <div className="panel">
          <h2>🪟 Window Computations</h2>
          <div className="window-stream">
            {windows.slice(-10).reverse().map((win, idx) => (
              <div key={idx} className={`window-item ${win.type}`}>
                <div className="window-header">
                  <span className="window-time">
                    {formatTime(win.windowStart)} - {formatTime(win.windowEnd)}
                  </span>
                  <span className={`window-badge ${win.type}`}>
                    {win.type === 'triggered' ? '✓ Triggered' : '🔄 Updated'}
                  </span>
                </div>
                <div className="window-stats">
                  <div>Events: {win.totalEvents}</div>
                  <div>Value: ${win.totalValue}</div>
                  <div>Updates: {win.updates}</div>
                </div>
                <div className="event-breakdown">
                  {Object.entries(win.eventCounts).map(([type, count]) => (
                    <span key={type} className="breakdown-item">
                      {type}: {count}
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
      
      {state && state.activeWindows.length > 0 && (
        <div className="panel timeline-panel">
          <h2>⏱️ Window Timeline</h2>
          <div className="timeline">
            {state.activeWindows.map((win, idx) => (
              <div key={idx} className={`timeline-window ${win.triggered ? 'triggered' : 'active'}`}>
                <div className="timeline-label">
                  {formatTime(win.start)}
                </div>
                <div className="timeline-bar">
                  <div className="event-count">{win.eventCount} events</div>
                  {win.updates > 1 && <div className="update-badge">{win.updates} updates</div>}
                </div>
                <div className="window-status">
                  {win.triggered ? '✓ Computed' : '⏳ Open'}
                </div>
              </div>
            ))}
          </div>
          <div className="watermark-indicator">
            <div className="watermark-line">
              <span className="watermark-label">
                ← Watermark: {formatTime(state.watermark)}
              </span>
            </div>
          </div>
        </div>
      )}
      
      {lateEvents.length > 0 && (
        <div className="panel alert-panel">
          <h2>🚫 Dropped Late Events</h2>
          <div className="late-events">
            {lateEvents.slice(-5).reverse().map((evt, idx) => (
              <div key={idx} className="dropped-event">
                <span className="event-id">{evt.id}</span>
                <span className="event-type">{evt.type}</span>
                <span className="lateness">Late by {formatDuration(evt.lateBy)}</span>
                <span className="reason">Beyond 10s allowed lateness</span>
              </div>
            ))}
          </div>
        </div>
      )}
      
      <div className="info-panel">
        <h3>How It Works</h3>
        <ul>
          <li><strong>Event Time:</strong> When the event actually occurred (may be in the past)</li>
          <li><strong>Processing Time:</strong> When we received the event (now)</li>
          <li><strong>Watermark:</strong> "I've seen all events up to this time" - triggers window computations</li>
          <li><strong>Watermark Lag:</strong> 20 seconds behind latest event (configurable trade-off)</li>
          <li><strong>Allowed Lateness:</strong> 10 seconds - late data updates already-triggered windows; beyond that, events are dropped</li>
          <li><strong>Late Events:</strong> 15% of events arrive with random delays (0-45 seconds)</li>
        </ul>
      </div>
    </div>
  );
}

export default App;
