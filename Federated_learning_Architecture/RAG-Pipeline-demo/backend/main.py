import os
import json
import time
import math
import glob
import threading
import numpy as np
import faiss
from pathlib import Path
from typing import List, Optional
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

# ── Config ───────────────────────────────────────────────────
DOCS_PATH  = os.getenv("DOCS_PATH", "/app/docs")
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
TOP_K      = int(os.getenv("TOP_K", "5"))
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "150"))  # tokens approx (words)
OVERLAP    = int(os.getenv("OVERLAP", "20"))

app = FastAPI(title="RAG Pipeline API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

# ── State ────────────────────────────────────────────────────
model: Optional[SentenceTransformer] = None
index: Optional[faiss.IndexFlatIP]   = None
chunks: List[dict] = []
ws_clients: List[WebSocket] = []
index_ready = threading.Event()
index_stats = {
    "status": "loading",
    "num_docs": 0,
    "num_chunks": 0,
    "model": MODEL_NAME,
    "dim": 0,
    "build_time_ms": 0,
}

# ── Chunking ─────────────────────────────────────────────────
def chunk_text(text: str, source: str) -> List[dict]:
    words = text.split()
    result = []
    step = CHUNK_SIZE - OVERLAP
    for i in range(0, len(words), step):
        window = words[i : i + CHUNK_SIZE]
        if len(window) < 10:
            continue
        result.append({
            "text": " ".join(window),
            "source": source,
            "chunk_idx": len(result),
            "word_start": i,
        })
    return result

# ── Build index ───────────────────────────────────────────────
def build_index():
    global model, index, chunks, index_stats
    broadcast_sync({"event": "status", "message": "Loading embedding model…", "status": "loading"})

    t0 = time.time()
    model = SentenceTransformer(MODEL_NAME)
    dim = model.get_sentence_embedding_dimension()

    broadcast_sync({"event": "status", "message": "Ingesting documents…", "status": "ingesting"})

    doc_files = glob.glob(f"{DOCS_PATH}/*.txt")
    all_chunks = []
    for path in sorted(doc_files):
        name = Path(path).stem
        text = open(path).read().strip()
        doc_chunks = chunk_text(text, name)
        all_chunks.extend(doc_chunks)

    broadcast_sync({
        "event": "status",
        "message": f"Embedding {len(all_chunks)} chunks…",
        "status": "embedding"
    })

    texts = [c["text"] for c in all_chunks]
    embeddings = model.encode(texts, batch_size=32, normalize_embeddings=True, show_progress_bar=False)
    embeddings = embeddings.astype(np.float32)

    # FAISS inner product = cosine similarity (vectors are L2-normalised)
    idx = faiss.IndexFlatIP(dim)
    idx.add(embeddings)

    elapsed = int((time.time() - t0) * 1000)
    chunks = all_chunks
    index  = idx
    index_stats = {
        "status": "ready",
        "num_docs": len(doc_files),
        "num_chunks": len(all_chunks),
        "model": MODEL_NAME,
        "dim": dim,
        "build_time_ms": elapsed,
    }
    index_ready.set()
    broadcast_sync({
        "event": "ready",
        "message": f"Index ready — {len(all_chunks)} chunks from {len(doc_files)} docs ({elapsed}ms)",
        "stats": index_stats,
    })

# ── WebSocket broadcast ───────────────────────────────────────
def broadcast_sync(payload: dict):
    msg = json.dumps(payload)
    dead = []
    for ws in ws_clients:
        try:
            import asyncio
            loop = asyncio.new_event_loop()
            loop.run_until_complete(ws.send_text(msg))
            loop.close()
        except Exception:
            dead.append(ws)
    for ws in dead:
        ws_clients.remove(ws)

# ── Startup ───────────────────────────────────────────────────
@app.on_event("startup")
def on_startup():
    t = threading.Thread(target=build_index, daemon=True)
    t.start()

# ── Routes ────────────────────────────────────────────────────
class SearchRequest(BaseModel):
    query: str
    top_k: int = TOP_K

class ChunkResult(BaseModel):
    text: str
    source: str
    chunk_idx: int
    score: float

class SearchResponse(BaseModel):
    query: str
    results: List[ChunkResult]
    context: str
    latency_ms: float

@app.get("/health")
def health():
    return {"status": index_stats["status"], "stats": index_stats}

@app.post("/search", response_model=SearchResponse)
def search(req: SearchRequest):
    if not index_ready.is_set():
        raise HTTPException(503, detail="Index not ready yet")

    t0 = time.time()
    qvec = model.encode([req.query], normalize_embeddings=True).astype(np.float32)
    scores, ids = index.search(qvec, req.top_k)

    results = []
    for score, idx_id in zip(scores[0], ids[0]):
        if idx_id < 0:
            continue
        c = chunks[idx_id]
        results.append(ChunkResult(
            text=c["text"],
            source=c["source"],
            chunk_idx=c["chunk_idx"],
            score=float(score),
        ))

    # Assemble RAG context exactly as it would be injected into an LLM prompt
    context_parts = []
    for i, r in enumerate(results, 1):
        context_parts.append(f"[Source {i}: {r.source}]\n{r.text}")
    context = "\n\n".join(context_parts)

    latency = (time.time() - t0) * 1000
    return SearchResponse(
        query=req.query,
        results=results,
        context=context,
        latency_ms=round(latency, 2),
    )

@app.get("/chunks")
def list_chunks():
    if not index_ready.is_set():
        raise HTTPException(503, detail="Index not ready yet")
    sources = {}
    for c in chunks:
        sources.setdefault(c["source"], 0)
        sources[c["source"]] += 1
    return {"total": len(chunks), "by_source": sources}

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    ws_clients.append(ws)
    try:
        # Send current state immediately on connect
        await ws.send_text(json.dumps({
            "event": "status" if not index_ready.is_set() else "ready",
            "message": "Connected to RAG Pipeline",
            "stats": index_stats,
        }))
        while True:
            await ws.receive_text()  # keep alive
    except WebSocketDisconnect:
        if ws in ws_clients:
            ws_clients.remove(ws)
