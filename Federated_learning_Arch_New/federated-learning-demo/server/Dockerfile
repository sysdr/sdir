FROM python:3.11-slim
WORKDIR /app
ENV PIP_DEFAULT_TIMEOUT=120
COPY requirements.txt .
RUN pip install --retries 5 --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=5s --retries=20 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
CMD ["python", "main.py"]
