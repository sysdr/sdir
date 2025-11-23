FROM python:3.11-slim
WORKDIR /app
RUN pip install requests urllib3
COPY generator.py .
CMD ["python", "generator.py"]
