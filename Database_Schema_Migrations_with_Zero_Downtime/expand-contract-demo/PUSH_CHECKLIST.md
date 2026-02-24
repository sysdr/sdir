# GitHub Push Checklist (Production-Ready)

Use this checklist before pushing. Generated from DevOps/Git audit.

## ✅ Files TO PUSH (minimal set)

- `README.md` — Required for clone-and-run instructions
- `setup.sh` — Required; generates the full demo (no secrets; generic paths)
- `build.sh` — Rebuild images only
- `start.sh` — Start demo from project root
- `test.sh` — Smoke tests
- `run-all.sh` — Full cycle: stop, setup, test
- `cleanup.sh` — Stop containers, prune Docker, remove local artifacts
- `.gitignore` — Ensures no secrets/artifacts committed

## ❌ Files/folders MUST NOT PUSH (enforced by .gitignore)

- `expand-contract-demo/` (except `expand-contract-demo/setup.sh`) — Demo content lives in project root; only `setup.sh` stays in `expand-contract-demo/`
- `.env`, `.env.*`, `secrets/`, `*.pem`, `*.key`
- `node_modules/`, `venv/`, `.venv/`
- `dist/`, `build/`, `__pycache__/`, `.pytest_cache/`, `*.pyc`
- `*.log`, `logs/`, `tmp/`, `temp/`
- `.DS_Store`, `Thumbs.db`, `.idea/`, `.vscode/`

## ⚠️ Review before pushing

- Run `git status` and confirm no files from the "MUST NOT PUSH" list are staged.
- Run `./setup.sh` once from project root to confirm it completes; then run `./test.sh` to verify.

## After push: fresh machine

1. Clone the repo.
2. Install Docker (and Docker Compose).
3. Run `./setup.sh`.
4. Open http://localhost:3000 — dashboard should run.

No `.env` or API keys required; default Postgres password is demo-only and documented in README.
