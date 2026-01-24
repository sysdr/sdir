import React, { useState, useEffect, useRef } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from 'recharts';
import './App.css';

const BACKEND_URL = 'http://localhost:4000';
const QUALITIES = ['240p', '360p', '480p', '720p', '1080p'];
const QUALITY_BITRATES = {
  '240p': 400,
  '360p': 800,
  '480p': 1400,
  '720p': 2800,
  '1080p': 5000
};

function App() {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentQuality, setCurrentQuality] = useState('480p');
  const [currentSegment, setCurrentSegment] = useState(0);
  const [buffer, setBuffer] = useState([]);
  const [bufferHealth, setBufferHealth] = useState(100);
  const [metrics, setMetrics] = useState({
    throughput: 0,
    qualitySwitches: 0,
    rebufferEvents: 0,
    avgBitrate: 0
  });
  const [networkThrottle, setNetworkThrottle] = useState({
    enabled: false,
    bandwidth: 5000
  });
  const [chartData, setChartData] = useState([]);
  const [logs, setLogs] = useState([]);
  const [backendMetrics, setBackendMetrics] = useState({
    totalSegmentsServed: 0,
    segmentsByQuality: {},
    activeConnections: 0,
    averageLatency: 0
  });

  const playbackInterval = useRef(null);
  const downloadInterval = useRef(null);
  const metricsHistory = useRef([]);
  const metricsFetchInterval = useRef(null);

  const addLog = (message, type = 'info') => {
    const timestamp = new Date().toLocaleTimeString();
    setLogs(prev => [{timestamp, message, type}, ...prev.slice(0, 49)]);
  };

  // ABR Algorithm: Buffer-based with throughput consideration
  const selectQuality = (currentThroughput, bufferLevel) => {
    const bufferSeconds = bufferLevel * 10; // Each segment is 10 seconds
    
    // Conservative: if buffer is low, drop quality immediately
    if (bufferSeconds < 10) {
      const index = QUALITIES.indexOf(currentQuality);
      if (index > 0) {
        const newQuality = QUALITIES[index - 1];
        addLog(`⚠️ Low buffer (${bufferSeconds.toFixed(1)}s), switching to ${newQuality}`, 'warning');
        setMetrics(prev => ({...prev, qualitySwitches: prev.qualitySwitches + 1}));
        return newQuality;
      }
    }
    
    // Aggressive upgrade: if buffer is healthy and throughput supports it
    if (bufferSeconds > 20 && currentThroughput > 0) {
      const currentBitrate = QUALITY_BITRATES[currentQuality];
      const targetBitrate = currentThroughput * 0.8; // 80% utilization for safety
      
      const betterQuality = QUALITIES.reverse().find(q => 
        QUALITY_BITRATES[q] < targetBitrate && 
        QUALITY_BITRATES[q] > currentBitrate
      );
      
      if (betterQuality) {
        addLog(`📈 High throughput (${currentThroughput.toFixed(0)} kbps), upgrading to ${betterQuality}`, 'success');
        setMetrics(prev => ({...prev, qualitySwitches: prev.qualitySwitches + 1}));
        return betterQuality;
      }
    }
    
    return currentQuality;
  };

  // Download segment
  const downloadSegment = async (quality, segmentIndex) => {
    const startTime = Date.now();
    const url = `${BACKEND_URL}/segments/${quality}/segment_${segmentIndex}.m4s`;
    
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error('Segment not found');
      
      const blob = await response.blob();
      const downloadTime = Date.now() - startTime;
      const throughputKbps = (blob.size * 8) / (downloadTime / 1000) / 1024;
      
      addLog(`✅ Downloaded ${quality} segment ${segmentIndex} (${(blob.size / 1024).toFixed(1)} KB in ${downloadTime}ms)`, 'success');
      
      return { quality, segmentIndex, blob, throughputKbps, downloadTime };
    } catch (error) {
      addLog(`❌ Failed to download segment ${segmentIndex}: ${error.message}`, 'error');
      return null;
    }
  };

  // Start playback
  const startPlayback = () => {
    setIsPlaying(true);
    setCurrentSegment(0);
    setBuffer([]);
    setMetrics({
      throughput: 0,
      qualitySwitches: 0,
      rebufferEvents: 0,
      avgBitrate: QUALITY_BITRATES['480p']
    });
    setChartData([]);
    metricsHistory.current = [];
    addLog('▶️ Playback started', 'info');

    // Simulate playback (consume buffer every 10 seconds)
    playbackInterval.current = setInterval(() => {
      setBuffer(prev => {
        if (prev.length === 0) {
          addLog('⏸️ Buffer empty! Rebuffering...', 'error');
          setMetrics(m => ({...m, rebufferEvents: m.rebufferEvents + 1}));
          return prev;
        }
        const [played, ...remaining] = prev;
        setCurrentSegment(s => s + 1);
        setBufferHealth((remaining.length / 3) * 100);
        return remaining;
      });
    }, 10000);

    // Download segments continuously
    let segmentCounter = 0;
    const downloadLoop = async () => {
      if (segmentCounter >= 20) {
        addLog('🏁 All segments downloaded', 'info');
        clearInterval(downloadInterval.current);
        return;
      }

      // Determine quality using ABR algorithm
      const avgThroughput = metricsHistory.current.length > 0
        ? metricsHistory.current.reduce((sum, t) => sum + t, 0) / metricsHistory.current.length
        : 0;
      
      const bufferLevel = buffer.length;
      const selectedQuality = selectQuality(avgThroughput, bufferLevel);
      setCurrentQuality(selectedQuality);

      // Download segment
      const segment = await downloadSegment(selectedQuality, segmentCounter);
      
      if (segment) {
        metricsHistory.current.push(segment.throughputKbps);
        if (metricsHistory.current.length > 5) metricsHistory.current.shift();

        setBuffer(prev => [...prev, segment]);
        setBufferHealth(Math.min(((buffer.length + 1) / 3) * 100, 100));
        
        setMetrics(prev => ({
          ...prev,
          throughput: segment.throughputKbps,
          avgBitrate: (prev.avgBitrate * 0.7) + (QUALITY_BITRATES[selectedQuality] * 0.3)
        }));

        setChartData(prev => [...prev, {
          time: segmentCounter,
          quality: QUALITY_BITRATES[selectedQuality],
          throughput: segment.throughputKbps,
          buffer: buffer.length + 1
        }].slice(-20));
      }

      segmentCounter++;
    };

    downloadInterval.current = setInterval(downloadLoop, 2000);
    downloadLoop(); // Start immediately
  };

  const stopPlayback = () => {
    setIsPlaying(false);
    clearInterval(playbackInterval.current);
    clearInterval(downloadInterval.current);
    addLog('⏹️ Playback stopped', 'info');
  };

  const applyNetworkThrottle = async () => {
    try {
      await fetch(`${BACKEND_URL}/network/throttle`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          enabled: networkThrottle.enabled,
          bandwidthKbps: networkThrottle.bandwidth
        })
      });
      addLog(`🌐 Network ${networkThrottle.enabled ? 'throttled to ' + networkThrottle.bandwidth + ' kbps' : 'throttling disabled'}`, 'info');
    } catch (error) {
      addLog(`❌ Failed to apply network throttle: ${error.message}`, 'error');
    }
  };

  // Fetch backend metrics periodically
  useEffect(() => {
    const fetchBackendMetrics = async () => {
      try {
        const response = await fetch(`${BACKEND_URL}/metrics`);
        if (response.ok) {
          const data = await response.json();
          setBackendMetrics({
            totalSegmentsServed: data.totalSegmentsServed || 0,
            segmentsByQuality: data.segmentsByQuality || {},
            activeConnections: data.activeConnections || 0,
            averageLatency: data.averageLatency || 0
          });
        }
      } catch (error) {
        // Silently fail - backend might not be ready yet
      }
    };

    // Fetch immediately and then every 2 seconds
    fetchBackendMetrics();
    metricsFetchInterval.current = setInterval(fetchBackendMetrics, 2000);

    return () => {
      clearInterval(playbackInterval.current);
      clearInterval(downloadInterval.current);
      clearInterval(metricsFetchInterval.current);
    };
  }, []);

  return (
    <div className="App">
      <header className="header">
        <h1>🎬 Adaptive Bitrate Streaming Demo</h1>
        <p>HLS vs. DASH • Real-time Quality Adaptation</p>
      </header>

      <div className="container">
        <div className="player-section">
          <div className="video-player">
            <div className="player-display">
              <div className="quality-badge">{currentQuality}</div>
              {isPlaying ? (
                <div className="playing-indicator">
                  <div className="pulse"></div>
                  <span>Segment {currentSegment}</span>
                </div>
              ) : (
                <div className="play-prompt">Click Play to Start</div>
              )}
            </div>
            <div className="player-controls">
              {!isPlaying ? (
                <button onClick={startPlayback} className="btn-primary">▶️ Play</button>
              ) : (
                <button onClick={stopPlayback} className="btn-secondary">⏹️ Stop</button>
              )}
            </div>
          </div>

          <div className="buffer-section">
            <h3>Buffer Health</h3>
            <div className="buffer-bar">
              <div 
                className="buffer-fill" 
                style={{
                  width: `${bufferHealth}%`,
                  backgroundColor: bufferHealth > 50 ? '#3B82F6' : bufferHealth > 20 ? '#FBBF24' : '#EF4444'
                }}
              ></div>
            </div>
            <div className="buffer-info">
              <span>{buffer.length} segments buffered</span>
              <span>{bufferHealth.toFixed(0)}%</span>
            </div>
          </div>
        </div>

        <div className="metrics-section">
          <h3>Performance Metrics</h3>
          <div className="metrics-grid">
            <div className="metric-card">
              <div className="metric-value">{metrics.throughput.toFixed(0)}</div>
              <div className="metric-label">Throughput (kbps)</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.avgBitrate.toFixed(0)}</div>
              <div className="metric-label">Avg Bitrate (kbps)</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.qualitySwitches}</div>
              <div className="metric-label">Quality Switches</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{metrics.rebufferEvents}</div>
              <div className="metric-label">Rebuffer Events</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{backendMetrics.totalSegmentsServed}</div>
              <div className="metric-label">Total Segments Served</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{backendMetrics.activeConnections}</div>
              <div className="metric-label">Active Connections</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{backendMetrics.averageLatency.toFixed(0)}</div>
              <div className="metric-label">Avg Latency (ms)</div>
            </div>
            <div className="metric-card">
              <div className="metric-value">{Object.values(backendMetrics.segmentsByQuality).reduce((a, b) => a + (b || 0), 0)}</div>
              <div className="metric-label">Segments by Quality</div>
            </div>
          </div>
        </div>

        <div className="chart-section">
          <h3>Real-Time Metrics</h3>
          {chartData.length > 0 ? (
            <LineChart width={800} height={300} data={chartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" />
              <XAxis dataKey="time" label={{ value: 'Segment', position: 'insideBottom', offset: -5 }} />
              <YAxis label={{ value: 'kbps', angle: -90, position: 'insideLeft' }} />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="quality" stroke="#3B82F6" name="Quality (kbps)" strokeWidth={2} />
              <Line type="monotone" dataKey="throughput" stroke="#10B981" name="Throughput (kbps)" strokeWidth={2} />
            </LineChart>
          ) : (
            <div className="chart-placeholder">Start playback to see real-time metrics</div>
          )}
        </div>

        <div className="network-section">
          <h3>Network Simulation</h3>
          <div className="network-controls">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={networkThrottle.enabled}
                onChange={(e) => setNetworkThrottle({...networkThrottle, enabled: e.target.checked})}
              />
              Enable Throttling
            </label>
            <div className="slider-group">
              <label>Bandwidth: {networkThrottle.bandwidth} kbps</label>
              <input
                type="range"
                min="200"
                max="10000"
                step="100"
                value={networkThrottle.bandwidth}
                onChange={(e) => setNetworkThrottle({...networkThrottle, bandwidth: parseInt(e.target.value)})}
                disabled={!networkThrottle.enabled}
              />
            </div>
            <button onClick={applyNetworkThrottle} className="btn-primary">Apply Settings</button>
          </div>
          <div className="presets">
            <button onClick={() => {
              setNetworkThrottle({enabled: true, bandwidth: 500});
              setTimeout(applyNetworkThrottle, 100);
            }} className="btn-preset">3G (500 kbps)</button>
            <button onClick={() => {
              setNetworkThrottle({enabled: true, bandwidth: 2000});
              setTimeout(applyNetworkThrottle, 100);
            }} className="btn-preset">4G (2 Mbps)</button>
            <button onClick={() => {
              setNetworkThrottle({enabled: true, bandwidth: 10000});
              setTimeout(applyNetworkThrottle, 100);
            }} className="btn-preset">5G (10 Mbps)</button>
            <button onClick={() => {
              setNetworkThrottle({enabled: false, bandwidth: 5000});
              setTimeout(applyNetworkThrottle, 100);
            }} className="btn-preset">No Limit</button>
          </div>
        </div>

        <div className="logs-section">
          <h3>Activity Logs</h3>
          <div className="logs-container">
            {logs.map((log, i) => (
              <div key={i} className={`log-entry log-${log.type}`}>
                <span className="log-time">{log.timestamp}</span>
                <span className="log-message">{log.message}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
