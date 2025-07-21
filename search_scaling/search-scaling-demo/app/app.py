import os
import time
import json
import logging
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_cors import CORS
import redis
import psycopg2
from psycopg2.extras import RealDictCursor
from elasticsearch import Elasticsearch
import pandas as pd
import numpy as np
from faker import Faker
import threading
from functools import wraps

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/search_app.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configuration
ELASTICSEARCH_URL = os.getenv('ELASTICSEARCH_URL', 'http://localhost:9200')
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379')
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://searchuser:searchpass@localhost:5432/searchdb')

# Initialize connections
es = Elasticsearch([ELASTICSEARCH_URL])
redis_client = redis.from_url(REDIS_URL, decode_responses=True)
fake = Faker()

# Search performance metrics
search_metrics = {
    'database_searches': 0,
    'elasticsearch_searches': 0,
    'cached_searches': 0,
    'total_search_time': 0,
    'average_results_per_query': 0
}

def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

def timing_decorator(search_type):
    """Decorator to measure search performance"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            result = func(*args, **kwargs)
            end_time = time.time()
            
            # Update metrics
            search_metrics[f'{search_type}_searches'] += 1
            search_metrics['total_search_time'] += (end_time - start_time)
            if isinstance(result, list):
                search_metrics['average_results_per_query'] = (
                    search_metrics['average_results_per_query'] + len(result)
                ) / 2
            
            logger.info(f"{search_type} search took {end_time - start_time:.3f}s")
            return result
        return wrapper
    return decorator

@timing_decorator('database')
def search_database(query, limit=20):
    """Search using PostgreSQL full-text search"""
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT id, title, content, category, 
                           ts_rank(to_tsvector('english', title || ' ' || content), 
                                  plainto_tsquery('english', %s)) as rank
                    FROM documents 
                    WHERE to_tsvector('english', title || ' ' || content) @@ plainto_tsquery('english', %s)
                    ORDER BY rank DESC, created_at DESC
                    LIMIT %s
                """, (query, query, limit))
                results = cur.fetchall()
                return [dict(row) for row in results]
    except Exception as e:
        logger.error(f"Database search error: {e}")
        return []

@timing_decorator('elasticsearch')
def search_elasticsearch(query, limit=20):
    """Search using Elasticsearch"""
    try:
        search_body = {
            "query": {
                "multi_match": {
                    "query": query,
                    "fields": ["title^2", "content", "category"],
                    "type": "best_fields",
                    "fuzziness": "AUTO"
                }
            },
            "highlight": {
                "fields": {
                    "title": {},
                    "content": {}
                }
            },
            "size": limit
        }
        
        response = es.search(index="documents", body=search_body)
        results = []
        
        for hit in response['hits']['hits']:
            result = {
                'id': hit['_source']['id'],
                'title': hit['_source']['title'],
                'content': hit['_source']['content'],
                'category': hit['_source']['category'],
                'score': hit['_score']
            }
            if 'highlight' in hit:
                result['highlight'] = hit['highlight']
            results.append(result)
        
        return results
    except Exception as e:
        logger.error(f"Elasticsearch search error: {e}")
        return []

@timing_decorator('cached')
def search_cached(query, limit=20):
    """Search using Redis cache"""
    try:
        cache_key = f"search:{query}:{limit}"
        cached_result = redis_client.get(cache_key)
        
        if cached_result:
            return json.loads(cached_result)
        
        # If not cached, search elasticsearch and cache result
        results = search_elasticsearch(query, limit)
        redis_client.setex(cache_key, 300, json.dumps(results, default=str))  # Cache for 5 minutes
        return results
    except Exception as e:
        logger.error(f"Cached search error: {e}")
        return search_elasticsearch(query, limit)

def create_sample_data():
    """Create sample documents for testing"""
    logger.info("Creating sample data...")
    
    # Create database documents
    documents = []
    categories = ['Technology', 'Science', 'Business', 'Health', 'Education', 'Entertainment']
    
    for i in range(1000):
        doc = {
            'title': fake.sentence(nb_words=6),
            'content': fake.text(max_nb_chars=500),
            'category': fake.random_element(categories),
            'tags': [fake.word() for _ in range(3)]
        }
        documents.append(doc)
    
    # Insert into PostgreSQL
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                for doc in documents:
                    cur.execute("""
                        INSERT INTO documents (title, content, category, tags)
                        VALUES (%s, %s, %s, %s)
                    """, (doc['title'], doc['content'], doc['category'], doc['tags']))
                conn.commit()
    except Exception as e:
        logger.error(f"Error inserting sample data: {e}")
    
    # Index in Elasticsearch
    try:
        # Create index if it doesn't exist
        if not es.indices.exists(index="documents"):
            mapping = {
                "mappings": {
                    "properties": {
                        "id": {"type": "integer"},
                        "title": {"type": "text", "analyzer": "english"},
                        "content": {"type": "text", "analyzer": "english"},
                        "category": {"type": "keyword"},
                        "tags": {"type": "keyword"},
                        "created_at": {"type": "date"}
                    }
                }
            }
            es.indices.create(index="documents", body=mapping)
        
        # Index documents
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM documents")
                db_docs = cur.fetchall()
                
                for doc in db_docs:
                    es.index(
                        index="documents",
                        id=doc['id'],
                        body={
                            'id': doc['id'],
                            'title': doc['title'],
                            'content': doc['content'],
                            'category': doc['category'],
                            'tags': doc['tags'],
                            'created_at': doc['created_at']
                        }
                    )
        
        es.indices.refresh(index="documents")
        logger.info("Sample data created successfully")
    except Exception as e:
        logger.error(f"Error indexing sample data: {e}")

@app.route('/')
def index():
    """Main page"""
    return render_template('index.html')

@app.route('/static/<path:filename>')
def static_files(filename):
    return send_from_directory('static', filename)

@app.route('/search')
def search():
    """Search endpoint"""
    query = request.args.get('q', '')
    search_type = request.args.get('type', 'elasticsearch')
    limit = int(request.args.get('limit', 20))
    
    if not query:
        return jsonify({'error': 'Query parameter is required'}), 400
    
    start_time = time.time()
    
    if search_type == 'database':
        results = search_database(query, limit)
    elif search_type == 'cached':
        results = search_cached(query, limit)
    else:
        results = search_elasticsearch(query, limit)
    
    end_time = time.time()
    
    return jsonify({
        'query': query,
        'search_type': search_type,
        'results': results,
        'count': len(results),
        'time': round(end_time - start_time, 3),
        'metrics': search_metrics
    })

@app.route('/metrics')
def metrics():
    """Get search performance metrics"""
    return jsonify(search_metrics)

@app.route('/health')
def health():
    """Health check endpoint"""
    health_status = {
        'status': 'healthy',
        'elasticsearch': False,
        'redis': False,
        'postgres': False
    }
    
    try:
        es.ping()
        health_status['elasticsearch'] = True
    except:
        pass
    
    try:
        redis_client.ping()
        health_status['redis'] = True
    except:
        pass
    
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        health_status['postgres'] = True
    except:
        pass
    
    if not all([health_status['elasticsearch'], health_status['redis'], health_status['postgres']]):
        health_status['status'] = 'degraded'
    
    return jsonify(health_status)

def init_services():
    """Initialize services and create sample data"""
    max_retries = 30
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            # Test connections
            es.ping()
            redis_client.ping()
            with get_db_connection() as conn:
                pass
            
            logger.info("All services connected successfully")
            create_sample_data()
            break
        except Exception as e:
            retry_count += 1
            logger.warning(f"Waiting for services... ({retry_count}/{max_retries}): {e}")
            time.sleep(2)
    
    if retry_count >= max_retries:
        logger.error("Failed to connect to services after maximum retries")

if __name__ == '__main__':
    # Initialize services in a separate thread
    init_thread = threading.Thread(target=init_services)
    init_thread.start()
    
    app.run(host='0.0.0.0', port=5000, debug=True)
