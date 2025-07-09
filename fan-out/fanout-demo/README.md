# Fanout Demo

A demonstration of different fanout strategies for social media feed systems, built with Flask, Redis, and Docker.

## Overview

This project demonstrates two main fanout strategies:
- **Write Fanout**: Pre-computes and stores notifications for all followers when a user posts
- **Read Fanout**: Generates feeds on-demand when users request their timeline

The demo includes real-time metrics, visualizations, and interactive testing capabilities.

## Prerequisites

- Docker
- Docker Compose
- curl (for health checks)

## Quick Start

### Start the Application
```bash
./start.sh
```

This script will:
- Check Docker and Docker Compose availability
- Build the Docker images
- Start the application and Redis services
- Verify the application is accessible
- Open the application in your default browser

### Stop the Application
```bash
./stop.sh
```

This script will:
- Gracefully stop all containers
- Clean up resources
- Provide cleanup options

### Restart the Application
```bash
./restart.sh
```

This script combines stop and start operations for easy restarting.

### Check Application Status
```bash
./status.sh
```

This script shows:
- Container status
- Service information
- Resource usage
- Recent logs
- Available commands

## Services

- **Web Application**: http://localhost:8080
- **Redis**: localhost:6379

## Features

### Interactive Demo
- Post messages as different user types
- View real-time fanout metrics
- Compare write vs read fanout performance
- Monitor backpressure handling

### Visualizations
- Fanout architecture diagrams
- Strategy comparison charts
- Backpressure handling illustrations

### Metrics
- Processing time by strategy
- Fanout operations count
- Active users tracking
- Queue size monitoring

## Project Structure

```
fanout-demo/
├── app/
│   └── main.py              # Flask application
├── config/                  # Configuration files
├── static/
│   ├── css/
│   │   └── style.css       # Styles
│   ├── js/
│   │   └── app.js          # Frontend JavaScript
│   └── *.svg               # Architecture diagrams
├── templates/
│   └── index.html          # Main page template
├── tests/
│   └── test_fanout.py      # Test suite
├── docker-compose.yml       # Docker services
├── Dockerfile              # Application container
├── requirements.txt         # Python dependencies
├── start.sh               # Start script
├── stop.sh                # Stop script
├── restart.sh             # Restart script
├── status.sh              # Status script
└── README.md              # This file
```

## Development

### Running Tests
```bash
python -m pytest tests/
```

### Viewing Logs
```bash
docker-compose logs -f
```

### Accessing Redis CLI
```bash
docker-compose exec redis redis-cli
```

## Cleanup Options

### Remove Volumes (Data)
```bash
docker-compose down -v
```

### Remove Images
```bash
docker-compose down --rmi all
```

### Remove Everything
```bash
docker-compose down -v --rmi all
```

## Troubleshooting

### Application Not Starting
1. Check if Docker is running: `docker info`
2. Verify Docker Compose is installed: `docker-compose --version`
3. Check container logs: `docker-compose logs`
4. Ensure ports 8080 and 6379 are available

### Performance Issues
1. Monitor resource usage: `./status.sh`
2. Check Redis memory usage
3. Review application logs for errors

### Network Issues
1. Verify Docker network connectivity
2. Check firewall settings
3. Ensure no port conflicts

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is for educational and demonstration purposes. 