import React, { useState, useEffect, useRef } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import './App.css';

function App() {
  const [connected, setConnected] = useState(false);
  const [stats, setStats] = useState({ eventRate: 0, totalEvents: 0 });
  const [tumblingData, setTumblingData] = useState([]);
  const [slidingData, setSlidingData] = useState([]);
  const [sessionData, setSessionData] = useState([]);
  const [recentEvents, setRecentEvents] = useState([]);
  const wsRef = useRef(null);
  const eventCountRef = useRef(0);
  const totalEventsRef = useRef(0);

  useEffect(() => {
    // Connect to WebSocket
    const ws = new WebSocket('ws://localhost:3001');
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      console.log('Connected to stream processor');
    };

    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);

      switch (message.type) {
        case 'newEvent':
          eventCountRef.current++;
          setRecentEvents(prev => [message.data, ...prev].slice(0, 10));
          break;
        case 'tumblingWindow':
          setTumblingData(message.data);
          break;
        case 'slidingWindow':
          setSlidingData(message.data);
          break;
        case 'sessionWindow':
          setSessionData(message.data);
          break;
      }
    };

    ws.onclose = () => setConnected(false);

    // Update event rate and total every second (totalEventsRef accumulates)
    const rateInterval = setInterval(() => {
      const rate = eventCountRef.current;
      eventCountRef.current = 0;
      setStats({
        eventRate: rate,
        totalEvents: totalEventsRef.current
      });
    }, 1000);

    return () => {
      ws.close();
      clearInterval(rateInterval);
    };
  }, []);

  return (
    <div className="app">
      <header className="header">
        <h1>🪟 Stream Windowing Strategies Dashboard</h1>
        <div className="connection-status">
          <span className={`status-indicator ${connected ? 'connected' : 'disconnected'}`}></span>
          <span>{connected ? 'Connected' : 'Disconnected'}</span>
          <span className="stats">
            {stats.eventRate} events/sec | {stats.totalEvents.toLocaleString()} total
          </span>
        </div>
      </header>

      <div className="dashboard">
        {/* Tumbling Windows */}
        <section className="window-section tumbling">
          <div className="section-header">
            <h2>Tumbling Windows</h2>
            <span className="badge">Non-Overlapping | 60s Fixed</span>
          </div>
          <div className="window-description">
            Fixed 1-minute buckets that never overlap. Each event appears in exactly one window.
          </div>
          <div className="window-content">
            {tumblingData.slice(0, 3).map((window, idx) => (
              <div key={idx} className="window-card">
                <div className="window-time">
                  {new Date(window.timestamp).toLocaleTimeString()}
                </div>
                <div className="metrics-grid">
                  {window.results?.slice(0, 4).map((result, i) => (
                    <div key={i} className="metric">
                      <span className="symbol">{result.symbol}</span>
                      <span className="value">${result.avgPrice}</span>
                      <span className="count">{result.eventCount} trades</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Sliding Windows */}
        <section className="window-section sliding">
          <div className="section-header">
            <h2>Sliding Windows</h2>
            <span className="badge">Overlapping | 5min / 15s slide</span>
          </div>
          <div className="window-description">
            5-minute windows sliding every 15 seconds. Each event appears in ~20 windows.
          </div>
          <div className="window-content">
            {slidingData.slice(0, 3).map((window, idx) => (
              <div key={idx} className="window-card">
                <div className="window-time">
                  {new Date(window.windowEnd).toLocaleTimeString()}
                </div>
                <div className="metrics-grid">
                  {window.results?.slice(0, 4).map((result, i) => (
                    <div key={i} className="metric">
                      <span className="symbol">{result.symbol}</span>
                      <span className="value">${result.movingAvg}</span>
                      <span className="count">{result.eventCount} trades</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Session Windows */}
        <section className="window-section session">
          <div className="section-header">
            <h2>Session Windows</h2>
            <span className="badge">Activity-Based | 5s gap</span>
          </div>
          <div className="window-description">
            Variable-length windows that close after 30 seconds of inactivity.
          </div>
          <div className="window-content">
            {sessionData.slice(0, 6).map((session, idx) => (
              <div key={idx} className="session-card">
                <div className="session-header">
                  <span className="symbol">{session.symbol}</span>
                  <span className="duration">{(session.duration / 1000).toFixed(1)}s</span>
                </div>
                <div className="session-metrics">
                  <span>${session.avgPrice}</span>
                  <span>{session.eventCount} trades</span>
                  <span>{session.totalVolume.toLocaleString()} vol</span>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Live Events Stream */}
        <section className="events-section">
          <div className="section-header">
            <h2>Live Event Stream</h2>
            <span className="badge">Real-time Trades</span>
          </div>
          <div className="events-stream">
            {recentEvents.map((event, idx) => (
              <div key={idx} className="event-item">
                <span className="event-symbol">{event.symbol}</span>
                <span className="event-price">${event.price}</span>
                <span className="event-volume">{event.volume} shares</span>
                <span className="event-time">
                  {new Date(event.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}

export default App;
