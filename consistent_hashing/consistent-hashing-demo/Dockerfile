FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000 6379

CMD ["sh", "-c", "redis-server --daemonize yes && python src/app.py"]
