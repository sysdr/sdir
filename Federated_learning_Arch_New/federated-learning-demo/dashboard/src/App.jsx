import { useState, useEffect, useRef, useCallback } from 'react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from 'recharts'

/** Same-origin `/api` and `/ws`: nginx (production) or Vite proxy (dev) forward to FastAPI. */
const api = (path) => `/api${path.startsWith('/') ? path : `/${path}`}`
const wsUrl = () => {
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${proto}//${window.location.host}/ws`
}

const C_COLOR = { '1': '#3B82F6', '2': '#10B981', '3': '#F59E0B' }
const C_LABEL = { '1': 'Hospital A', '2': 'Mobile Fleet', '3': 'Edge Nodes' }
const S_COLOR = {
  waiting_for_clients: '#F59E0B', training: '#3B82F6',
  aggregating: '#8B5CF6', completed: '#10B981', connecting: '#9CA3AF',
}
const L_COLOR = { info:'#9CA3AF', success:'#10B981', warning:'#F59E0B', update:'#3B82F6', agg:'#8B5CF6' }

const Stat = ({ label, value, color }) => (
  <div style={{ background:'#fff', borderRadius:12, padding:'16px 20px', boxShadow:'0 2px 12px rgba(59,130,246,.07)' }}>
    <div style={{ fontSize:11, color:'#9CA3AF', textTransform:'uppercase', letterSpacing:.5, marginBottom:8 }}>{label}</div>
    <div style={{ fontSize:26, fontWeight:800, color }}>{value}</div>
  </div>
)

export default function App() {
  const [srv,   setSrv]    = useState({ round:0, status:'connecting' })
  const [mets,  setMets]   = useState([])
  const [regN,  setRegN]   = useState(0)
  const [logs,  setLogs]   = useState([{ msg:'Connecting to Federated Server…', type:'info', t: new Date().toLocaleTimeString() }])
  const [cuUpd, setCuUpd]  = useState({})
  const [pend,  setPend]   = useState([])
  const [demoBusy, setDemoBusy] = useState(false)
  const logsRef = useRef(null)
  const wsRef   = useRef(null)

  const addLog = useCallback((msg, type='info') => {
    const t = new Date().toLocaleTimeString()
    setLogs(prev => [...prev.slice(-99), { msg, type, t }])
  }, [])

  const mergeMet = useCallback((m) => {
    setMets(prev => {
      if (prev.find(x => x.round === m.round)) return prev
      return [...prev, m].sort((a,b) => a.round - b.round)
    })
  }, [])

  const runDemo = useCallback(async () => {
    setDemoBusy(true)
    try {
      const r = await fetch(api('/demo/reset'), { method: 'POST' })
      const body = await r.json().catch(() => ({}))
      if (!r.ok) {
        addLog(`Run demo failed: ${body.error || body.detail || r.statusText}`, 'warning')
        return
      }
      setMets(Array.isArray(body.metrics) ? body.metrics : [])
      setSrv(p => ({ ...p, round: body.round ?? 0, status: body.status || 'waiting_for_clients' }))
      setCuUpd({})
      setPend([])
      setRegN(0)
      addLog('Demo reset — training will resume when all three clients re-register.', 'success')
    } catch (e) {
      addLog(`Run demo failed: ${e.message}`, 'warning')
    } finally {
      setDemoBusy(false)
    }
  }, [addLog])

  useEffect(() => {
    fetch(api('/metrics')).then(r=>r.json()).then(d => {
      setMets(d.metrics || [])
      setSrv(p => ({ ...p, round: d.round, status: d.status || 'unknown' }))
    }).catch(()=>{})

    const connect = () => {
      const ws = new WebSocket(wsUrl())
      wsRef.current = ws

      ws.onopen  = () => addLog('WebSocket connected to aggregation server', 'success')
      ws.onerror = () => ws.close()
      ws.onclose = () => { addLog('Disconnected — reconnecting in 3 s…', 'warning'); setTimeout(connect, 3000) }

      ws.onmessage = (e) => {
        let d; try { d = JSON.parse(e.data) } catch { return }

        if (d.type === 'init' || d.type === 'demo_reset') {
          setMets(d.metrics || [])
          setSrv(p => ({ ...p, round: d.round, status: d.status }))
          setCuUpd({})
          setPend([])
          if (d.type === 'demo_reset') {
            addLog(`Demo reset: round=${d.round} · ${d.status} — clients re-joining.`, 'info')
          } else {
            addLog(`Server state: round=${d.round}  status=${d.status}`, 'info')
          }
        }
        if (d.type === 'training_started') {
          addLog(`All clients joined. Training started! (${d.clients.join(', ')})`, 'success')
          setSrv(p => ({ ...p, status:'training' }))
        }
        if (d.type === 'update_received') {
          const acc = (d.local_accuracy * 100).toFixed(1)
          addLog(`Client ${d.client_id} → round ${d.round} update  local_acc=${acc}%  (${d.received}/${d.needed})`, 'update')
          setCuUpd(p => ({ ...p, [d.client_id]: d }))
        }
        if (d.type === 'aggregation_complete') {
          const acc = (d.global_accuracy * 100).toFixed(1)
          addLog(`⚡ FedAvg round ${d.prev_round} complete → global_acc=${acc}%`, 'agg')
          mergeMet({ round: d.prev_round, global_accuracy: d.global_accuracy, client_accuracies: d.client_accuracies })
          setCuUpd({})
          setSrv(p => ({ ...p, round: d.round, status: d.status }))
        }
        if (d.type === 'ping') {
          setSrv(p => ({ ...p, round: d.round, status: d.status }))
          setPend(d.pending || [])
        }
      }
    }
    connect()
    return () => wsRef.current?.close()
  }, [addLog, mergeMet])

  useEffect(() => {
    const poll = () => {
      fetch(api('/metrics')).then(r => r.json()).then(d => {
        setMets(Array.isArray(d.metrics) ? d.metrics : [])
        setSrv(p => ({ ...p, round: d.round ?? p.round, status: d.status ?? p.status }))
      }).catch(() => {})
      fetch(api('/status')).then(r => r.json()).then(s => {
        setRegN(Array.isArray(s.registered_clients) ? s.registered_clients.length : 0)
      }).catch(() => {})
    }
    poll()
    const id = setInterval(poll, 2500)
    return () => clearInterval(id)
  }, [])

  useEffect(() => {
    logsRef.current?.scrollTo({ top: logsRef.current.scrollHeight, behavior:'smooth' })
  }, [logs])

  const last = mets[mets.length - 1]
  const chartData = mets.map(m => ({
    round:    m.round,
    'Global': +(m.global_accuracy * 100).toFixed(1),
    'Client 1': m.client_accuracies?.['1'] != null ? +(m.client_accuracies['1']*100).toFixed(1) : undefined,
    'Client 2': m.client_accuracies?.['2'] != null ? +(m.client_accuracies['2']*100).toFixed(1) : undefined,
    'Client 3': m.client_accuracies?.['3'] != null ? +(m.client_accuracies['3']*100).toFixed(1) : undefined,
  }))

  return (
    <div style={{ fontFamily:"'Inter',system-ui,sans-serif", background:'#EFF6FF', minHeight:'100vh', padding:24 }}>

      {/* ── Header ── */}
      <div style={{ background:'#fff', borderRadius:16, padding:'18px 28px', marginBottom:20,
                    boxShadow:'0 4px 24px rgba(59,130,246,.12)', display:'flex', justifyContent:'space-between', alignItems:'center' }}>
        <div>
          <div style={{ fontSize:20, fontWeight:800, color:'#1E3A5F' }}>🧠 Federated Learning Dashboard</div>
          <div style={{ fontSize:12, color:'#6B7280', marginTop:3 }}>FedAvg · 3 Clients · Non-IID Data · Zero Raw-Data Transfer</div>
        </div>
        <div style={{ display:'flex', gap:16, alignItems:'center' }}>
          <button
            type="button"
            onClick={runDemo}
            disabled={demoBusy}
            style={{
              cursor: demoBusy ? 'wait' : 'pointer',
              border: 'none',
              borderRadius: 8,
              padding: '10px 18px',
              fontSize: 13,
              fontWeight: 700,
              color: '#fff',
              background: demoBusy ? '#9CA3AF' : '#2563EB',
              boxShadow: demoBusy ? 'none' : '0 2px 10px rgba(37,99,235,.35)',
            }}
          >
            {demoBusy ? 'Starting…' : 'Run demo'}
          </button>
          <div style={{ textAlign:'right' }}>
            <div style={{ fontSize:10, color:'#9CA3AF', textTransform:'uppercase', letterSpacing:1 }}>Round</div>
            <div style={{ fontSize:32, fontWeight:900, color:'#1D4ED8', lineHeight:1 }}>
              {srv.round}<span style={{ fontSize:16, color:'#93C5FD' }}> / 15</span>
            </div>
          </div>
          <div style={{ background: S_COLOR[srv.status]||'#9CA3AF', color:'#fff', borderRadius:8,
                        padding:'8px 16px', fontSize:12, fontWeight:700, textTransform:'uppercase', letterSpacing:.5 }}>
            {(srv.status||'').replace(/_/g,' ')}
          </div>
        </div>
      </div>

      {/* ── Stats Row ── */}
      <div style={{ display:'grid', gridTemplateColumns:'repeat(4,1fr)', gap:16, marginBottom:20 }}>
        <Stat label="Global Accuracy"  value={last ? `${(last.global_accuracy*100).toFixed(1)}%` : '—'} color="#1D4ED8" />
        <Stat label="Rounds Complete"  value={mets.length > 0 ? mets.length : '—'} color="#10B981" />
        <Stat label="Active Clients"   value={regN > 0 ? regN : '—'} color="#F59E0B" />
        <Stat label="Algorithm"        value="FedAvg"      color="#8B5CF6" />
      </div>

      {/* ── Client Cards ── */}
      <div style={{ display:'grid', gridTemplateColumns:'repeat(3,1fr)', gap:16, marginBottom:20 }}>
        {['1','2','3'].map(cid => {
          const upd = cuUpd[cid]
          const acc = last?.client_accuracies?.[cid]
          return (
            <div key={cid} style={{ background:'#fff', borderRadius:12, padding:'18px 22px',
                                    boxShadow:'0 2px 12px rgba(59,130,246,.07)', borderLeft:`4px solid ${C_COLOR[cid]}` }}>
              <div style={{ display:'flex', justifyContent:'space-between', alignItems:'flex-start' }}>
                <div>
                  <div style={{ fontSize:14, fontWeight:700, color:'#1E3A5F' }}>Client {cid}</div>
                  <div style={{ fontSize:11, color:'#9CA3AF' }}>{C_LABEL[cid]}</div>
                </div>
                <div style={{ width:12, height:12, borderRadius:'50%', marginTop:4, transition:'all .3s',
                              background: upd ? '#10B981' : '#E5E7EB',
                              boxShadow:  upd ? '0 0 8px #10B98155' : 'none' }} />
              </div>
              <div style={{ marginTop:14 }}>
                <div style={{ fontSize:11, color:'#9CA3AF' }}>Local Accuracy (last round)</div>
                <div style={{ fontSize:26, fontWeight:800, color:C_COLOR[cid] }}>
                  {acc != null ? `${(acc*100).toFixed(1)}%` : '—'}
                </div>
              </div>
              <div style={{ marginTop:8, fontSize:11, color: upd ? '#10B981' : '#9CA3AF' }}>
                {upd ? `✓ Round ${upd.round} update submitted` : 'Awaiting local training…'}
              </div>
              {pend.includes(cid) && !upd && (
                <div style={{ marginTop:6, fontSize:11, color:'#3B82F6' }}>⏳ Training in progress…</div>
              )}
            </div>
          )
        })}
      </div>

      {/* ── Chart + Log ── */}
      <div style={{ display:'grid', gridTemplateColumns:'3fr 2fr', gap:20 }}>
        <div style={{ background:'#fff', borderRadius:12, padding:'22px 24px', boxShadow:'0 2px 12px rgba(59,130,246,.07)' }}>
          <div style={{ fontSize:14, fontWeight:700, color:'#1E3A5F', marginBottom:18 }}>Model Accuracy Over Rounds</div>
          {chartData.length > 0 ? (
            <ResponsiveContainer width="100%" height={260}>
              <LineChart data={chartData} margin={{ top:5, right:20, left:-10, bottom:22 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#F3F4F6" />
                <XAxis dataKey="round" tick={{ fontSize:11 }}
                       label={{ value:'Round', position:'insideBottom', offset:-10, fontSize:11, fill:'#9CA3AF' }} />
                <YAxis domain={[0,100]} tickFormatter={v=>`${v}%`} tick={{ fontSize:11 }} />
                <Tooltip formatter={v => v!=null ? `${Number(v).toFixed(1)}%` : 'N/A'} />
                <Legend wrapperStyle={{ fontSize:11 }} />
                <Line type="monotone" dataKey="Global"   stroke="#1D4ED8" strokeWidth={3} dot={{ r:3 }} name="Global (FedAvg)" />
                <Line type="monotone" dataKey="Client 1" stroke="#3B82F6" strokeWidth={1.5} strokeDasharray="5 3" dot={false} />
                <Line type="monotone" dataKey="Client 2" stroke="#10B981" strokeWidth={1.5} strokeDasharray="5 3" dot={false} />
                <Line type="monotone" dataKey="Client 3" stroke="#F59E0B" strokeWidth={1.5} strokeDasharray="5 3" dot={false} />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <div style={{ height:260, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', color:'#9CA3AF', gap:12 }}>
              <div style={{ fontSize:36 }}>⏳</div>
              <div style={{ fontSize:13 }}>Waiting for first round to complete…</div>
              <div style={{ fontSize:11 }}>Clients are registering and training locally</div>
            </div>
          )}
        </div>

        <div style={{ background:'#fff', borderRadius:12, padding:'22px 24px', boxShadow:'0 2px 12px rgba(59,130,246,.07)' }}>
          <div style={{ fontSize:14, fontWeight:700, color:'#1E3A5F', marginBottom:14 }}>Activity Log</div>
          <div ref={logsRef} style={{ height:280, overflowY:'auto', fontSize:11.5 }}>
            {logs.map((l,i) => (
              <div key={i} style={{ display:'flex', gap:8, padding:'5px 0', borderBottom:'1px solid #F9FAFB' }}>
                <span style={{ color:'#D1D5DB', flexShrink:0, fontSize:10.5, paddingTop:1 }}>{l.t}</span>
                <span style={{ color: L_COLOR[l.type]||'#374151' }}>{l.msg}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── Footer ── */}
      <div style={{ marginTop:16, textAlign:'center', fontSize:11, color:'#9CA3AF' }}>
        Federated Learning Demo · FedAvg · Non-IID Logistic Regression · 2-Feature Synthetic Data
      </div>
    </div>
  )
}
