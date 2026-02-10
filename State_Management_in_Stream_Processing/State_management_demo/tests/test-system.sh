#!/bin/bash
set -e
cd "$(dirname "$0")/.."
PASS=0 FAIL=0
if curl -sf --connect-timeout 5 http://localhost:3000 >/dev/null; then echo "PASS: Dashboard"; PASS=$((PASS+1)); else echo "FAIL: Dashboard"; FAIL=$((FAIL+1)); fi
if curl -sf --connect-timeout 5 http://localhost:8081 >/dev/null; then echo "PASS: Flink UI"; PASS=$((PASS+1)); else echo "FAIL: Flink UI"; FAIL=$((FAIL+1)); fi
echo ""
echo "Tests: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
