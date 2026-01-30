from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer
import redis
import json
import time
import hashlib
import numpy as np

app = Flask(__name__)

# Initialize models (Fast and Heavy tiers)
print("Loading models...")
fast_model = SentenceTransformer('all-MiniLM-L6-v2')  # Fast: 22M params
heavy_model = SentenceTransformer('all-mpnet-base-v2')  # Heavy: 110M params
print("Models loaded successfully")

# Redis connection
r = redis.from_url('redis://redis:6379', decode_responses=False)

# Batch processing queues
fast_batch = []
heavy_batch = []
BATCH_SIZE_FAST = 32
BATCH_SIZE_HEAVY = 8
BATCH_TIMEOUT = 0.01  # 10ms

def get_cache_key(text, model_type):
    return f"emb:{model_type}:{hashlib.md5(text.encode()).hexdigest()}"

def get_embedding(text, model_type='fast'):
    """Get embedding with caching"""
    cache_key = get_cache_key(text, model_type)
    
    # Check cache
    cached = r.get(cache_key)
    if cached:
        return {
            'embedding': np.frombuffer(cached, dtype=np.float32).tolist(),
            'cached': True,
            'model': model_type
        }
    
    # Compute embedding
    start = time.time()
    model = fast_model if model_type == 'fast' else heavy_model
    embedding = model.encode(text, convert_to_numpy=True)
    latency = (time.time() - start) * 1000
    
    # Cache for 1 hour
    r.setex(cache_key, 3600, embedding.tobytes())
    
    return {
        'embedding': embedding.tolist(),
        'cached': False,
        'model': model_type,
        'latency_ms': round(latency, 2)
    }

def compute_similarity(emb1, emb2):
    """Cosine similarity"""
    a = np.array(emb1)
    b = np.array(emb2)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'}), 200

@app.route('/embed', methods=['POST'])
def embed():
    """Generate embeddings with intelligent routing"""
    data = request.json
    text = data.get('text', '')
    force_model = data.get('model', None)
    
    # Smart routing: complex queries go to heavy model
    word_count = len(text.split())
    is_complex = word_count > 20 or '?' in text or any(word in text.lower() for word in ['compare', 'analyze', 'explain'])
    
    model_type = force_model or ('heavy' if is_complex else 'fast')
    
    result = get_embedding(text, model_type)
    result['routed_by'] = 'complexity_analysis' if not force_model else 'explicit'
    result['text_length'] = len(text)
    
    return jsonify(result)

@app.route('/similarity', methods=['POST'])
def similarity():
    """Compute similarity between two texts"""
    data = request.json
    text1 = data.get('text1', '')
    text2 = data.get('text2', '')
    model = data.get('model', 'fast')
    
    start = time.time()
    
    emb1_result = get_embedding(text1, model)
    emb2_result = get_embedding(text2, model)
    
    sim_score = compute_similarity(emb1_result['embedding'], emb2_result['embedding'])
    
    total_latency = (time.time() - start) * 1000
    
    return jsonify({
        'similarity': round(sim_score, 4),
        'text1_cached': emb1_result['cached'],
        'text2_cached': emb2_result['cached'],
        'model': model,
        'total_latency_ms': round(total_latency, 2),
        'cache_hit_rate': (emb1_result['cached'] + emb2_result['cached']) / 2
    })

@app.route('/batch/embed', methods=['POST'])
def batch_embed():
    """Batch embedding endpoint"""
    data = request.json
    texts = data.get('texts', [])
    model_type = data.get('model', 'fast')
    
    start = time.time()
    results = []
    cache_hits = 0
    
    for text in texts:
        result = get_embedding(text, model_type)
        results.append(result)
        if result['cached']:
            cache_hits += 1
    
    total_latency = (time.time() - start) * 1000
    
    return jsonify({
        'results': results,
        'batch_size': len(texts),
        'cache_hit_rate': cache_hits / len(texts) if texts else 0,
        'total_latency_ms': round(total_latency, 2),
        'avg_latency_per_item': round(total_latency / len(texts), 2) if texts else 0
    })

@app.route('/stats', methods=['GET'])
def stats():
    """Get cache statistics"""
    info = r.info('stats')
    return jsonify({
        'total_keys': r.dbsize(),
        'cache_hits': info.get('keyspace_hits', 0),
        'cache_misses': info.get('keyspace_misses', 0),
        'hit_rate': round(info.get('keyspace_hits', 0) / max(info.get('keyspace_hits', 0) + info.get('keyspace_misses', 0), 1), 2)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
