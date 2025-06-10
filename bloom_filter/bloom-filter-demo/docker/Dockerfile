FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and maintain directory structure
COPY src/ ./src/
COPY templates/ ./templates/
COPY static/ ./static/
COPY tests/ ./tests/

# Create logs directory
RUN mkdir -p /app/logs

# Debug: List directory structure for troubleshooting
RUN echo "=== Directory Structure ===" && \
    find /app -type f -name "*.py" -o -name "*.html" | head -20 && \
    echo "=== Template Directory ===" && \
    ls -la /app/templates/ || echo "Templates directory not found"

EXPOSE 8080

# Set Python path to include src directory
ENV PYTHONPATH="/app/src:${PYTHONPATH}"

CMD ["python", "src/app.py"]
