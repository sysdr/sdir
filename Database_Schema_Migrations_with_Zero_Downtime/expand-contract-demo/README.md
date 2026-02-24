# Database Schema Migrations with Zero Downtime (Expand-Contract Pattern)

Demo for **Article 212** of the System Design Interview Roadmap: zero-downtime database migrations using the expand-contract pattern.

## Prerequisites

- **Docker** and **Docker Compose** (no Node/npm on host required; everything runs in containers)
- Bash
- `curl` (for smoke tests)

## Quick Start (fresh clone)

From the project root (where `expand-contract-demo/` lives):

```bash
git clone <your-repo-url>
cd Database_Schema_Migrations_with_Zero_Downtime
./setup.sh
```

(`setup.sh` at root runs `expand-contract-demo/setup.sh`; demo content is expected in project root.)

After `setup.sh` finishes:

- **Dashboard:** http://localhost:3000  
- **Backend API:** http://localhost:3001  

No need to run `start.sh` or `build.sh` — the demo is already running.

## Scripts

| Script        | Purpose |
|---------------|---------|
| `./setup.sh`  | Create demo, build images, start services, run smoke tests. **Run this first on a new clone.** |
| `./start.sh`  | Start the demo again after you stopped it (e.g. after reboot). |
| `./build.sh`  | Rebuild Docker images only (e.g. after code changes). Run `./start.sh` if the stack is not up. |
| `./test.sh`   | Run API/dashboard smoke tests (demo must be running). |
| `./run-all.sh`| Stop existing demo, run `setup.sh`, then `test.sh`. |
| `./cleanup.sh`| Stop containers, prune unused Docker resources, remove local artifacts (node_modules, venv, .pytest_cache, etc.). |

## Stopping the demo

From the project root:

```bash
./cleanup.sh
```

This stops containers. Run `./setup.sh` again to rebuild and start.

## What this demo does

1. **Expand** — Add new columns (`first_name`, `last_name`) with minimal lock time.
2. **Backfill** — Populate new columns from existing data in batches.
3. **Dual-write** — Application writes to both old and new columns.
4. **Contract** — Drop the old column (`full_name`) with a short lock.

The dashboard shows schema state, column population, lock duration comparison, and sample data.

## License

Use as needed for learning and reference.
