FROM python:3.11-slim
WORKDIR /app
ENV PIP_DEFAULT_TIMEOUT=120
COPY requirements.txt .
RUN pip install --retries 5 --no-cache-dir -r requirements.txt
COPY client.py .
CMD ["python", "client.py"]
