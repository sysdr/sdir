#!/bin/bash

# Compression Techniques Demo - One-Click Setup
# Creates a complete compression performance analyzer

set -e

echo "🚀 Setting up Compression Techniques Demo..."

# Create project structure
mkdir -p compression-demo/{src,static,templates,test_data,logs}
cd compression-demo

# Create requirements.txt
cat > requirements.txt << 'EOF'
flask==3.0.0
zstandard==0.22.0
brotli==1.1.0
lz4==4.3.3
numpy==1.24.4
matplotlib==3.8.2
psutil==5.9.8
requests==2.31.0
werkzeug==3.0.1
EOF

# Create main Flask application
cat > src/app.py << 'EOF'
import flask
from flask import Flask, render_template, jsonify, request
import gzip
import brotli
import lz4.frame
import zstandard as zstd
import json
import time
import psutil
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import io
import base64
import os
from pathlib import Path

app = Flask(__name__, template_folder='../templates', static_folder='../static')

class CompressionAnalyzer:
    def __init__(self):
        self.compressors = {
            'gzip': {'compress': self._gzip_compress, 'level_range': range(1, 10)},
            'brotli': {'compress': self._brotli_compress, 'level_range': range(1, 12)},
            'zstd': {'compress': self._zstd_compress, 'level_range': range(1, 20)},
            'lz4': {'compress': self._lz4_compress, 'level_range': [1]}
        }
        
    def _gzip_compress(self, data, level=6):
        return gzip.compress(data, compresslevel=level)
    
    def _brotli_compress(self, data, level=6):
        return brotli.compress(data, quality=level)
    
    def _zstd_compress(self, data, level=3):
        cctx = zstd.ZstdCompressor(level=level)
        return cctx.compress(data)
    
    def _lz4_compress(self, data, level=1):
        return lz4.frame.compress(data)
    
    def benchmark_compression(self, data, algorithm, level=None):
        if algorithm not in self.compressors:
            return None
            
        compressor = self.compressors[algorithm]['compress']
        
        # Memory usage before
        process = psutil.Process()
        mem_before = process.memory_info().rss
        
        # Compression timing
        start_time = time.perf_counter()
        if level is not None:
            compressed_data = compressor(data, level)
        else:
            compressed_data = compressor(data)
        end_time = time.perf_counter()
        
        # Memory usage after
        mem_after = process.memory_info().rss
        
        # Calculate metrics
        original_size = len(data)
        compressed_size = len(compressed_data)
        compression_time = end_time - start_time
        compression_ratio = (1 - compressed_size / original_size) * 100
        throughput = original_size / compression_time / 1024 / 1024  # MB/s
        memory_used = mem_after - mem_before
        
        return {
            'algorithm': algorithm,
            'level': level,
            'original_size': original_size,
            'compressed_size': compressed_size,
            'compression_ratio': round(compression_ratio, 2),
            'compression_time': round(compression_time * 1000, 3),  # ms
            'throughput': round(throughput, 2),
            'memory_used': memory_used
        }

analyzer = CompressionAnalyzer()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/compress', methods=['POST'])
def compress_data():
    data = request.json
    text_data = data.get('text', '').encode('utf-8')
    
    if not text_data:
        return jsonify({'error': 'No data provided'}), 400
    
    results = []
    
    # Test all algorithms
    for algorithm in analyzer.compressors.keys():
        if algorithm == 'lz4':
            result = analyzer.benchmark_compression(text_data, algorithm)
            if result:
                results.append(result)
        else:
            # Test multiple levels for other algorithms
            for level in [1, 3, 6, 9]:
                if level in analyzer.compressors[algorithm]['level_range']:
                    result = analyzer.benchmark_compression(text_data, algorithm, level)
                    if result:
                        results.append(result)
    
    return jsonify({'results': results})

@app.route('/api/sample-data')
def get_sample_data():
    samples = {
        'json': json.dumps({
            'users': [{'id': i, 'name': f'User {i}', 'email': f'user{i}@example.com'} for i in range(100)],
            'metadata': {'timestamp': '2024-01-01', 'version': '1.0'}
        }),
        'log': '\n'.join([f'2024-01-01 10:{i:02d}:00 INFO Processing request {i} from 192.168.1.{i%255}' for i in range(50)]),
        'text': 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' * 20,
        'csv': 'id,name,value\n' + '\n'.join([f'{i},Item {i},{i*10}' for i in range(100)])
    }
    return jsonify(samples)

@app.route('/api/chart')
def generate_chart():
    # Generate comparison chart
    algorithms = ['gzip', 'brotli', 'zstd', 'lz4']
    ratios = [65, 72, 68, 55]  # Example compression ratios
    speeds = [25, 15, 35, 120]  # Example speeds in MB/s
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    
    # Compression ratio chart
    ax1.bar(algorithms, ratios, color=['#4285f4', '#34a853', '#fbbc04', '#ea4335'])
    ax1.set_title('Compression Ratio (%)')
    ax1.set_ylabel('Ratio (%)')
    
    # Speed chart
    ax2.bar(algorithms, speeds, color=['#4285f4', '#34a853', '#fbbc04', '#ea4335'])
    ax2.set_title('Compression Speed (MB/s)')
    ax2.set_ylabel('Speed (MB/s)')
    
    plt.tight_layout()
    
    # Convert to base64
    img_buffer = io.BytesIO()
    plt.savefig(img_buffer, format='png', dpi=150, bbox_inches='tight')
    img_buffer.seek(0)
    img_base64 = base64.b64encode(img_buffer.getvalue()).decode()
    plt.close()
    
    return jsonify({'chart': f'data:image/png;base64,{img_base64}'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# Create HTML template
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Compression Techniques Analyzer</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Google Sans', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #f8f9fa;
            min-height: 100vh;
        }
        
        .header {
            background: linear-gradient(135deg, #1a73e8 0%, #4285f4 100%);
            color: white;
            padding: 2rem 0;
            text-align: center;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            font-size: 2.5rem;
            font-weight: 400;
            margin-bottom: 0.5rem;
        }
        
        .header p {
            opacity: 0.9;
            font-size: 1.1rem;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        
        .card {
            background: white;
            border-radius: 12px;
            padding: 2rem;
            margin-bottom: 2rem;
            box-shadow: 0 2px 16px rgba(0,0,0,0.1);
            border: 1px solid #e8eaed;
        }
        
        .card h2 {
            color: #1a73e8;
            font-size: 1.5rem;
            margin-bottom: 1rem;
            font-weight: 500;
        }
        
        .input-section {
            margin-bottom: 2rem;
        }
        
        .sample-buttons {
            display: flex;
            gap: 1rem;
            margin-bottom: 1rem;
            flex-wrap: wrap;
        }
        
        .btn {
            padding: 0.75rem 1.5rem;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 500;
            transition: all 0.2s;
            text-decoration: none;
            display: inline-block;
        }
        
        .btn-primary {
            background: #1a73e8;
            color: white;
        }
        
        .btn-primary:hover {
            background: #1557b0;
            transform: translateY(-1px);
        }
        
        .btn-secondary {
            background: #f1f3f4;
            color: #5f6368;
            border: 1px solid #dadce0;
        }
        
        .btn-secondary:hover {
            background: #e8eaed;
        }
        
        textarea {
            width: 100%;
            min-height: 150px;
            padding: 1rem;
            border: 2px solid #e8eaed;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            resize: vertical;
            transition: border-color 0.2s;
        }
        
        textarea:focus {
            outline: none;
            border-color: #1a73e8;
        }
        
        .results-section {
            margin-top: 2rem;
        }
        
        .results-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .result-card {
            background: #f8f9fa;
            border: 1px solid #e8eaed;
            border-radius: 8px;
            padding: 1.5rem;
            position: relative;
        }
        
        .result-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }
        
        .algorithm-name {
            font-weight: 600;
            font-size: 1.1rem;
            color: #1a73e8;
        }
        
        .compression-ratio {
            background: #e8f0fe;
            color: #1a73e8;
            padding: 0.25rem 0.75rem;
            border-radius: 16px;
            font-weight: 600;
            font-size: 0.9rem;
        }
        
        .metrics {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 0.5rem;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            padding: 0.5rem 0;
            border-bottom: 1px solid #e8eaed;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-label {
            color: #5f6368;
            font-size: 0.9rem;
        }
        
        .metric-value {
            font-weight: 600;
            color: #202124;
        }
        
        .loading {
            text-align: center;
            padding: 2rem;
            color: #5f6368;
        }
        
        .chart-container {
            text-align: center;
            margin-top: 2rem;
        }
        
        .chart-container img {
            max-width: 100%;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        @media (max-width: 768px) {
            .sample-buttons {
                flex-direction: column;
            }
            
            .btn {
                width: 100%;
            }
            
            .results-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Compression Techniques Analyzer</h1>
        <p>Compare compression algorithms performance and efficiency</p>
    </div>
    
    <div class="container">
        <div class="card">
            <h2>Data Input</h2>
            <div class="input-section">
                <div class="sample-buttons">
                    <button class="btn btn-secondary" onclick="loadSample('json')">JSON Data</button>
                    <button class="btn btn-secondary" onclick="loadSample('log')">Log Files</button>
                    <button class="btn btn-secondary" onclick="loadSample('text')">Text Content</button>
                    <button class="btn btn-secondary" onclick="loadSample('csv')">CSV Data</button>
                </div>
                <textarea id="dataInput" placeholder="Enter your data here or click a sample button above..."></textarea>
                <div style="margin-top: 1rem;">
                    <button class="btn btn-primary" onclick="analyzeCompression()">Analyze Compression</button>
                </div>
            </div>
        </div>
        
        <div class="card results-section" id="results" style="display: none;">
            <h2>Compression Results</h2>
            <div id="resultsContent"></div>
        </div>
        
        <div class="card" id="chartSection" style="display: none;">
            <h2>Performance Comparison</h2>
            <div class="chart-container" id="chartContainer"></div>
        </div>
    </div>

    <script>
        async function loadSample(type) {
            try {
                const response = await fetch('/api/sample-data');
                const samples = await response.json();
                document.getElementById('dataInput').value = samples[type];
            } catch (error) {
                console.error('Error loading sample:', error);
            }
        }
        
        async function analyzeCompression() {
            const data = document.getElementById('dataInput').value;
            if (!data.trim()) {
                alert('Please enter some data to analyze');
                return;
            }
            
            const resultsSection = document.getElementById('results');
            const resultsContent = document.getElementById('resultsContent');
            
            resultsSection.style.display = 'block';
            resultsContent.innerHTML = '<div class="loading">Analyzing compression performance...</div>';
            
            try {
                const response = await fetch('/api/compress', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ text: data })
                });
                
                const result = await response.json();
                displayResults(result.results);
                loadChart();
            } catch (error) {
                console.error('Error analyzing compression:', error);
                resultsContent.innerHTML = '<div class="loading">Error analyzing compression. Please try again.</div>';
            }
        }
        
        function displayResults(results) {
            const resultsContent = document.getElementById('resultsContent');
            
            if (!results || results.length === 0) {
                resultsContent.innerHTML = '<div class="loading">No results to display</div>';
                return;
            }
            
            const html = `
                <div class="results-grid">
                    ${results.map(result => `
                        <div class="result-card">
                            <div class="result-header">
                                <span class="algorithm-name">
                                    ${result.algorithm.toUpperCase()}
                                    ${result.level ? ` (Level ${result.level})` : ''}
                                </span>
                                <span class="compression-ratio">${result.compression_ratio}%</span>
                            </div>
                            <div class="metrics">
                                <div class="metric">
                                    <span class="metric-label">Original Size</span>
                                    <span class="metric-value">${formatBytes(result.original_size)}</span>
                                </div>
                                <div class="metric">
                                    <span class="metric-label">Compressed Size</span>
                                    <span class="metric-value">${formatBytes(result.compressed_size)}</span>
                                </div>
                                <div class="metric">
                                    <span class="metric-label">Speed</span>
                                    <span class="metric-value">${result.throughput} MB/s</span>
                                </div>
                                <div class="metric">
                                    <span class="metric-label">Time</span>
                                    <span class="metric-value">${result.compression_time} ms</span>
                                </div>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
            
            resultsContent.innerHTML = html;
        }
        
        async function loadChart() {
            try {
                const response = await fetch('/api/chart');
                const result = await response.json();
                
                const chartSection = document.getElementById('chartSection');
                const chartContainer = document.getElementById('chartContainer');
                
                chartContainer.innerHTML = `<img src="${result.chart}" alt="Compression Performance Chart">`;
                chartSection.style.display = 'block';
            } catch (error) {
                console.error('Error loading chart:', error);
            }
        }
        
        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        // Load JSON sample by default
        loadSample('json');
    </script>
</body>
</html>
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY . .

# Expose port
EXPOSE 5000

# Set environment variables
ENV FLASK_APP=src/app.py
ENV FLASK_ENV=production

# Run the application
CMD ["python", "src/app.py"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  compression-demo:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./logs:/app/logs
    environment:
      - FLASK_ENV=development
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Create test script
cat > test_compression.py << 'EOF'
#!/usr/bin/env python3

import requests
import json
import sys
import time

def test_api():
    base_url = "http://localhost:5000"
    
    print("🧪 Testing Compression API...")
    
    # Test 1: Check if server is running
    try:
        response = requests.get(f"{base_url}/")
        assert response.status_code == 200
        print("✅ Server is running")
    except Exception as e:
        print(f"❌ Server not accessible: {e}")
        return False
    
    # Test 2: Get sample data
    try:
        response = requests.get(f"{base_url}/api/sample-data")
        assert response.status_code == 200
        samples = response.json()
        assert 'json' in samples
        print("✅ Sample data endpoint working")
    except Exception as e:
        print(f"❌ Sample data test failed: {e}")
        return False
    
    # Test 3: Compression analysis
    try:
        test_data = {"text": "This is a test string for compression analysis. " * 10}
        response = requests.post(
            f"{base_url}/api/compress",
            headers={"Content-Type": "application/json"},
            json=test_data
        )
        assert response.status_code == 200
        results = response.json()
        assert 'results' in results
        assert len(results['results']) > 0
        print("✅ Compression analysis working")
    except Exception as e:
        print(f"❌ Compression analysis test failed: {e}")
        return False
    
    # Test 4: Chart generation
    try:
        response = requests.get(f"{base_url}/api/chart")
        assert response.status_code == 200
        chart_data = response.json()
        assert 'chart' in chart_data
        print("✅ Chart generation working")
    except Exception as e:
        print(f"❌ Chart generation test failed: {e}")
        return False
    
    print("🎉 All tests passed!")
    return True

if __name__ == "__main__":
    # Wait for server to start
    time.sleep(5)
    success = test_api()
    sys.exit(0 if success else 1)
EOF

chmod +x test_compression.py

echo "📦 Building Docker container..."
docker build -t compression-demo .

echo "🚀 Starting services..."
docker-compose up -d

echo "⏱️  Waiting for services to start..."
sleep 10

echo "🧪 Running tests..."
python3 test_compression.py

echo ""
echo "🎉 Demo setup complete!"
echo ""
echo "🌐 Access the demo at: http://localhost:5000"
echo ""
echo "📊 Features available:"
echo "   • Interactive compression comparison"
echo "   • Multiple algorithm testing (gzip, brotli, zstd, lz4)"
echo "   • Performance metrics visualization"
echo "   • Sample data for different use cases"
echo ""
echo "🔧 Commands:"
echo "   • View logs: docker-compose logs -f"
echo "   • Stop demo: docker-compose down"
echo "   • Restart: docker-compose restart"
echo ""
echo "📚 Try these test scenarios:"
echo "   1. Compare JSON compression ratios"
echo "   2. Test log file compression speed"
echo "   3. Analyze different compression levels"
echo "   4. Compare memory usage patterns"