FROM python:3.11-slim

WORKDIR /app

# Use CPU-only PyTorch for faster/smaller builds (no ~2GB CUDA deps)
# sentence-transformers>=2.3.0 uses hf_hub_download (compatible with modern deps)
RUN pip install --no-cache-dir \
    "torch==2.5.0+cpu" \
    flask==3.0.0 \
    sentence-transformers>=2.3.0 \
    redis==5.0.1 \
    numpy==1.24.3 \
    gunicorn==21.2.0 \
    --index-url https://download.pytorch.org/whl/cpu \
    --extra-index-url https://pypi.org/simple

COPY app.py .

EXPOSE 5001

# --preload loads models in master before forking workers (avoids worker timeout during boot)
CMD ["gunicorn", "-b", "0.0.0.0:5001", "-w", "2", "--timeout", "120", "--preload", "app:app"]
