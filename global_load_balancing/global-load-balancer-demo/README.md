# Global Load Balancer Demo

A comprehensive demonstration of global load balancing strategies for System Design Interview preparation.

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose installed
- At least 2GB of available RAM
- Ports 5000 and 8888 available

### One-Click Setup

```bash
# Start all services
./start.sh

# Check status
./status.sh

# Stop all services
./stop.sh
```

## 📋 Available Scripts

### `./start.sh` - Start Services
- Checks Docker and Docker Compose availability
- Validates required files
- Builds and starts all services
- Waits for health checks
- Displays access URLs and API endpoints
- Shows real-time logs

### `./stop.sh` - Stop Services
- Gracefully stops all running services
- Cleans up Docker resources
- Provides restart instructions
- Shows final status

### `./restart.sh` - Restart Services
- Stops existing services
- Rebuilds and starts services
- Waits for health checks
- Shows updated status

### `./status.sh` - Check Status
- Shows service status and health
- Displays resource usage
- Lists API endpoints
- Shows recent logs
- Provides management commands

## 🌐 Access URLs

Once started, access the application at:

- **Main Application**: http://localhost:5000
- **Nginx Proxy**: http://localhost:8888

## 🔌 API Endpoints

### Health & Status
- `GET /health` - Application health check
- `GET /api/data-centers` - List all data centers
- `GET /api/stats` - Get global statistics

### Load Balancing
- `POST /api/request` - Process a user request
- `POST /api/config` - Update load balancer configuration

## 🏗️ Architecture

The demo consists of two main services:

### 1. Global Load Balancer (Flask App)
- **Port**: 5000
- **Features**:
  - Multiple load balancing strategies
  - Real-time health monitoring
  - Geographic routing
  - Latency optimization
  - Capacity-based routing
  - Round-robin fallback

### 2. Nginx Proxy
- **Port**: 8888
- **Features**:
  - Reverse proxy to Flask app
  - Load balancing demonstration
  - Health check integration

## 🌍 Data Centers

The demo simulates 4 global data centers:

1. **US East (Virginia)** - us-east-1
2. **US West (Oregon)** - us-west-2
3. **Europe (Ireland)** - eu-west-1
4. **Asia Pacific (Singapore)** - ap-southeast-1

## ⚖️ Load Balancing Strategies

### 1. Geographic Routing
Routes requests to the nearest geographic data center based on user location.

### 2. Latency Optimization
Selects data center with lowest estimated latency considering:
- Network distance
- Base latency
- Jitter simulation

### 3. Capacity-Based Routing
Routes to data center with highest available capacity.

### 4. Round-Robin
Distributes requests evenly across all healthy data centers.

## 🛠️ Development

### Project Structure
```
global-load-balancer-demo/
├── app/
│   └── main.py              # Flask application
├── configs/
│   └── nginx.conf           # Nginx configuration
├── static/
│   ├── css/
│   │   └── style.css        # Frontend styles
│   └── js/
│       └── app.js           # Frontend JavaScript
├── templates/
│   └── index.html           # Main HTML template
├── tests/
│   └── test_global_lb.py    # Test suite
├── docker-compose.yml       # Service orchestration
├── Dockerfile              # Application container
├── requirements.txt        # Python dependencies
├── start.sh               # Start script
├── stop.sh                # Stop script
├── restart.sh             # Restart script
└── status.sh              # Status script
```

### Running Tests
```bash
# Run the test suite
python -m pytest tests/
```

### Development Mode
```bash
# Start with development settings
docker-compose up --build

# View logs
docker-compose logs -f

# Access container shell
docker-compose exec global-lb bash
```

## 🔧 Configuration

### Environment Variables
- `FLASK_ENV=development` - Flask environment
- `FLASK_DEBUG=1` - Enable debug mode

### Load Balancer Configuration
Update load balancing strategy via API:
```bash
curl -X POST http://localhost:5000/api/config \
  -H "Content-Type: application/json" \
  -d '{"strategy": "latency"}'
```

Available strategies: `latency`, `geographic`, `capacity`, `round_robin`

## 📊 Monitoring

### Health Checks
- Application health: http://localhost:5000/health
- Nginx health: http://localhost:8888

### Metrics
- Total requests processed
- Success/failure rates
- Average latency
- Routing decisions history

## 🧹 Cleanup

### Stop and Remove Everything
```bash
# Stop services and remove containers
docker-compose down

# Remove volumes and orphaned containers
docker-compose down --volumes --remove-orphans

# Clean up all unused Docker resources (use with caution)
docker system prune -a
```

## 🐛 Troubleshooting

### Common Issues

1. **Port already in use**
   ```bash
   # Check what's using the ports
   lsof -i :5000
   lsof -i :8888
   ```

2. **Docker not running**
   ```