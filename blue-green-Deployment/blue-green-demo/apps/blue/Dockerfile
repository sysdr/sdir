FROM python:3.11-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache curl gcc python3-dev musl-dev linux-headers

# Install Python dependencies
RUN pip install --no-cache-dir flask psutil

# Copy application
COPY app.py .

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

EXPOSE 5000

CMD ["python", "app.py"]
