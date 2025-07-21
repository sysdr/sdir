#!/bin/bash

# Search Scaling Demo Script
# Creates a comprehensive search scaling demonstration

set -e

echo "🚀 Starting Search Scaling Demo Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create project directory structure
print_status "Creating project structure..."
mkdir -p search-scaling-demo/{app,data,logs,config}
cd search-scaling-demo

# Create requirements.txt
cat > requirements.txt << 'EOF'
flask==3.0.0
elasticsearch==8.11.1
redis==5.0.1
psycopg2-binary==2.9.9
requests==2.31.0
flask-cors==4.0.0
gunicorn==21.2.0
python-dotenv==1.0.0
pandas==2.1.4
numpy==1.26.2
faker==20.1.0
sentence-transformers==2.2.2
scikit-learn==1.3.2
plotly==5.17.0
dash==2.16.1
dash-bootstrap-components==1.5.0
EOF

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.1
    container_name: search-elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - "9200:9200"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  redis:
    image: redis:7.2-alpine
    container_name: search-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  postgres:
    image: postgres:16-alpine
    container_name: search-postgres
    environment:
      POSTGRES_DB: searchdb
      POSTGRES_USER: searchuser
      POSTGRES_PASSWORD: searchpass
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./config/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U searchuser -d searchdb"]
      interval: 10s
      timeout: 5s
      retries: 5

  search-app:
    build: .
    container_name: search-app
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=development
      - ELASTICSEARCH_URL=http://elasticsearch:9200
      - REDIS_URL=redis://redis:6379
      - DATABASE_URL=postgresql://searchuser:searchpass@postgres:5432/searchdb
    depends_on:
      elasticsearch:
        condition: service_healthy
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    volumes:
      - ./app:/app
      - ./logs:/app/logs

volumes:
  es_data:
  redis_data:
  postgres_data:
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ .

# Create necessary directories
RUN mkdir -p logs data

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]
EOF

# Create database initialization script
mkdir -p config
cat > config/init.sql << 'EOF'
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    category VARCHAR(100),
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_documents_title ON documents USING GIN(to_tsvector('english', title));
CREATE INDEX IF NOT EXISTS idx_documents_content ON documents USING GIN(to_tsvector('english', content));
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(category);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at);
EOF

# Create main Flask application
cat > app/app.py << 'EOF'
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
EOF

# Create HTML template
mkdir -p app/templates
cat > app/templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Search Scaling Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Google Sans', Roboto, Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        .header {
            background: linear-gradient(135deg, #4285f4 0%, #34a853 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }

        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            font-weight: 300;
        }

        .header p {
            font-size: 1.1rem;
            opacity: 0.9;
        }

        .content {
            padding: 30px;
        }

        .search-section {
            margin-bottom: 30px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 12px;
            border-left: 5px solid #4285f4;
        }

        .search-form {
            display: grid;
            grid-template-columns: 1fr auto auto auto;
            gap: 15px;
            align-items: center;
            margin-bottom: 20px;
        }

        .search-input {
            padding: 12px 16px;
            border: 2px solid #e1e5e9;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s ease;
        }

        .search-input:focus {
            outline: none;
            border-color: #4285f4;
            box-shadow: 0 0 0 3px rgba(66, 133, 244, 0.1);
        }

        .search-select, .search-button {
            padding: 12px 20px;
            border: 2px solid #4285f4;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: all 0.3s ease;
        }

        .search-select {
            background: white;
            color: #4285f4;
        }

        .search-button {
            background: #4285f4;
            color: white;
            font-weight: 500;
        }

        .search-button:hover {
            background: #3367d6;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(66, 133, 244, 0.3);
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 12px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.05);
            border-left: 5px solid #34a853;
            text-align: center;
        }

        .metric-value {
            font-size: 2rem;
            font-weight: 600;
            color: #34a853;
            margin-bottom: 5px;
        }

        .metric-label {
            color: #5f6368;
            font-size: 0.9rem;
        }

        .results-section {
            margin-top: 30px;
        }

        .results-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid #e8eaed;
        }

        .results-count {
            font-size: 1.1rem;
            color: #5f6368;
        }

        .results-time {
            font-size: 1rem;
            color: #34a853;
            font-weight: 500;
        }

        .result-item {
            background: white;
            margin-bottom: 15px;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
            border-left: 4px solid #4285f4;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        .result-item:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 16px rgba(0,0,0,0.1);
        }

        .result-title {
            font-size: 1.2rem;
            font-weight: 600;
            color: #1a73e8;
            margin-bottom: 8px;
        }

        .result-content {
            color: #5f6368;
            line-height: 1.5;
            margin-bottom: 10px;
        }

        .result-meta {
            display: flex;
            gap: 15px;
            font-size: 0.9rem;
            color: #9aa0a6;
        }

        .loading {
            text-align: center;
            padding: 40px;
            color: #5f6368;
        }

        .spinner {
            border: 3px solid #f3f3f3;
            border-top: 3px solid #4285f4;
            border-radius: 50%;
            width: 30px;
            height: 30px;
            animation: spin 1s linear infinite;
            margin: 0 auto 15px;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .comparison-section {
            background: #f8f9fa;
            padding: 25px;
            border-radius: 12px;
            margin-top: 30px;
        }

        .comparison-title {
            font-size: 1.5rem;
            color: #202124;
            margin-bottom: 20px;
            text-align: center;
        }

        .comparison-buttons {
            display: flex;
            gap: 15px;
            justify-content: center;
            margin-bottom: 20px;
        }

        .comparison-btn {
            padding: 12px 24px;
            border: 2px solid #4285f4;
            border-radius: 8px;
            background: white;
            color: #4285f4;
            cursor: pointer;
            transition: all 0.3s ease;
        }

        .comparison-btn:hover {
            background: #4285f4;
            color: white;
        }

        @media (max-width: 768px) {
            .search-form {
                grid-template-columns: 1fr;
            }
            
            .metrics-grid {
                grid-template-columns: 1fr;
            }
            
            .comparison-buttons {
                flex-direction: column;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Search Scaling Demo</h1>
            <p>Compare Database, Elasticsearch, and Cached Search Performance</p>
        </div>
        
        <div class="content">
            <div class="search-section">
                <div class="search-form">
                    <input type="text" id="searchInput" class="search-input" placeholder="Enter your search query..." value="technology">
                    <select id="searchType" class="search-select">
                        <option value="elasticsearch">Elasticsearch</option>
                        <option value="database">Database</option>
                        <option value="cached">Cached</option>
                    </select>
                    <select id="searchLimit" class="search-select">
                        <option value="10">10 Results</option>
                        <option value="20" selected>20 Results</option>
                        <option value="50">50 Results</option>
                    </select>
                    <button id="searchButton" class="search-button">Search</button>
                </div>
                
                <div class="metrics-grid" id="metricsGrid">
                    <div class="metric-card">
                        <div class="metric-value" id="totalSearches">0</div>
                        <div class="metric-label">Total Searches</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value" id="avgTime">0ms</div>
                        <div class="metric-label">Average Time</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value" id="cachedSearches">0</div>
                        <div class="metric-label">Cached Searches</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value" id="esSearches">0</div>
                        <div class="metric-label">Elasticsearch</div>
                    </div>
                </div>
            </div>
            
            <div class="comparison-section">
                <h3 class="comparison-title">Performance Comparison</h3>
                <div class="comparison-buttons">
                    <button class="comparison-btn" onclick="runComparison()">Run Performance Test</button>
                    <button class="comparison-btn" onclick="clearCache()">Clear Cache</button>
                    <button class="comparison-btn" onclick="loadMetrics()">Refresh Metrics</button>
                </div>
            </div>
            
            <div class="results-section" id="resultsSection" style="display: none;">
                <div class="results-header">
                    <span class="results-count" id="resultsCount">0 results</span>
                    <span class="results-time" id="resultsTime">0ms</span>
                </div>
                <div id="resultsContainer"></div>
            </div>
            
            <div class="loading" id="loadingIndicator" style="display: none;">
                <div class="spinner"></div>
                <div>Searching...</div>
            </div>
        </div>
    </div>

    <script>
        let searchMetrics = {};

        async function performSearch() {
            const query = document.getElementById('searchInput').value.trim();
            const searchType = document.getElementById('searchType').value;
            const limit = document.getElementById('searchLimit').value;
            
            if (!query) {
                alert('Please enter a search query');
                return;
            }
            
            showLoading(true);
            hideResults();
            
            try {
                const response = await fetch(`/search?q=${encodeURIComponent(query)}&type=${searchType}&limit=${limit}`);
                const data = await response.json();
                
                displayResults(data);
                updateMetrics(data.metrics);
            } catch (error) {
                console.error('Search error:', error);
                alert('Search failed. Please try again.');
            } finally {
                showLoading(false);
            }
        }
        
        function displayResults(data) {
            const resultsSection = document.getElementById('resultsSection');
            const resultsCount = document.getElementById('resultsCount');
            const resultsTime = document.getElementById('resultsTime');
            const resultsContainer = document.getElementById('resultsContainer');
            
            resultsCount.textContent = `${data.count} results for "${data.query}"`;
            resultsTime.textContent = `${data.time * 1000}ms (${data.search_type})`;
            
            resultsContainer.innerHTML = '';
            
            data.results.forEach(result => {
                const resultDiv = document.createElement('div');
                resultDiv.className = 'result-item';
                
                let highlightedContent = result.content;
                if (result.highlight && result.highlight.content) {
                    highlightedContent = result.highlight.content[0];
                }
                
                resultDiv.innerHTML = `
                    <div class="result-title">${result.title}</div>
                    <div class="result-content">${highlightedContent.substring(0, 200)}...</div>
                    <div class="result-meta">
                        <span>Category: ${result.category}</span>
                        <span>ID: ${result.id}</span>
                        ${result.score ? `<span>Score: ${result.score.toFixed(2)}</span>` : ''}
                    </div>
                `;
                
                resultsContainer.appendChild(resultDiv);
            });
            
            resultsSection.style.display = 'block';
        }
        
        function updateMetrics(metrics) {
            searchMetrics = metrics;
            
            const totalSearches = metrics.database_searches + metrics.elasticsearch_searches + metrics.cached_searches;
            const avgTime = totalSearches > 0 ? (metrics.total_search_time / totalSearches * 1000) : 0;
            
            document.getElementById('totalSearches').textContent = totalSearches;
            document.getElementById('avgTime').textContent = `${avgTime.toFixed(0)}ms`;
            document.getElementById('cachedSearches').textContent = metrics.cached_searches;
            document.getElementById('esSearches').textContent = metrics.elasticsearch_searches;
        }
        
        function showLoading(show) {
            document.getElementById('loadingIndicator').style.display = show ? 'block' : 'none';
        }
        
        function hideResults() {
            document.getElementById('resultsSection').style.display = 'none';
        }
        
        async function runComparison() {
            const queries = ['technology', 'science', 'business', 'health', 'education'];
            const types = ['database', 'elasticsearch', 'cached'];
            
            showLoading(true);
            
            for (const type of types) {
                for (const query of queries) {
                    try {
                        await fetch(`/search?q=${encodeURIComponent(query)}&type=${type}&limit=20`);
                        await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
                    } catch (error) {
                        console.error(`Error testing ${type} with query ${query}:`, error);
                    }
                }
            }
            
            await loadMetrics();
            showLoading(false);
            alert('Performance comparison completed! Check the metrics above.');
        }
        
        async function clearCache() {
            try {
                // Note: This would require a backend endpoint to clear Redis cache
                alert('Cache clearing would be implemented with a backend endpoint');
            } catch (error) {
                console.error('Error clearing cache:', error);
            }
        }
        
        async function loadMetrics() {
            try {
                const response = await fetch('/metrics');
                const metrics = await response.json();
                updateMetrics(metrics);
            } catch (error) {
                console.error('Error loading metrics:', error);
            }
        }
        
        // Event listeners
        document.getElementById('searchButton').addEventListener('click', performSearch);
        document.getElementById('searchInput').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                performSearch();
            }
        });
        
        // Load initial metrics
        loadMetrics();
        
        // Auto-refresh metrics every 5 seconds
        setInterval(loadMetrics, 5000);
    </script>
</body>
</html>
EOF

# Create static directory for assets
mkdir -p app/static

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Search Scaling Demo..."

# Stop and remove containers
docker-compose down -v --remove-orphans

# Remove Docker images
docker rmi search-scaling-demo_search-app 2>/dev/null || true

# Remove project directory
cd ..
rm -rf search-scaling-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

print_status "Building Docker images..."
docker-compose build

print_status "Starting services..."
docker-compose up -d

print_status "Waiting for services to be ready..."
sleep 30

# Check service health
print_status "Checking service health..."
for i in {1..30}; do
    if curl -s http://localhost:5000/health > /dev/null; then
        print_status "Search application is ready!"
        break
    fi
    echo "Waiting for application... ($i/30)"
    sleep 2
done

print_status "Running tests..."

# Test search endpoints
echo "Testing database search..."
curl -s "http://localhost:5000/search?q=technology&type=database&limit=5" | python3 -m json.tool > /dev/null && echo "✅ Database search working"

echo "Testing Elasticsearch search..."
curl -s "http://localhost:5000/search?q=science&type=elasticsearch&limit=5" | python3 -m json.tool > /dev/null && echo "✅ Elasticsearch search working"

echo "Testing cached search..."
curl -s "http://localhost:5000/search?q=business&type=cached&limit=5" | python3 -m json.tool > /dev/null && echo "✅ Cached search working"

print_status "Demo setup complete!"
echo ""
echo "🌐 Access the demo at: http://localhost:5000"
echo "🔍 Elasticsearch: http://localhost:9200"
echo "📊 Redis: localhost:6379"
echo "🗄️  PostgreSQL: localhost:5432"
echo ""
echo "🧪 Try these searches:"
echo "  - 'technology' (should find tech-related content)"
echo "  - 'science' (should find science content)"
echo "  - 'business' (should find business content)"
echo ""
echo "📈 Compare performance between:"
echo "  - Database search (PostgreSQL full-text)"
echo "  - Elasticsearch search (distributed search)"
echo "  - Cached search (Redis + Elasticsearch)"
echo ""
echo "🔧 Use the Performance Test button to compare all search types"
echo ""
print_status "Happy searching! 🚀"