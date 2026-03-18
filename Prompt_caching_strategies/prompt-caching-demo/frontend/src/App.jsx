import { useState, useEffect, useRef, useCallback } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend } from 'recharts';

const API = '';  // same-origin via nginx proxy

const fmt = (n, dec = 2) => Number(n || 0).toFixed(dec);
const fmtMs = (n) => `${Math.round(n || 0)} ms`;
const fmtCost = (n) => `$${fmt(n, 6)}`;

function StatCard({ label, value, sub, accent }) {
  return (
    <div style={{
      background: accent ? 'linear-gradient(135deg,#1e40af,#3b82f6)' : '#fff',
      color: accent ? '#fff' : '#1e293b',
      borderRadius: 12, padding: '20px 24px', boxShadow: '0 2px 12px rgba(59,130,246,.15)',
      minWidth: 160, flex: 1
    }}>
      <div style={{ fontSize: 12, opacity: .7, marginBottom: 6, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1 }}>{label}</div>
      <div style={{ fontSize: 28, fontWeight: 800, lineHeight: 1 }}>{value}</div>
      {sub && <div style={{ fontSize: 11, opacity: .6, marginTop: 4 }}>{sub}</div>}
    </div>
  );
}

function QueryLog({ entries }) {
  const endRef = useRef(null);
  useEffect(() => endRef.current?.scrollIntoView({ behavior: 'smooth' }), [entries]);

  return (
    <div style={{ background: '#0f172a', borderRadius: 12, padding: 16, height: 280, overflowY: 'auto',
      fontFamily: 'monospace', fontSize: 12 }}>
      {entries.length === 0 && <div style={{ color: '#475569' }}>// Submit a question to see results</div>}
      {entries.map((e, i) => (
        <div key={i} style={{ marginBottom: 12, borderBottom: '1px solid #1e293b', paddingBottom: 10 }}>
          <span style={{ color: '#64748b' }}>[{e.reqId}] </span>
          <span style={{ color: e.useCache ? '#22d3ee' : '#f59e0b', fontWeight: 700 }}>
            {e.useCache ? '⚡ CACHED' : '○ UNCACHED'}
          </span>
          <span style={{ color: '#94a3b8' }}> · {fmtMs(e.latencyMs)} · cost {fmtCost(e.cost?.total)}</span>
          <div style={{ color: '#64748b', marginTop: 2 }}>
            cache_write:{e.usage?.cacheWriteTokens || 0} read:{e.usage?.cacheReadTokens || 0} input:{e.usage?.inputTokens || 0} output:{e.usage?.outputTokens || 0}
          </div>
          <div style={{ color: '#cbd5e1', marginTop: 4, whiteSpace: 'pre-wrap', maxHeight: 80, overflow: 'hidden' }}>
            {e.answer?.slice(0, 200)}{e.answer?.length > 200 ? '...' : ''}
          </div>
        </div>
      ))}
      <div ref={endRef} />
    </div>
  );
}

export default function App() {
  const [question, setQuestion] = useState('');
  const [mode, setMode] = useState('both');   // 'cached' | 'uncached' | 'both'
  const [loading, setLoading] = useState(false);
  const [entries, setEntries] = useState([]);
  const [metrics, setMetrics] = useState(null);
  const [latencyData, setLatencyData] = useState([]);
  const [error, setError] = useState('');
  const wsRef = useRef(null);

  // WebSocket for live updates
  useEffect(() => {
    const host = typeof location !== 'undefined' && location.host ? location.host : 'localhost:4210';
    const proto = typeof location !== 'undefined' && location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(`${proto}://${host}/ws`);
    wsRef.current = ws;
    ws.onmessage = (e) => {
      const msg = JSON.parse(e.data);
      if (msg.type === 'query_result') {
        setEntries(prev => [msg, ...prev].slice(0, 50));
        setMetrics(msg.metrics);
      }
      if (msg.type === 'metrics_reset') {
        setMetrics(null); setEntries([]); setLatencyData([]);
      }
    };
    return () => ws.close();
  }, []);

  // Poll metrics every 5 s
  useEffect(() => {
    const poll = async () => {
      try {
        const r = await fetch(`${API}/api/metrics`);
        const m = await r.json();
        setMetrics(m);
        setLatencyData(prev => {
          const point = {
            t: new Date().toLocaleTimeString(),
            cached: m.avg_latency_cached_ms || 0,
            uncached: m.avg_latency_uncached_ms || 0
          };
          return [...prev.slice(-14), point];
        });
      } catch (_) {}
    };
    poll();
    const id = setInterval(poll, 5000);
    return () => clearInterval(id);
  }, []);

  const submit = useCallback(async () => {
    if (!question.trim() || loading) return;
    setLoading(true); setError('');
    try {
      if (mode === 'both') {
        const r = await fetch(`${API}/api/compare`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ question })
        });
        if (!r.ok) {
          const errBody = await r.json().catch(() => ({}));
          throw new Error(errBody.error || r.statusText || 'Request failed');
        }
      } else {
        const r = await fetch(`${API}/api/query`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ question, useCache: mode === 'cached' })
        });
        if (!r.ok) {
          const errBody = await r.json().catch(() => ({}));
          throw new Error(errBody.error || r.statusText || 'Request failed');
        }
      }
    } catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }, [question, mode, loading]);

  const resetMetrics = async () => {
    await fetch(`${API}/api/metrics`, { method: 'DELETE' });
  };

  const SAMPLE_QUESTIONS = [
    'What is write amplification in LSM trees?',
    'Explain the split-brain problem in distributed databases',
    'How does consistent hashing handle node additions?',
    'What is the difference between read-through and write-through cache?'
  ];

  return (
    <div style={{ minHeight: '100vh', background: '#f0f6ff', fontFamily: 'system-ui,sans-serif', color: '#1e293b' }}>
      {/* Header */}
      <div style={{ background: 'linear-gradient(135deg,#1e3a8a,#2563eb)', padding: '24px 32px',
        boxShadow: '0 4px 24px rgba(37,99,235,.3)' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto' }}>
          <div style={{ fontSize: 11, color: '#93c5fd', fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase' }}>
            Section 9: AI & LLM Infrastructure · Article 221
          </div>
          <h1 style={{ color: '#fff', margin: '4px 0 0', fontSize: 26, fontWeight: 800 }}>
            Prompt Caching — Live Cost & Latency Demo
          </h1>
          <div style={{ color: '#bfdbfe', fontSize: 13, marginTop: 4 }}>
            Real Anthropic API · KV cache hit/miss tracking · Cost delta calculation
          </div>
        </div>
      </div>

      <div style={{ maxWidth: 1100, margin: '0 auto', padding: '28px 32px' }}>

        {/* Stat cards — show — when no requests yet so dashboard is not misleading */}
        <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', marginBottom: 28 }}>
          <StatCard accent label="Cache Hit Rate" value={metrics?.requests_total > 0 ? `${metrics.cache_hit_rate}%` : '—'} sub="cache_read / total input tokens" />
          <StatCard label="Avg Latency — Cached" value={metrics?.requests_total > 0 ? fmtMs(metrics?.avg_latency_cached_ms) : '—'} sub="time-to-first-token benefit" />
          <StatCard label="Avg Latency — Uncached" value={metrics?.requests_total > 0 ? fmtMs(metrics?.avg_latency_uncached_ms) : '—'} sub="full KV recomputation" />
          <StatCard label="Cost Savings" value={metrics?.requests_total > 0 ? fmtCost(metrics?.cost_savings_usd) : '—'} sub="cached vs uncached total" />
          <StatCard label="Total Requests" value={metrics?.requests_total > 0 ? Math.round(metrics.requests_total) : '—'} sub="since last reset" />
        </div>

        {/* Input panel */}
        <div style={{ background: '#fff', borderRadius: 12, padding: 24, boxShadow: '0 2px 12px rgba(59,130,246,.1)', marginBottom: 24 }}>
          <div style={{ display: 'flex', gap: 12, marginBottom: 14, flexWrap: 'wrap' }}>
            {['both', 'cached', 'uncached'].map(m => (
              <button key={m} onClick={() => setMode(m)} style={{
                padding: '7px 18px', borderRadius: 8, border: 'none', cursor: 'pointer',
                fontWeight: 700, fontSize: 13,
                background: mode === m ? '#2563eb' : '#e2e8f0',
                color: mode === m ? '#fff' : '#475569'
              }}>
                {m === 'both' ? '⚡ Compare Both' : m === 'cached' ? '⚡ Cache ON' : '○ Cache OFF'}
              </button>
            ))}
            <button onClick={resetMetrics} style={{
              marginLeft: 'auto', padding: '7px 18px', borderRadius: 8, border: 'none',
              background: '#fee2e2', color: '#b91c1c', cursor: 'pointer', fontWeight: 700, fontSize: 13
            }}>Reset Metrics</button>
          </div>
          <textarea value={question} onChange={e => setQuestion(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && !e.shiftKey && (e.preventDefault(), submit())}
            placeholder="Ask a systems design question…"
            style={{ width: '100%', height: 80, padding: '10px 14px', border: '1.5px solid #cbd5e1',
              borderRadius: 8, fontSize: 14, resize: 'vertical', fontFamily: 'inherit', boxSizing: 'border-box' }} />
          <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
            {SAMPLE_QUESTIONS.map((q, i) => (
              <button key={i} onClick={() => setQuestion(q)} style={{
                padding: '5px 12px', borderRadius: 20, border: '1px solid #93c5fd',
                background: '#eff6ff', color: '#1d4ed8', fontSize: 12, cursor: 'pointer'
              }}>{q.slice(0, 45)}…</button>
            ))}
          </div>
          {error && <div style={{ marginTop: 10, color: '#b91c1c', fontSize: 13 }}>⚠ {error}</div>}
          <button onClick={submit} disabled={loading || !question.trim()} style={{
            marginTop: 14, padding: '10px 28px', background: loading ? '#93c5fd' : '#2563eb',
            color: '#fff', border: 'none', borderRadius: 8, cursor: 'pointer', fontWeight: 700, fontSize: 14
          }}>{loading ? 'Calling Anthropic API…' : 'Send Query'}</button>
        </div>

        {/* Charts + Log row */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginBottom: 24 }}>
          <div style={{ background: '#fff', borderRadius: 12, padding: 20, boxShadow: '0 2px 12px rgba(59,130,246,.1)' }}>
            <div style={{ fontWeight: 700, marginBottom: 14, fontSize: 14 }}>Average Latency Over Time</div>
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={latencyData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="t" tick={{ fontSize: 10 }} />
                <YAxis tick={{ fontSize: 10 }} unit=" ms" />
                <Tooltip formatter={v => `${v} ms`} />
                <Legend />
                <Bar dataKey="cached" fill="#3b82f6" name="Cached" radius={[4,4,0,0]} />
                <Bar dataKey="uncached" fill="#f59e0b" name="Uncached" radius={[4,4,0,0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div style={{ background: '#fff', borderRadius: 12, padding: 20, boxShadow: '0 2px 12px rgba(59,130,246,.1)' }}>
            <div style={{ fontWeight: 700, marginBottom: 14, fontSize: 14 }}>Token Breakdown</div>
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={[{
                name: 'Tokens',
                'Cache Read': Math.round(metrics?.cache_hit_tokens || 0),
                'Cache Write': Math.round(metrics?.cache_miss_tokens || 0),
              }]}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 10 }} />
                <Tooltip />
                <Legend />
                <Bar dataKey="Cache Write" fill="#6366f1" radius={[4,4,0,0]} />
                <Bar dataKey="Cache Read" fill="#22d3ee" radius={[4,4,0,0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div style={{ background: '#fff', borderRadius: 12, padding: 20, boxShadow: '0 2px 12px rgba(59,130,246,.1)' }}>
          <div style={{ fontWeight: 700, marginBottom: 14, fontSize: 14 }}>Live Request Log</div>
          <QueryLog entries={entries} />
        </div>

        <div style={{ marginTop: 20, padding: '14px 20px', background: '#eff6ff', borderRadius: 10,
          border: '1px solid #bfdbfe', fontSize: 12, color: '#1e40af', lineHeight: 1.7 }}>
          <strong>What you're seeing:</strong> Each request sends a ~1,500-token static system prompt + few-shot examples.
          With caching ON, Anthropic stores the KV tensors for that prefix. Second+ requests show
          <strong> cache_read_input_tokens {'>'} 0</strong> and lower latency.
          Compare costs: cached reads are billed at <strong>0.08 $/MTok</strong> vs <strong>0.80 $/MTok</strong> uncached.
        </div>
      </div>
    </div>
  );
}
