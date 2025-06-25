FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including build tools for psutil
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY templates/ ./templates/
COPY static/ ./static/

# Create directories
RUN mkdir -p logs config

# Set Python path
ENV PYTHONPATH="/app/src:${PYTHONPATH}"

# Expose port
EXPOSE 8000

# Run application
CMD ["python", "src/chaos_engine.py"]
