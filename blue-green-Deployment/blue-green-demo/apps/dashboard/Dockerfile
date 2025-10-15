FROM python:3.11-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache curl

# Install Python dependencies
RUN pip install --no-cache-dir flask requests

# Copy application
COPY dashboard.py .

EXPOSE 5000

CMD ["python", "dashboard.py"]
