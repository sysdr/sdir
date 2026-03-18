# Prompt Caching Demo

Section 9: AI & LLM Infrastructure — demo for prompt caching cost and latency.

## Quick start

1. **Prerequisites:** Docker, Docker Compose.
2. **Setup** (run from parent directory):
   ```bash
   cd .. && ./setup.sh
   ```
3. **Start** (from this directory):
   ```bash
   ./start.sh
   ```
4. **Dashboard:** http://localhost:4210
5. **Optional:** Add `ANTHROPIC_API_KEY` to `.env` for live API; set `DEMO_MOCK=false` to use it. With `DEMO_MOCK=true` (default), the dashboard runs with simulated answers and no API credits.

## Scripts (run from this directory)

| Script        | Description |
|---------------|-------------|
| `./start.sh`  | Start the demo stack. |
| `./cleanup.sh`| Stop containers, remove unused Docker resources, and clean node_modules/venv/.pytest_cache/.pyc/Istio. |
| `./demo.sh`   | Open dashboard URL in browser. |

## Cleanup

```bash
./cleanup.sh
```

To stop the Docker daemon (optional): `sudo systemctl stop docker`

## Layout

- `backend/` — Node.js API (Anthropic, Redis, metrics).
- `frontend/` — React + Vite UI.
- `nginx/` — Reverse proxy.
- `docker-compose.yml` — Redis, backend, frontend, nginx.
