FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
# Copy templates and static files to src directory for Flask app
RUN cp -r templates src/ && cp -r static src/

EXPOSE 5000 8050

CMD ["python", "src/app.py"]
