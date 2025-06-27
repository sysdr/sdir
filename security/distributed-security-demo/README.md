# Distributed Security Demo

A comprehensive demonstration of defense-in-depth security in distributed systems, featuring multiple microservices with advanced security monitoring and threat detection.

## 🚀 Quick Start

### Prerequisites
- Docker
- Docker Compose
- curl (for testing)

### Start the Demo
```bash
./demo.sh
```

This script will:
- ✅ Check all prerequisites
- ✅ Build all Docker images
- ✅ Start all services
- ✅ Test all endpoints
- ✅ Display service URLs and status

### Stop and Clean Up
```bash
./cleanup.sh
```

This script will:
- ✅ Stop all running containers
- ✅ Remove all Docker images
- ✅ Clean up volumes and networks
- ✅ Optimize system resources

## 🏗️ Architecture

### Services
- **API Gateway** (Port 8000) - Secure entry point with SSL/TLS
- **User Service** (Port 8001) - User management with security
- **Order Service** (Port 8002) - Order processing with security
- **Payment Service** (Port 8003) - Payment processing with security
- **Security Monitor** (Port 8080) - Real-time threat detection
- **Prometheus** (Port 9090) - Metrics collection
- **Grafana** (Port 3000) - Security dashboards

### Security Features
- 🔒 **SSL/TLS Certificates** - Self-signed certificates for all services
- 🛡️ **Threat Detection** - ML-based anomaly detection and rule-based security
- 📊 **Real-time Monitoring** - Security events and threat analysis
- 🔐 **Service-to-Service Authentication** - JWT tokens for inter-service communication
- 🚫 **Auto-blocking** - High-risk IPs automatically blocked

## 📊 Access Points

After running `./demo.sh`, you can access:

- **API Gateway**: https://localhost:8000
- **Security Dashboard**: http://localhost:8080
- **Grafana**: http://localhost:3000
- **Prometheus**: http://localhost:9090

## 🔧 Useful Commands

```bash
# View service logs
docker-compose logs -f [service-name]

# Check service status
docker-compose ps

# Restart a specific service
docker-compose restart [service-name]

# View security events
curl http://localhost:8080/api/security/events

# Check security status
curl http://localhost:8080/api/security/status
```

## 🛠️ Troubleshooting

### SSL Certificate Warnings
SSL certificate warnings are expected since we're using self-signed certificates for the demo. You can:
- Accept the certificate in your browser
- Use `curl -k` to ignore SSL verification
- Add the certificate to your trusted store

### Service Startup Issues
Some services may take a few minutes to fully initialize. If you encounter issues:
1. Check service logs: `docker-compose logs [service-name]`
2. Wait a few minutes and try again
3. Restart the service: `docker-compose restart [service-name]`

### Port Conflicts
If you get port conflicts, ensure no other services are using the required ports:
- 8000, 8001, 8002, 8003, 8080, 9090, 3000

## 📝 Notes

- This is a demonstration system with self-signed certificates
- The ML threat detection model trains on sample data
- All data is ephemeral and will be lost when containers are stopped
- For production use, implement proper certificate management and data persistence

## 🎯 Demo Scenarios

1. **Normal Traffic**: Access the API gateway and observe normal request patterns
2. **Threat Detection**: The security monitor will automatically detect and block suspicious activity
3. **Monitoring**: View real-time security events in the dashboard
4. **Metrics**: Explore security metrics in Grafana and Prometheus

Enjoy exploring the distributed security demo! 🎉 