# Consistent Hashing Interactive Demo

This demo demonstrates consistent hashing concepts with a fully interactive web interface.

## Features

- ✅ Interactive consistent hashing implementation with virtual nodes
- ✅ Real-time load distribution visualization
- ✅ Node addition/removal with rebalancing metrics
- ✅ Performance benchmarking
- ✅ Web-based interface with charts
- ✅ Docker support for easy deployment
- ✅ Comprehensive test suite

## Quick Start

### Option 1: Docker (Recommended)
```bash
./run_demo.sh
```

### Option 2: Local Python
```bash
pip install -r requirements.txt
cd src && python app.py
```

## Access the Demo

- **Web Interface**: http://localhost:5000
- **API Endpoints**: http://localhost:5000/api/

## Key Features to Try

1. **Add/Remove Nodes**: See how the ring rebalances
2. **Load Simulation**: Generate 1000 random keys and see distribution
3. **Key Lookup**: Find which node handles specific keys
4. **Performance Benchmark**: Test lookup performance
5. **Load Visualization**: Interactive charts showing distribution

## API Endpoints

- `GET /api/ring/info` - Get current ring state
- `POST /api/ring/add_node` - Add a new node
- `POST /api/ring/remove_node` - Remove a node  
- `POST /api/ring/lookup` - Find node for a key
- `GET /api/demo/simulate_load` - Simulate random load
- `GET /api/demo/benchmark` - Run performance tests

## Testing

```bash
cd tests && python test_consistent_hash.py
```

## Architecture

The demo implements:
- Consistent hashing with configurable virtual nodes
- xxHash for fast, high-quality hashing
- Weighted node distribution
- Replication support
- Comprehensive metrics collection
- Real-time load balancing visualization
