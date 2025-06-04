# Multi-stage build for optimized production container
FROM python:3.11-slim as base

# Set working directory
WORKDIR /app

# Install system dependencies for potential network tools
RUN apt-get update && apt-get install -y \
    curl \
    netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash paxos

# Copy requirements first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY paxos_simulator.py .
COPY start_web_server.py .
COPY web/ ./web/

# Create directories for logs and state with proper permissions
RUN mkdir -p logs state && \
    chown -R paxos:paxos /app

# Switch to non-root user
USER paxos

# Expose port for web interface
EXPOSE 8080

# Health check to ensure the service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Default command runs the simulation
CMD ["python3", "paxos_simulator.py"]
