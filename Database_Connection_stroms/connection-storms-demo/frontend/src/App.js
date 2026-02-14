import { useState, useEffect, useRef, useCallback } from 'react';

const C = {
  bg:'#0a0e1a',surface:'#0f1628',card:'#141c30',cardBorder:'#1e2d4a',
  blue:'#3b82f6',blueDim:'#1d4ed8',blueLight:'#60a5fa',blueGhost:'rgba(59,130,246,0.08)',
  cyan:'#22d3ee',red:'#ef4444',redDim:'#dc2626',redGhost:'rgba(239,68,68,0.08)',
  green:'#4ade80',greenDim:'#16a34a',greenGhost:'rgba(74,222,128,0.08)',
  amber:'#f59e0b',slate:'#334155',slateLight:'#475569',muted:'#64748b',
  text:'#e2e8f0',textDim:'#94a3b8',
};

function ConnectionGauge({ value, max, label, color }) {
  const pct = Math.min(100, Math.round((value / max) * 100));
  const radius = 44, circ = 2 * Math.PI * radius, arc = circ * 0.75;
  const offset = arc - (arc * pct) / 100;
  const gaugeColor = pct >= 95 ? C.red : pct >= 75 ? C.amber : color;
  return (
    <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:4 }}>
      <svg width="110" height="80" viewBox="0 0 110 90">
        <circle cx="55" cy="58" r={radius} fill="none" stroke={C.slate} strokeWidth="8"
          strokeDasharray={`${arc} ${circ-arc}`} strokeLinecap="round" transform={`rotate(-225, 55, 58)`}/>
        <circle cx="55" cy="58" r={radius} fill="none" stroke={gaugeColor} strokeWidth="8"
          strokeDasharray={`${arc-offset} ${circ-(arc-offset)}`} strokeLinecap="round" transform={`rotate(-225, 55, 58)`}
          style={{ transition:'stroke-dasharray 0.5s ease, stroke 0.3s' }}/>
        <text x="55" y="55" textAnchor="middle" fontSize="20" fontWeight="700" fill={gaugeColor} style={{ transition:'fill 0.3s' }}>{value}</text>
        <text x="55" y="68" textAnchor="middle" fontSize="9" fill={C.muted}>/{max}</text>
      </svg>
      <span style={{ fontSize:10, color:C.textDim, letterSpacing:'0.08em', textTransform:'uppercase' }}>{label}</span>
    </div>
  );
}

function StatPill({ label, value, color=C.text, bg=C.slate+'44' }) {
  return (
    <div style={{ display:'flex', flexDirection:'column', gap:4, padding:'14px 18px', background:bg, borderRadius:12, border:`1px solid ${color}33`, boxShadow:'inset 0 1px 0 rgba(255,255,255,0.02)' }}>
      <span style={{ fontSize:10, color:C.muted, textTransform:'uppercase', letterSpacing:'0.1em', fontWeight:600 }}>{label}</span>
      <span style={{ fontSize:24, fontWeight:800, color, fontVariantNumeric:'tabular-nums', lineHeight:1, letterSpacing:'-0.02em' }}>{value}</span>
    </div>
  );
}

function BarRow({ label, value, max, color }) {
  const pct = Math.min(100, max > 0 ? (value/max)*100 : 0);
  return (
    <div style={{ display:'flex', alignItems:'center', gap:10, marginBottom:6 }}>
      <span style={{ width:130, fontSize:11, color:C.textDim, flexShrink:0 }}>{label}</span>
      <div style={{ flex:1, height:6, background:C.slate+'55', borderRadius:3, overflow:'hidden' }}>
        <div style={{ width:`${pct}%`, height:'100%', background:color, borderRadius:3, transition:'width 0.5s ease' }}/>
      </div>
      <span style={{ width:30, fontSize:11, color, textAlign:'right', fontVariantNumeric:'tabular-nums' }}>{value}</span>
    </div>
  );
}

function MiniGraph({ points, color, max=20, height=40 }) {
  if (points.length < 2) return <div style={{ height }}/>;
  const w=200, h=height, pts=points.slice(-30), step=w/(pts.length-1);
  const pathD=pts.map((v,i)=>`${i===0?'M':'L'}${(i*step).toFixed(1)},${(h-(Math.min(v,max)/max)*h*0.9-2).toFixed(1)}`).join(' ');
  return <svg width={w} height={h} style={{ display:'block' }}><path d={pathD} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>;
}

function LogEntry({ log }) {
  const colorMap = { storm_start:C.amber, storm_reject:C.red, storm_end:C.green, reset:C.cyan, startup:C.blue };
  const c = colorMap[log.type] || C.textDim;
  const t = log.ts ? new Date(log.ts).toLocaleTimeString() : '';
  return (
    <div style={{ display:'flex', gap:8, alignItems:'flex-start', padding:'5px 0', borderBottom:`1px solid ${C.cardBorder}` }}>
      <span style={{ fontSize:9, color:C.muted, flexShrink:0, paddingTop:2, fontVariantNumeric:'tabular-nums' }}>{t}</span>
      <span style={{ fontSize:11, color:c, lineHeight:1.4 }}>{log.message}</span>
    </div>
  );
}

const BACKEND = '';

export default function App() {
  const [metrics, setMetrics] = useState(null);
  const [connected, setConnected] = useState(false);
  const [stormConcurrency, setStormConcurrency] = useState(25);
  const [stormHoldMs, setStormHoldMs] = useState(600);
  const [stormPending, setStormPending] = useState({ direct:false, pooled:false });
  const connHistory = useRef([]);

  const fetchMetrics = useCallback(async () => {
    try { const r = await fetch(`${BACKEND}/api/metrics`); const d = await r.json(); setMetrics(d); } catch {}
  }, []);

  useEffect(() => {
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${wsProtocol}//${window.location.host}/ws`;
    const connect = () => {
      const ws = new WebSocket(wsUrl);
      ws.onopen = () => setConnected(true);
      ws.onclose = () => { setConnected(false); setTimeout(connect, 3000); };
      ws.onmessage = (e) => {
        try {
          const msg = JSON.parse(e.data);
          if (msg.type === 'init' || msg.type === 'metrics') {
            setMetrics(prev => ({ ...(prev||{}), ...msg.data }));
            if (msg.data.connectionStats) { connHistory.current.push(msg.data.connectionStats.total||0); if (connHistory.current.length>60) connHistory.current.shift(); }
          }
        } catch {}
      };
    };
    connect();
    fetchMetrics();
    const iv = setInterval(fetchMetrics, 3000);
    return () => clearInterval(iv);
  }, [fetchMetrics]);

  const triggerStorm = async (mode) => {
    setStormPending(p => ({ ...p, [mode]:true }));
    try { await fetch(`${BACKEND}/api/storm/${mode}`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ concurrency:stormConcurrency, holdMs:stormHoldMs }) }); } catch {}
    setTimeout(() => setStormPending(p => ({ ...p, [mode]:false })), 5000);
  };

  const resetMetrics = async () => { await fetch(`${BACKEND}/api/reset`, { method:'POST' }); setTimeout(fetchMetrics, 300); };

  const cs = metrics?.connectionStats || { active:0, idle:0, idleInTransaction:0, total:0, maxConnections:20 };
  const direct = metrics?.direct || {};
  const pooled = metrics?.pooled || {};
  const logs = metrics?.logs || [];
  const directRate = direct.totalRequests > 0 ? Math.round((direct.rejectedRequests/direct.totalRequests)*100) : 0;
  const pooledRate  = pooled.totalRequests  > 0 ? Math.round((pooled.rejectedRequests /pooled.totalRequests )*100) : 0;

  return (
    <div style={{ minHeight:'100vh', background:C.bg, color:C.text, fontFamily:"'JetBrains Mono','Fira Code','Cascadia Code',monospace", padding:'24px' }}>
      {/* Header */}
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:24 }}>
        <div>
          <div style={{ display:'flex', alignItems:'center', gap:10 }}>
            <div style={{ width:32, height:32, borderRadius:8, background:`linear-gradient(135deg,${C.blue},${C.cyan})`, display:'flex', alignItems:'center', justifyContent:'center', fontSize:16 }}>⚡</div>
            <span style={{ fontSize:20, fontWeight:700, letterSpacing:'-0.02em' }}>Connection Storm Monitor</span>
            <span style={{ fontSize:11, color:C.muted, background:C.surface, padding:'2px 8px', borderRadius:4, border:`1px solid ${C.cardBorder}` }}>Article 202</span>
          </div>
          <div style={{ fontSize:11, color:C.muted, marginTop:4, marginLeft:42 }}>Real-time pg_stat_activity · PgBouncer transaction mode demo · PostgreSQL max_connections=20</div>
        </div>
        <div style={{ display:'flex', alignItems:'center', gap:10 }}>
          <div style={{ width:8, height:8, borderRadius:'50%', background:connected?C.green:C.red, boxShadow:`0 0 8px ${connected?C.green:C.red}` }}/>
          <span style={{ fontSize:10, color:C.textDim }}>{connected?'LIVE':'CONNECTING'}</span>
          <button onClick={resetMetrics} style={{ background:'transparent', border:`1px solid ${C.slate}`, color:C.muted, padding:'6px 14px', borderRadius:6, cursor:'pointer', fontSize:11 }}>Reset</button>
        </div>
      </div>

      {/* Top 3 cards */}
      <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr 1fr', gap:24, marginBottom:24 }}>
        {/* Connection gauge */}
        <div style={{ background:'linear-gradient(145deg, rgba(20,28,48,0.95), rgba(15,22,40,0.9))', border:'1px solid rgba(30,45,74,0.6)', borderRadius:20, padding:'24px 28px', boxShadow:cs.total>=cs.maxConnections*0.9?`0 0 24px ${C.red}33`:'0 8px 32px rgba(0,0,0,0.4)' }}>
          <div style={{ fontSize:11, color:C.muted, textTransform:'uppercase', letterSpacing:'0.08em', marginBottom:16 }}>pg_stat_activity</div>
          <div style={{ display:'flex', gap:20, justifyContent:'center' }}>
            <ConnectionGauge value={cs.total} max={cs.maxConnections} label="Total" color={C.blue}/>
            <ConnectionGauge value={cs.active} max={cs.maxConnections} label="Active" color={C.cyan}/>
          </div>
          <div style={{ marginTop:12 }}>
            <BarRow label="active" value={cs.active} max={cs.maxConnections} color={C.cyan}/>
            <BarRow label="idle" value={cs.idle} max={cs.maxConnections} color={C.blue}/>
            <BarRow label="idle in txn" value={cs.idleInTransaction} max={cs.maxConnections} color={cs.idleInTransaction>1?C.amber:C.slateLight}/>
          </div>
          {cs.total>=cs.maxConnections*0.9&&<div style={{ marginTop:10, padding:'6px 10px', background:C.redGhost, border:`1px solid ${C.red}44`, borderRadius:6, fontSize:10, color:C.red, textAlign:'center' }}>⚠ APPROACHING MAX CONNECTIONS</div>}
        </div>

        {/* Direct metrics */}
        <div style={{ background:'linear-gradient(145deg, rgba(20,28,48,0.95), rgba(15,22,40,0.9))', border:`1px solid ${direct.rejectedRequests>0?C.red+'66':C.cardBorder}`, borderRadius:20, padding:'24px 28px', boxShadow:direct.rejectedRequests>0?`0 0 24px ${C.red}28`:'0 8px 32px rgba(0,0,0,0.4)' }}>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:16 }}>
            <span style={{ fontSize:11, color:C.muted, textTransform:'uppercase', letterSpacing:'0.08em' }}>Direct (No Pooler)</span>
            <span style={{ fontSize:9, padding:'2px 7px', borderRadius:4, background:direct.activeStorms>0?C.red+'33':C.greenGhost, color:direct.activeStorms>0?C.red:C.green, border:`1px solid ${direct.activeStorms>0?C.red+'44':C.green+'44'}` }}>{direct.activeStorms>0?'🌩 STORM ACTIVE':'● IDLE'}</span>
          </div>
          <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, marginBottom:12 }}>
            <StatPill label="Total Req" value={direct.totalRequests||0} color={C.text}/>
            <StatPill label="Rejected" value={direct.rejectedRequests||0} color={C.red} bg={C.redGhost}/>
            <StatPill label="Reject %" value={`${directRate}%`} color={directRate>10?C.red:C.green}/>
            <StatPill label="Avg Lat" value={`${direct.avgLatencyMs||0}ms`} color={C.cyan}/>
          </div>
          <div><div style={{ fontSize:9, color:C.muted, marginBottom:4 }}>conn count history</div><MiniGraph points={connHistory.current} color={direct.rejectedRequests>0?C.red:C.blue}/></div>
        </div>

        {/* Pooled metrics */}
        <div style={{ background:'linear-gradient(145deg, rgba(20,28,48,0.95), rgba(15,22,40,0.9))', border:`1px solid ${pooled.rejectedRequests>0?C.amber+'66':C.green+'44'}`, borderRadius:20, padding:'24px 28px', boxShadow:'0 8px 32px rgba(0,0,0,0.4)' }}>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:16 }}>
            <span style={{ fontSize:11, color:C.muted, textTransform:'uppercase', letterSpacing:'0.08em' }}>PgBouncer Pooled</span>
            <span style={{ fontSize:9, padding:'2px 7px', borderRadius:4, background:pooled.activeStorms>0?C.amber+'33':C.greenGhost, color:pooled.activeStorms>0?C.amber:C.green, border:`1px solid ${pooled.activeStorms>0?C.amber+'44':C.green+'44'}` }}>{pooled.activeStorms>0?'🌩 ABSORBING':'✓ STABLE'}</span>
          </div>
          <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr', gap:8, marginBottom:12 }}>
            <StatPill label="Total Req" value={pooled.totalRequests||0} color={C.text}/>
            <StatPill label="Rejected" value={pooled.rejectedRequests||0} color={C.green} bg={C.greenGhost}/>
            <StatPill label="Reject %" value={`${pooledRate}%`} color={pooledRate===0?C.green:C.amber}/>
            <StatPill label="Avg Lat" value={`${pooled.avgLatencyMs||0}ms`} color={C.cyan}/>
          </div>
          <div><div style={{ fontSize:9, color:C.muted, marginBottom:4 }}>conn count history</div><MiniGraph points={connHistory.current} color={C.green}/></div>
        </div>
      </div>

      {/* Storm Controls */}
      <div style={{ background:'linear-gradient(145deg, rgba(20,28,48,0.95), rgba(15,22,40,0.9))', border:'1px solid rgba(59,130,246,0.2)', borderRadius:20, padding:'28px 32px', marginBottom:24, boxShadow:'0 8px 32px rgba(0,0,0,0.4)' }}>
        <div style={{ fontSize:12, color:C.muted, textTransform:'uppercase', letterSpacing:'0.1em', marginBottom:20, fontWeight:700 }}>Storm Simulator</div>
        <div style={{ display:'flex', gap:24, alignItems:'flex-end', flexWrap:'wrap' }}>
          <div style={{ padding:'16px 20px', background:'rgba(0,0,0,0.2)', borderRadius:12, border:'1px solid rgba(59,130,246,0.2)' }}>
            <div style={{ fontSize:11, color:C.textDim, marginBottom:8, fontWeight:600 }}>Concurrent connections</div>
            <div style={{ display:'flex', alignItems:'center', gap:12 }}>
              <input type="range" min="5" max="60" value={stormConcurrency} onChange={e=>setStormConcurrency(+e.target.value)} style={{ width:160, accentColor:C.blue }}/>
              <span style={{ fontSize:18, fontWeight:700, color:stormConcurrency>20?C.red:C.blue, minWidth:30, fontVariantNumeric:'tabular-nums' }}>{stormConcurrency}</span>
            </div>
          </div>
          <div style={{ padding:'16px 20px', background:'rgba(0,0,0,0.2)', borderRadius:12, border:'1px solid rgba(59,130,246,0.2)' }}>
            <div style={{ fontSize:11, color:C.textDim, marginBottom:8, fontWeight:600 }}>Hold duration (ms)</div>
            <div style={{ display:'flex', alignItems:'center', gap:12 }}>
              <input type="range" min="100" max="3000" step="100" value={stormHoldMs} onChange={e=>setStormHoldMs(+e.target.value)} style={{ width:160, accentColor:C.amber }}/>
              <span style={{ fontSize:18, fontWeight:700, color:C.amber, minWidth:50, fontVariantNumeric:'tabular-nums' }}>{stormHoldMs}ms</span>
            </div>
          </div>
          <div style={{ display:'flex', gap:10 }}>
            <button onClick={()=>triggerStorm('direct')} disabled={stormPending.direct} style={{ background:stormPending.direct?C.slate:`linear-gradient(135deg,${C.redDim},${C.red})`, border:'none', color:'white', padding:'10px 20px', borderRadius:8, cursor:stormPending.direct?'not-allowed':'pointer', fontSize:12, fontWeight:600, boxShadow:stormPending.direct?'none':`0 4px 14px ${C.red}44`, opacity:stormPending.direct?0.6:1, transition:'all 0.2s' }}>
              {stormPending.direct?'⚡ Storming...':'🌩 Storm Direct'}
            </button>
            <button onClick={()=>triggerStorm('pooled')} disabled={stormPending.pooled} style={{ background:stormPending.pooled?C.slate:`linear-gradient(135deg,${C.blueDim},${C.blue})`, border:'none', color:'white', padding:'10px 20px', borderRadius:8, cursor:stormPending.pooled?'not-allowed':'pointer', fontSize:12, fontWeight:600, boxShadow:stormPending.pooled?'none':`0 4px 14px ${C.blue}44`, opacity:stormPending.pooled?0.6:1, transition:'all 0.2s' }}>
              {stormPending.pooled?'⚡ Absorbing...':'🛡 Storm Pooled'}
            </button>
          </div>
          <div style={{ fontSize:10, color:C.muted, padding:'8px 12px', background:C.surface, borderRadius:8, border:`1px solid ${C.cardBorder}`, maxWidth:260 }}>
            PostgreSQL max_connections=<span style={{ color:C.amber }}>20</span>. 
            Storm with {stormConcurrency} conns will {stormConcurrency>20?<span style={{ color:C.red }}> exceed capacity → rejections</span>:<span style={{ color:C.green }}> stay within limits</span>}
          </div>
        </div>
      </div>

      {/* Event log */}
      <div style={{ background:'linear-gradient(145deg, rgba(20,28,48,0.95), rgba(15,22,40,0.9))', border:'1px solid rgba(30,45,74,0.6)', borderRadius:20, padding:'24px 28px', boxShadow:'0 8px 32px rgba(0,0,0,0.4)' }}>
        <div style={{ fontSize:12, color:C.muted, textTransform:'uppercase', letterSpacing:'0.1em', marginBottom:16, fontWeight:700 }}>Event Stream</div>
        <div style={{ maxHeight:200, overflowY:'auto' }}>
          {logs.length===0
            ?<div style={{ fontSize:11, color:C.muted, padding:'8px 0' }}>No events yet. Trigger a storm to begin.</div>
            :logs.map((l,i)=><LogEntry key={i} log={l}/>)
          }
        </div>
      </div>

      <div style={{ marginTop:16, textAlign:'center', fontSize:10, color:C.muted }}>
        System Design Interview Roadmap · Article 202 · Section 8: Production Engineering
      </div>
    </div>
  );
}

