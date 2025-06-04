FROM python:3.9-slim

WORKDIR /app

# Install dependencies including curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install requests

COPY quorum_node.py .
COPY test_scenarios.py .

# Create logs directory
RUN mkdir -p logs

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/status || exit 1

EXPOSE 8080

# Use environment variables for configuration
CMD python3 quorum_node.py
