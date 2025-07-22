# Seasonal Traffic Demo - Management Scripts

This directory contains comprehensive management scripts for the Seasonal Traffic Demo project. These scripts provide an easy way to start, stop, and monitor the demo environment.

## 📋 Available Scripts

### 🚀 `start.sh` - Start the Demo Environment
Starts all services including the scaling demo application and Prometheus monitoring.

**Features:**
- ✅ Docker and Docker Compose validation
- ✅ Automatic directory creation
- ✅ Health check monitoring
- ✅ Service status display
- ✅ Recent logs display
- ✅ Colored output for better UX

**Usage:**
```bash
./start.sh
```

**What it does:**
1. Checks if Docker and Docker Compose are available
2. Creates necessary directories (`logs/`, `data/`)
3. Stops any existing services to avoid conflicts
4. Builds and starts services with Docker Compose
5. Waits for services to be healthy
6. Displays service endpoints and information

### 🛑 `stop.sh` - Stop the Demo Environment
Gracefully stops all services with cleanup options.

**Features:**
- ✅ Graceful service shutdown
- ✅ Multiple cleanup options
- ✅ Orphaned container detection
- ✅ Force stop option
- ✅ Service logs before stopping

**Usage:**
```bash
./stop.sh                    # Interactive cleanup
./stop.sh --force           # Force stop without prompts
./stop.sh -f                # Same as --force
./stop.sh --help            # Show help
```

**Cleanup Options:**
1. **Remove containers only** (default)
2. **Remove containers and images**
3. **Remove containers, images, and volumes**
4. **Remove containers, images, volumes, and networks**
5. **Keep everything** (just stop services)

### 📊 `status.sh` - Check Demo Status
Comprehensive status checking and monitoring.

**Features:**
- ✅ Service health checks
- ✅ Resource usage monitoring
- ✅ Endpoint information
- ✅ Issue detection
- ✅ Live logs option
- ✅ System information

**Usage:**
```bash
./status.sh                 # Full status report
./status.sh --logs          # Show live logs
./status.sh -l              # Same as --logs
./status.sh --resources     # Show resource usage
./status.sh -r              # Same as --resources
./status.sh --health        # Health checks only
./status.sh -h              # Same as --health
./status.sh --help          # Show help
```

## 🎯 Quick Start Guide

### First Time Setup
1. **Make scripts executable:**
   ```bash
   chmod +x start.sh stop.sh status.sh
   ```

2. **Start the demo:**
   ```bash
   ./start.sh
   ```

3. **Check status:**
   ```bash
   ./status.sh
   ```

4. **Stop the demo:**
   ```bash
   ./stop.sh
   ```

### Daily Usage
```bash
# Start demo
./start.sh

# Check if everything is working
./status.sh

# View live logs (optional)
./status.sh --logs

# Stop demo when done
./stop.sh
```

## 🌐 Service Endpoints

Once started, the demo provides these endpoints:

### Scaling Demo (Port 8000)
- **Main Demo:** http://localhost:8000
- **API Metrics:** http://localhost:8000/api/metrics
- **WebSocket:** ws://localhost:8000/ws

### Prometheus (Port 9090)
- **Dashboard:** http://localhost:9090
- **Targets:** http://localhost:9090/targets
- **Graph:** http://localhost:9090/graph

## 🔧 Troubleshooting

### Common Issues

**Docker not running:**
```bash
# Start Docker Desktop or Docker daemon
# Then try again:
./start.sh
```

**Port conflicts:**
```bash
# Check what's using the ports
lsof -i :8000
lsof -i :9090

# Stop conflicting services or use different ports
```

**Services not starting:**
```bash
# Check logs
docker-compose logs

# Rebuild containers
docker-compose up -d --build
```

**Force cleanup:**
```bash
# Stop and remove everything
./stop.sh --force

# Or manually:
docker-compose down --volumes --remove-orphans
docker system prune -f
```

### Health Check Failures

If services don't become healthy:
1. Check if Docker has enough resources
2. Ensure ports 8000 and 9090 are available
3. Check system logs: `docker-compose logs`
4. Try rebuilding: `docker-compose up -d --build`

## 📈 Monitoring

### Resource Usage
```bash
# Check resource usage
./status.sh --resources

# Or directly:
docker stats
```

### Live Logs
```bash
# Follow logs in real-time
./status.sh --logs

# Or directly:
docker-compose logs -f
```

### Health Checks
```bash
# Quick health check
./status.sh --health

# Manual checks
curl http://localhost:8000/api/metrics
curl http://localhost:9090/-/healthy
```

## 🛠️ Advanced Usage

### Custom Docker Compose
If you need to use a different docker-compose file:
```bash
COMPOSE_FILE=docker-compose.prod.yml ./start.sh
```

### Environment Variables
Set environment variables before running scripts:
```bash
export DOCKER_BUILDKIT=1
./start.sh
```

### Debug Mode
For debugging, you can run services in foreground:
```bash
# Instead of ./start.sh, run:
docker-compose up --build
```

## 📝 Script Features

### Error Handling
- ✅ Graceful error handling with colored output
- ✅ Timeout protection for hanging operations
- ✅ Automatic cleanup on failures
- ✅ Detailed error messages

### User Experience
- ✅ Colored output for better readability
- ✅ Progress indicators
- ✅ Clear success/failure messages
- ✅ Helpful usage information

### Safety Features
- ✅ Docker availability checks
- ✅ Port conflict detection
- ✅ Resource usage warnings
- ✅ Orphaned container cleanup

## 🔄 Integration with Other Tools

### CI/CD Integration
These scripts can be easily integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Start Demo
  run: ./start.sh

- name: Run Tests
  run: ./run_tests.sh

- name: Stop Demo
  run: ./stop.sh
```

### Development Workflow
```bash
# Development cycle
./start.sh          # Start environment
# ... work on code ...
./status.sh         # Check status
# ... make changes ...
docker-compose restart  # Restart services
./stop.sh           # Clean up
```

## 📚 Additional Commands

### Manual Docker Compose Commands
```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Restart services
docker-compose restart

# Rebuild and start
docker-compose up -d --build
```

### System Maintenance
```bash
# Clean up Docker resources
docker system prune -f

# Remove all containers
docker-compose down --volumes --remove-orphans

# Clean up images
docker-compose down --rmi all
```

## 🤝 Contributing

When adding new features to the scripts:
1. Maintain the colored output format
2. Add appropriate error handling
3. Include help text for new options
4. Test with different scenarios
5. Update this README

## 📄 License

These scripts are part of the Seasonal Traffic Demo project and follow the same license terms. 