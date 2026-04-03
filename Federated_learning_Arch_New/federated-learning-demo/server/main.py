#!/usr/bin/env python3
"""
Federated Learning Server
Implements FedAvg aggregation — sees model updates, never raw client data.
"""
import asyncio, json, logging, time
from typing import Dict, List
import numpy as np
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(title="Federated Learning Server")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ── Config ────────────────────────────────────────────────────────────────────
NUM_FEATURES = 2
NUM_CLIENTS  = 3
MAX_ROUNDS   = 15

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -500.0, 500.0)))

def evaluate(weights, X, y):
    w = np.array(weights, dtype=float)
    Xa = np.column_stack([X, np.ones(len(X))])
    return float(np.mean((sigmoid(Xa @ w) >= 0.5).astype(int) == y))

# Global held-out test set (union of all three client distributions)
np.random.seed(0)
_TX = np.vstack([
    np.random.randn(40, 2) + [ 2.0,  2.0],   # C1 positive
    np.random.randn(40, 2) + [-2.0, -2.0],   # C1 negative
    np.random.randn(40, 2) + [-1.0,  2.5],   # C2 positive
    np.random.randn(40, 2) + [ 2.0, -1.0],   # C2 negative
    np.random.randn(40, 2) + [ 0.5, -2.0],   # C3 positive
    np.random.randn(40, 2) + [-1.5,  1.5],   # C3 negative
])
_TY = np.array([1]*120 + [0]*120)

# ── State ─────────────────────────────────────────────────────────────────────
class State:
    def __init__(self):
        self.round: int = 0
        self.weights: List[float] = [0.0] * (NUM_FEATURES + 1)
        self.updates: Dict[str, dict] = {}
        self.metrics: List[dict] = []
        self.status: str = "waiting_for_clients"
        self.registered: set = set()

state = State()
ws_pool: List[WebSocket] = []

async def broadcast(payload: dict):
    dead = []
    for ws in ws_pool:
        try:
            await ws.send_text(json.dumps(payload))
        except Exception:
            dead.append(ws)
    for ws in dead:
        if ws in ws_pool:
            ws_pool.remove(ws)

def fedavg(updates: Dict[str, dict]) -> List[float]:
    """Weighted average of client weights by local dataset size."""
    total = sum(u["n"] for u in updates.values())
    agg = np.zeros(NUM_FEATURES + 1, dtype=float)
    for u in updates.values():
        agg += (u["n"] / total) * np.array(u["w"], dtype=float)
    return agg.tolist()

async def aggregate():
    state.status = "aggregating"
    new_w  = fedavg(state.updates)
    g_acc  = evaluate(new_w, _TX, _TY)
    c_accs = {cid: u["acc"] for cid, u in state.updates.items()}

    state.metrics.append({
        "round": state.round,
        "global_accuracy": round(g_acc, 4),
        "client_accuracies": c_accs,
        "timestamp": time.time(),
    })
    state.weights = new_w
    state.round  += 1
    state.updates = {}
    state.status  = "completed" if state.round > MAX_ROUNDS else "training"

    logger.info(f"Round {state.round-1} done — global_acc={g_acc:.4f}  next_round={state.round}")
    await broadcast({
        "type": "aggregation_complete",
        "round": state.round,
        "prev_round": state.round - 1,
        "global_accuracy": g_acc,
        "client_accuracies": c_accs,
        "status": state.status,
    })

# ── Pydantic models ───────────────────────────────────────────────────────────
class Reg(BaseModel):
    client_id: str
    n_samples: int
    distribution: str

class Upd(BaseModel):
    client_id: str
    round: int
    weights: List[float]
    n_samples: int
    local_accuracy: float

# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/status")
async def status():
    return {
        "round": state.round, "status": state.status,
        "registered_clients": sorted(state.registered),
        "pending_updates": sorted(state.updates.keys()),
        "total_rounds": MAX_ROUNDS,
    }

@app.post("/register")
async def register(reg: Reg):
    if state.status != "waiting_for_clients":
        return JSONResponse(
            status_code=409,
            content={
                "error": "Registration only open when waiting for clients (use POST /demo/reset).",
                "status": state.status,
                "round": state.round,
            },
        )
    state.registered.add(reg.client_id)
    if len(state.registered) >= NUM_CLIENTS and state.status == "waiting_for_clients":
        state.status = "training"
        logger.info("All clients registered — training starts.")
        await broadcast({"type": "training_started", "clients": sorted(state.registered)})
    return {"current_round": state.round, "status": state.status}

@app.get("/model")
async def get_model():
    return {"round": state.round, "weights": state.weights, "status": state.status, "max_rounds": MAX_ROUNDS}

@app.post("/update")
async def receive_update(upd: Upd):
    if upd.round != state.round:
        return {"error": f"Stale: got round {upd.round}, current is {state.round}"}
    if upd.client_id in state.updates:
        return {"error": "Duplicate update for this round"}

    state.updates[upd.client_id] = {"w": upd.weights, "n": upd.n_samples, "acc": upd.local_accuracy}
    logger.info(f"Update from {upd.client_id} round={upd.round} acc={upd.local_accuracy:.4f} ({len(state.updates)}/{NUM_CLIENTS})")

    await broadcast({
        "type": "update_received",
        "client_id": upd.client_id,
        "round": upd.round,
        "local_accuracy": upd.local_accuracy,
        "received": len(state.updates),
        "needed": NUM_CLIENTS,
    })

    if len(state.updates) >= NUM_CLIENTS:
        await aggregate()
    return {"accepted": True, "updates_received": len(state.updates)}

@app.get("/metrics")
async def metrics():
    return {"metrics": state.metrics, "round": state.round, "status": state.status}

@app.post("/demo/reset")
async def demo_reset():
    """Clear training state so clients can register again (dashboard 'Run demo' button)."""
    global state
    state = State()
    logger.info("Demo reset — state cleared, waiting for clients.")
    await broadcast({
        "type": "demo_reset",
        "round": state.round,
        "status": state.status,
        "metrics": state.metrics,
    })
    return {"ok": True, "round": state.round, "status": state.status, "metrics": state.metrics}

@app.websocket("/ws")
async def ws_handler(ws: WebSocket):
    await ws.accept()
    ws_pool.append(ws)
    await ws.send_text(json.dumps({
        "type": "init", "round": state.round, "status": state.status, "metrics": state.metrics
    }))
    try:
        while True:
            await asyncio.sleep(2)
            await ws.send_text(json.dumps({
                "type": "ping", "round": state.round,
                "status": state.status, "pending": sorted(state.updates.keys()),
            }))
    except (WebSocketDisconnect, Exception):
        if ws in ws_pool:
            ws_pool.remove(ws)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
