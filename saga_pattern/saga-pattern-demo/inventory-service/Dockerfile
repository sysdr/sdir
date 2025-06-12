FROM python:3.11-slim
WORKDIR /app
COPY inventory-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY inventory-service/ .
COPY shared/ /app/shared/
EXPOSE 8002
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
