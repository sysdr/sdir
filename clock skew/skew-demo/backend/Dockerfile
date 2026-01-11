FROM python:3.11-slim-bullseye
WORKDIR /app
# Install dependencies. Using Flask and Flask-CORS.
RUN pip install --no-cache-dir flask flask-cors
COPY app.py .
# Command to run the application
CMD ["python", "app.py"]
