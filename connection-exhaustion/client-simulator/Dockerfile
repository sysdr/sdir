FROM python:3.11-slim
WORKDIR /app
RUN pip install aiohttp
COPY simulator.py .
CMD ["python", "simulator.py", "http://haproxy:8080", "50"]
