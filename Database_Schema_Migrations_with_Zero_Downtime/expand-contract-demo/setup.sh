#!/bin/bash
set -euo pipefail

# ============================================================
# Expand-Contract Pattern Demo
# Article 212: Database Schema Migrations with Zero Downtime
# ============================================================
# Only this file lives in expand-contract-demo/; demo content (backend, frontend,
# docker-compose.yml, etc.) lives in project root (parent of this directory).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$DEMO_DIR/docker-compose.yml"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Expand-Contract Pattern — Zero Downtime Migrations     ║"
echo "║   System Design Interview Roadmap — Article 212         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Ensure demo content exists in project root: copy from expand-contract-demo if present
if [ ! -f "$COMPOSE_FILE" ] && [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
  echo "▶  Copying demo content to project root..."
  for dir in backend frontend nginx sql; do
    [ -d "$SCRIPT_DIR/$dir" ] && cp -r "$SCRIPT_DIR/$dir" "$DEMO_DIR/"
  done
  [ -f "$SCRIPT_DIR/docker-compose.yml" ] && cp "$SCRIPT_DIR/docker-compose.yml" "$DEMO_DIR/"
fi
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "❌ docker-compose.yml not found in project root: $DEMO_DIR"
  echo "   Ensure backend/, frontend/, nginx/, sql/, and docker-compose.yml are in the project root."
  exit 1
fi

# Write start.sh and cleanup.sh into project root if missing
if [ ! -f "$DEMO_DIR/start.sh" ]; then
  cat > "$DEMO_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose up -d
echo "Demo services started. Dashboard: http://localhost:3000"
EOF
  chmod +x "$DEMO_DIR/start.sh"
fi

if [ ! -f "$DEMO_DIR/cleanup.sh" ]; then
  cat > "$DEMO_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Stopping containers..."
docker compose down -v --remove-orphans
echo "Cleanup complete."
EOF
  chmod +x "$DEMO_DIR/cleanup.sh"
fi

# Build & Run
echo "▶  Building Docker images..."
cd "$DEMO_DIR"
docker compose build --quiet

echo "▶  Starting services..."
docker compose up -d

echo ""
echo "⏳ Waiting for PostgreSQL to be healthy..."
until docker compose exec -T postgres pg_isready -U postgres -d migrationdb > /dev/null 2>&1; do
  sleep 2
  printf "."
done
echo " ready!"

echo "⏳ Waiting for backend API..."
until curl -sf http://localhost:3001/health > /dev/null 2>&1; do
  sleep 2
  printf "."
done
echo " ready!"

# Quick smoke test
echo ""
echo "▶  Running smoke tests..."
FAIL=0
set +e
sleep 2

STATE=$(curl -sf http://localhost:3001/api/state)
if echo "$STATE" | grep -q "pre_migration"; then
  echo "  ✅ Initial state: pre_migration"
else
  echo "  ❌ State check failed"; FAIL=1
fi

ROW_CHECK=$(echo "$STATE" | grep -o '"full_name":[0-9]*' | grep -o '[0-9]*')
if [ -n "$ROW_CHECK" ] && [ "$ROW_CHECK" -gt "40000" ]; then
  echo "  ✅ Seed data: $ROW_CHECK rows in users table"
else
  echo "  ❌ Seed data check failed (got: ${ROW_CHECK:-none})"
fi

EXP=$(curl -sf -X POST http://localhost:3001/api/migrate/expand -H 'Content-Type: application/json')
if echo "$EXP" | grep -q '"success":true'; then
  echo "  ✅ Expand phase: ADD COLUMN succeeded"
else
  echo "  ❌ Expand phase failed"; FAIL=1
fi

WRT=$(curl -sf -X POST http://localhost:3001/api/simulate/write -H 'Content-Type: application/json')
if echo "$WRT" | grep -q '"success":true'; then
  echo "  ✅ App write simulation: OK"
else
  echo "  ❌ Write simulation failed"; FAIL=1
fi

set -e

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "  ✅ All smoke tests passed"
else
  echo ""
  echo "  ⚠️  Some tests failed — check docker logs"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  🚀 Demo is running! (no need to run start.sh)           ║"
echo "║                                                          ║"
echo "║  UI Dashboard:   http://localhost:3000                   ║"
echo "║  Backend API:    http://localhost:3001/api/state         ║"
echo "║                                                          ║"
echo "║  Start:  bash $DEMO_DIR/start.sh                         ║"
echo "║  Stop:   bash $DEMO_DIR/cleanup.sh                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Done!"
