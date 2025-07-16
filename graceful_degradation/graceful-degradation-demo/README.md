# 🛡️ Graceful Degradation Demo

A comprehensive demonstration of graceful degradation patterns in web applications, featuring automated UI testing capabilities.

## 🚀 Features

### Core Functionality
- **System Pressure Monitoring**: Real-time CPU and memory usage tracking
- **Feature Toggles**: Dynamic feature enabling/disabling based on system load
- **Circuit Breakers**: Automatic service degradation under high load
- **Fallback Mechanisms**: Graceful service degradation with cached responses
- **Real-time Metrics**: Prometheus-compatible metrics endpoint

### 🧪 Automated UI Testing
- **Comprehensive Component Testing**: Tests all UI components automatically
- **Visual Test Results**: Beautiful, real-time test results display
- **Component Coverage**: Tests pressure meters, buttons, displays, and APIs
- **Performance Metrics**: Test duration and status tracking
- **One-Click Testing**: Run all tests with a single button click

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend UI   │    │   Backend API   │    │   Redis Cache   │
│                 │    │                 │    │                 │
│ • Pressure Meter│◄──►│ • FastAPI       │◄──►│ • Session Store │
│ • Load Controls │    │ • Circuit       │    │ • Cache Layer   │
│ • Test Results  │    │   Breakers      │    │                 │
│ • Real-time Logs│    │ • Feature       │    │                 │
│                 │    │   Toggles       │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🎮 Demo Scenarios

### 1. Light Load (20%)
- All features active
- Normal response times
- Full functionality

### 2. Medium Load (50%)
- Some features may degrade
- Slightly increased response times
- Circuit breakers monitoring

### 3. Heavy Load (80%)
- Feature degradation begins
- Fallback responses activated
- Performance optimization

### 4. Extreme Load (100%)
- Maximum degradation
- Circuit breakers open
- Core functionality only

## 🧪 UI Testing Features

### Automated Test Components
1. **Pressure Meter Display** - Tests system pressure visualization
2. **Active Features Display** - Tests feature toggle visibility
3. **Circuit Breakers Display** - Tests circuit breaker status
4. **Load Simulation Buttons** - Tests load control functionality
5. **Recommendations Test Button** - Tests recommendation service
6. **Reviews Test Button** - Tests review service
7. **Log Display Component** - Tests log visualization
8. **Status API Endpoint** - Tests API functionality

### Test Results Display
- **Real-time Results**: Instant test execution and display
- **Visual Status**: Color-coded pass/fail/warning indicators
- **Performance Metrics**: Test duration and timing information
- **Detailed Reports**: Component-specific test results
- **Summary Statistics**: Overall test success rates

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+ (for local development)

### Running the Demo
```bash
# Start the demo
./demo.sh

# Access the application
open http://localhost:8080

# Run automated UI tests
# Click "Run UI Tests" button in the UI
```

### Testing the UI
1. **Open the Application**: Navigate to http://localhost:8080
2. **Run UI Tests**: Click the "Run UI Tests" button
3. **View Results**: See real-time test results displayed
4. **Test Scenarios**: Try different load levels to see degradation
5. **Monitor Logs**: Watch real-time activity logs

### API Endpoints
- `GET /` - Main application interface
- `GET /api/status` - System status and metrics
- `POST /api/ui-tests/run` - Run automated UI tests
- `GET /api/ui-tests/results` - Get latest test results
- `GET /api/load/{intensity}` - Simulate system load
- `GET /metrics` - Prometheus metrics

## 🧪 UI Testing API

### Run Tests
```bash
curl -X POST http://localhost:8080/api/ui-tests/run
```

### Get Results
```bash
curl http://localhost:8080/api/ui-tests/results
```

### Example Response
```json
{
  "last_run": "2024-01-15T10:30:00.123456",
  "tests": [
    {
      "test_name": "Pressure Meter Display",
      "component": "System Pressure",
      "status": "passed",
      "message": "Pressure meter correctly displays 50%",
      "duration": 0.123,
      "timestamp": "2024-01-15T10:30:00.123456"
    }
  ],
  "summary": {
    "passed": 8,
    "failed": 0,
    "warning": 0,
    "total": 8
  }
}
```

## 🛠️ Development

### Project Structure
```
graceful-degradation-demo/
├── app/
│   └── main.py              # FastAPI application
├── templates/
│   └── index.html           # Main UI template
├── tests/
│   ├── test_ui_tests.py     # UI testing verification
│   ├── load_generator.py    # Load testing utilities
│   └── test_degradation.py  # Degradation testing
├── monitoring/              # Monitoring configurations
├── static/                  # Static assets
├── docker-compose.yml       # Service orchestration
├── Dockerfile              # Application container
├── requirements.txt         # Python dependencies
├── demo.sh                 # Demo startup script
└── cleanup.sh              # Cleanup script
```

### Local Development
```bash
# Install dependencies
pip install -r requirements.txt

# Run the application
python app/main.py

# Run UI tests
python tests/test_ui_tests.py
```

### Docker Development
```bash
# Build and run
docker-compose up --build

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

## 📊 Monitoring

### Metrics Available
- `requests_total` - Total API requests
- `request_duration_seconds` - Request response times
- `system_load_percent` - Current system load
- `active_features_count` - Number of active features

### Prometheus Integration
```bash
# Access metrics
curl http://localhost:8080/metrics
```

## 🎯 Use Cases

### System Design Interviews
- Demonstrate graceful degradation patterns
- Show circuit breaker implementations
- Illustrate feature toggle strategies
- Present monitoring and observability

### Production Applications
- Load testing and capacity planning
- Feature flag management
- Service reliability patterns
- Performance monitoring

### Learning and Development
- Understanding degradation patterns
- Learning FastAPI and async Python
- Docker containerization
- UI testing automation

## 🔧 Configuration

### Environment Variables
- `REDIS_URL` - Redis connection string (default: redis://localhost:6379)
- `LOG_LEVEL` - Logging level (default: INFO)

### Feature Toggles
Features can be configured in the `FeatureToggle` class:
- `recommendations` - Product recommendations
- `detailed_reviews` - Detailed product reviews
- `analytics` - User analytics tracking
- `search_suggestions` - Search autocomplete

### Circuit Breaker Settings
- `failure_threshold` - Number of failures before opening
- `recovery_timeout` - Time to wait before half-open state

## 🧹 Cleanup

```bash
# Stop all services
./cleanup.sh

# Or manually
docker-compose down
docker system prune -f
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all UI tests pass
5. Submit a pull request

## 📝 License

MIT License - see LICENSE file for details

---

**🎉 Enjoy exploring graceful degradation patterns with automated UI testing!** 