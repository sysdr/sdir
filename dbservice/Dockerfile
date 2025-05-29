FROM python:3.9-slim

# Set environment variables for container compatibility
ENV TERM=xterm-256color
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bc \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy and setup the script
COPY dbaas_circuit_breaker.sh /app/
RUN chmod +x dbaas_circuit_breaker.sh

# Expose the web port
EXPOSE 8080

# Health check to ensure the service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/api/status || exit 1

# Run the circuit breaker system
CMD ["./dbaas_circuit_breaker.sh"]