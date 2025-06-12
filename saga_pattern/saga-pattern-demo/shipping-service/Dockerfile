FROM python:3.11-slim
WORKDIR /app
COPY shipping-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY shipping-service/ .
COPY shared/ /app/shared/
EXPOSE 8003
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
