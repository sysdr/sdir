# Federated Learning Architecture Demo

This directory contains a RAG pipeline demo with:
- FastAPI backend (`backend/`)
- React frontend served by Nginx (`frontend/`)
- Document corpus (`docs/`)
- Docker Compose orchestration (`docker-compose.yml`)

## Quick Start

```bash
./start.sh
```

Dashboard: `http://localhost:3000`  
API: `http://localhost:8000`  
API Docs: `http://localhost:8000/docs`

## Run Tests

```bash
./test.sh
```

## Demo Helper

```bash
./demo.sh
```

## Cleanup

```bash
./cleanup.sh
```

This stops containers and prunes unused Docker containers, images, volumes, and networks.
