FROM python:3.11-slim
WORKDIR /app
COPY web-ui/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY web-ui/ .
EXPOSE 5000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "5000"]
