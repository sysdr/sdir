FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    iproute2 \
    iputils-ping \
    iperf3 \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ .

# Add capabilities for network manipulation
CMD ["python", "dashboard.py"]
