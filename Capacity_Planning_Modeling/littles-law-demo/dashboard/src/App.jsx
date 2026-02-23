import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, ReferenceLine, AreaChart, Area
} from 'recharts';

const GATEWAY = import.meta.env.VITE_GATEWAY_URL || '/api';
const APP_SERVER = import.meta.env.VITE_APP_URL || 'http://localhost:3002';

export default function App() {
  const [stats, setStats] = useState(null);
  const [history, setHistory] = useState([]);
  const [latencyMs, setLatencyMs] = useState(80);
  const [pendingLatency, setPendingLatency] = useState(80);
  const [appState, setAppState] = useState(null);
  const [error, setError] = useState(null);
  const [loadActive, setLoadActive] = useState(false);
  const loadRef = useRef(null);
  const requestCounter = useRef(0);

  const fetchStats = useCallback(async () => {
    try {
      const [statsRes, stateRes] = await Promise.all([
        fetch(`${GATEWAY}/littles-law-stats`),
        fetch(`${APP_SERVER}/api/current-state`)
      ]);
      if (statsRes.ok) {
        const data = await statsRes.json();
        setStats(data);
        setHistory(prev => {
          const layerObj = (data.layers || []).map(l => [
            `${l.layer}_lambda`, l.lambda_rps,
            `${l.layer}_L_mean`, l.L_mean,
            `${l.layer}_L_p99`, l.L_p99,
          ]).flat().reduce((acc, _, i, arr) => {
            if (i % 2 === 0) acc[arr[i]] = arr[i + 1];
            return acc;
          }, {});
          const entry = {
            time: new Date().toLocaleTimeString(),
            gateway_L: data.current_concurrent_gateway,
            ...layerObj,
          };
          return [...prev.slice(-40), entry];
        });
      }
      if (stateRes.ok) setAppState(await stateRes.json());
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    fetchStats();
    const interval = setInterval(fetchStats, 1500);
    return () => clearInterval(interval);
  }, [fetchStats]);

  const applyLatency = async () => {
    try {
      await fetch(`${APP_SERVER}/api/set-latency`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ latency_ms: pendingLatency })
      });
      setLatencyMs(pendingLatency);
    } catch(e) { setError(e.message); }
  };

  const fireRequest = useCallback(async () => {
    requestCounter.current++;
    try { await fetch(`${GATEWAY}/process`); } catch(_) {}
  }, []);

  const startLoad = () => {
    if (loadRef.current) return;
    setLoadActive(true);
    loadRef.current = setInterval(() => {
      for (let i = 0; i < 8; i++) setTimeout(fireRequest, i * 120);
    }, 1000);
  };
  const stopLoad = () => {
    clearInterval(loadRef.current);
    loadRef.current = null;
    setLoadActive(false);
  };

  const gatewayLimit = stats?.gateway_limit || 50;
  const currentL = stats?.current_concurrent_gateway || 0;
  const utilPct = ((currentL / gatewayLimit) * 100).toFixed(1);
  const utilColor = utilPct < 60 ? '#22c55e' : utilPct < 80 ? '#f59e0b' : '#ef4444';

  const predictedL = appState
    ? ((8 * pendingLatency) / 1000).toFixed(2)
    : '—';

  return (
    <div style={{
      minHeight: '100vh', background: 'linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%)',
      fontFamily: 'system-ui, -apple-system, sans-serif', padding: '24px'
    }}>
      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: 32 }}>
        <h1 style={{ fontSize: 28, fontWeight: 800, color: '#1e3a8a', margin: 0 }}>
          Little's Law Live Dashboard
        </h1>
        <div style={{
          display: 'inline-block', marginTop: 8, padding: '6px 20px',
          background: '#1d4ed8', color: 'white', borderRadius: 20, fontSize: 15, fontWeight: 700
        }}>L = λ × W</div>
        <p style={{ color: '#64748b', marginTop: 6, fontSize: 13 }}>
          Concurrency = Rate × Latency — applied per service layer
        </p>
        {error && (
          <div style={{ background: '#fef2f2', border: '1px solid #fca5a5', padding: '8px 16px', borderRadius: 8, marginTop: 8, color: '#dc2626', fontSize: 12 }}>
            ⚠ {error} — waiting for services...
          </div>
        )}
      </div>

      {/* Top metrics row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
        {[
          { label: 'Current L (Gateway)', value: currentL, sub: `of ${gatewayLimit} limit`, color: utilColor },
          { label: 'Utilization', value: `${utilPct}%`, sub: utilPct < 70 ? '✓ Safe' : utilPct < 85 ? '⚠ Caution' : '✗ Danger', color: utilColor },
          { label: 'Injected W', value: `${latencyMs}ms`, sub: 'App server latency', color: '#3b82f6' },
          { label: 'Predicted L', value: predictedL, sub: 'at 8 RPS (Little\'s Law)', color: '#1d4ed8' },
        ].map((m, i) => (
          <div key={i} style={{
            background: 'white', borderRadius: 16, padding: '20px 16px',
            boxShadow: '0 4px 12px rgba(59,130,246,0.15)', textAlign: 'center'
          }}>
            <div style={{ fontSize: 12, color: '#64748b', marginBottom: 8 }}>{m.label}</div>
            <div style={{ fontSize: 36, fontWeight: 800, color: m.color }}>{m.value}</div>
            <div style={{ fontSize: 11, color: m.color, marginTop: 4 }}>{m.sub}</div>
          </div>
        ))}
      </div>

      {/* Charts row */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 24 }}>
        {/* L over time */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Concurrent Requests (L) Over Time</h3>
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={history}>
              <defs>
                <linearGradient id="lgL" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3}/>
                  <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9"/>
              <XAxis dataKey="time" tick={{ fontSize: 9 }} interval="preserveStartEnd"/>
              <YAxis tick={{ fontSize: 10 }}/>
              <Tooltip/>
              <ReferenceLine y={gatewayLimit} stroke="#ef4444" strokeDasharray="4" label={{ value: 'Limit', position: 'right', fontSize: 10 }}/>
              <ReferenceLine y={gatewayLimit * 0.7} stroke="#f59e0b" strokeDasharray="4" label={{ value: '70%', position: 'right', fontSize: 9 }}/>
              <Area type="monotone" dataKey="gateway_L" stroke="#3b82f6" fill="url(#lgL)" name="L (gateway)" strokeWidth={2}/>
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* Per-layer bar chart */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Per-Layer L (mean vs p99 latency)</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={stats?.layers || []}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9"/>
              <XAxis dataKey="layer" tick={{ fontSize: 11 }}/>
              <YAxis tick={{ fontSize: 10 }}/>
              <Tooltip formatter={(v, n) => [v, n]}/>
              <Legend/>
              <Bar dataKey="L_mean" name="L (mean W)" fill="#60a5fa" radius={[4,4,0,0]}/>
              <Bar dataKey="L_p99" name="L (p99 W)" fill="#1d4ed8" radius={[4,4,0,0]}/>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Layer details table */}
      <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)', marginBottom: 24 }}>
        <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>Little's Law Per Layer — Live Computation</h3>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
          <thead>
            <tr style={{ background: '#eff6ff' }}>
              {['Layer', 'λ (RPS)', 'W mean (ms)', 'W p99 (ms)', 'L (mean)', 'L (p99)', 'Rec. Pool Size (3×p99)'].map(h => (
                <th key={h} style={{ padding: '8px 12px', textAlign: 'left', color: '#1e40af', fontWeight: 600 }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {(stats?.layers || []).map((l, i) => (
              <tr key={i} style={{ borderBottom: '1px solid #f1f5f9' }}>
                <td style={{ padding: '8px 12px', fontWeight: 600, color: '#1e3a8a' }}>{l.layer}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.lambda_rps}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.w_mean_ms}</td>
                <td style={{ padding: '8px 12px', color: '#374151' }}>{l.w_p99_ms}</td>
                <td style={{ padding: '8px 12px', color: '#3b82f6', fontWeight: 600 }}>{l.L_mean}</td>
                <td style={{ padding: '8px 12px', color: '#1d4ed8', fontWeight: 700 }}>{l.L_p99}</td>
                <td style={{ padding: '8px 12px', color: '#059669', fontWeight: 600 }}>{l.recommended_pool_size}</td>
              </tr>
            ))}
            {(!stats?.layers || stats.layers.length === 0) && (
              <tr><td colSpan={7} style={{ padding: '16px', textAlign: 'center', color: '#94a3b8' }}>
                Generate load to see real measurements
              </td></tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Controls */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {/* Latency injection */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>
            🔬 Inject Latency — Watch L Change at Constant λ
          </h3>
          <p style={{ fontSize: 12, color: '#64748b', margin: '0 0 12px' }}>
            Increase W → L increases proportionally. This is the failure mode that saturates thread pools without traffic growth.
          </p>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <input
              type="range" min="20" max="500" value={pendingLatency}
              onChange={e => setPendingLatency(parseInt(e.target.value))}
              style={{ flex: 1 }}
            />
            <span style={{ width: 60, textAlign: 'center', fontWeight: 700, color: '#1d4ed8' }}>{pendingLatency}ms</span>
            <button onClick={applyLatency} style={{
              background: '#1d4ed8', color: 'white', border: 'none', borderRadius: 8,
              padding: '8px 16px', cursor: 'pointer', fontWeight: 600, fontSize: 13
            }}>Apply</button>
          </div>
          <div style={{ marginTop: 12, padding: '10px 14px', background: '#eff6ff', borderRadius: 8, fontSize: 12 }}>
            <strong>Little's Law prediction at 8 RPS:</strong><br/>
            L = 8 × {pendingLatency}/1000 = <strong style={{ color: '#1d4ed8' }}>{(8 * pendingLatency / 1000).toFixed(2)} concurrent</strong>
            {pendingLatency > 200 && (
              <span style={{ color: '#dc2626', marginLeft: 8 }}>⚠ Pool saturation risk</span>
            )}
          </div>
        </div>

        {/* Load control */}
        <div style={{ background: 'white', borderRadius: 16, padding: 20, boxShadow: '0 4px 12px rgba(59,130,246,0.15)' }}>
          <h3 style={{ margin: '0 0 16px', color: '#1e3a8a', fontSize: 14 }}>
            ⚡ Load Generator Controls
          </h3>
          <p style={{ fontSize: 12, color: '#64748b', margin: '0 0 16px' }}>
            Generate ~8 RPS from the browser to observe Little's Law measurements update in real time.
          </p>
          <div style={{ display: 'flex', gap: 12 }}>
            <button onClick={startLoad} disabled={loadActive} style={{
              flex: 1, background: loadActive ? '#94a3b8' : '#22c55e', color: 'white',
              border: 'none', borderRadius: 8, padding: '12px', cursor: loadActive ? 'default' : 'pointer',
              fontWeight: 700, fontSize: 14
            }}>▶ Start Load</button>
            <button onClick={stopLoad} disabled={!loadActive} style={{
              flex: 1, background: !loadActive ? '#94a3b8' : '#ef4444', color: 'white',
              border: 'none', borderRadius: 8, padding: '12px', cursor: !loadActive ? 'default' : 'pointer',
              fontWeight: 700, fontSize: 14
            }}>■ Stop Load</button>
          </div>
          <div style={{ marginTop: 12, padding: '10px', background: '#f8fafc', borderRadius: 8, fontSize: 11, color: '#64748b' }}>
            App server concurrency limit: {appState?.concurrency_limit || 30} |
            DB pool size: {appState?.db_pool_size || 5} |
            Current W: {appState?.injected_latency_ms || 80}ms
          </div>
        </div>
      </div>

      <div style={{ textAlign: 'center', marginTop: 24, fontSize: 11, color: '#94a3b8' }}>
        Article 201 · System Design Interview Roadmap · Section 8: Production Engineering
      </div>
    </div>
  );
}
