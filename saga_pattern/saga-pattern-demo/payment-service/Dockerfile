FROM python:3.11-slim
WORKDIR /app
COPY payment-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY payment-service/ .
COPY shared/ /app/shared/
EXPOSE 8001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
