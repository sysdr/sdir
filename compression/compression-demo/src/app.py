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
