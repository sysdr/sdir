# Federated Learning Architecture Demo

This directory contains a setup script and generated demo sources for a federated-learning architecture (server, clients, and dashboard).

## Main Files

- `setup.sh`: Generates project files and starts the demo stack.
- `cleanup.sh`: Stops containers and prunes Docker resources.
- `requirements.txt`: Root-level Python requirements for local validation usage.
- `.gitignore`: Ignores Python/Node/cache/build artifacts.

## Quick Start

```bash
bash setup.sh
```

Dashboard: `http://localhost:3001`  
API: `http://localhost:8000`

## Cleanup

```bash
bash cleanup.sh
```
