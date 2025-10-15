FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Set Python path
ENV PYTHONPATH=/app

EXPOSE 8001 8002 8003 8080

CMD ["python", "-c", "print('Container ready')"]
