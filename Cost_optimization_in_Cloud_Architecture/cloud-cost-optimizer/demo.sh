#!/bin/bash
# demo.sh — Run demonstration scenarios
set -e
BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'; BOLD='\033[1m'

echo -e "${BOLD}${BLUE}Cloud Cost Optimizer — Demo Scenarios${NC}\n"

BASE="http://localhost:3000"

# Scenario 1: Check current state
echo -e "1. ${BOLD}Current fleet state${NC}"
curl -s "$BASE/api/state" | node -e "
  const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  const m = d.metrics;
  console.log('  Active instances:', m.activeCount);
  console.log('  Reserved:', m.reservedCount, '| On-Demand:', m.onDemandCount, '| Spot:', m.spotCount);
  console.log('  Effective cost: \$' + m.totalEffectiveHr.toFixed(2) + '/hr');
  console.log('  Overall savings: ' + m.savingsPercent + '%');
  console.log('  Monthly estimate: \$' + m.monthlyCost.toFixed(0));
"

echo ""

# Scenario 2: Force a Spot interruption
echo -e "2. ${BOLD}Triggering Spot interruption${NC}"
curl -s -X POST "$BASE/api/interrupt" | node -e "
  const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  if (d.ok) {
    console.log('  ⚠ Interrupted: ' + d.instanceId + ' (' + d.family + ')');
    console.log('  2-minute drain window started — watch the dashboard');
  } else {
    console.log('  No Spot instances available:', d.message);
  }
"

echo ""
sleep 2

# Scenario 3: Scale up Spot
echo -e "3. ${BOLD}Scaling up Spot fleet (+3 instances)${NC}"
curl -s -X POST "$BASE/api/fleet" \
  -H "Content-Type: application/json" \
  -d '{"spotDelta":3}' | node -e "
  const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  const m = d.state;
  console.log('  Spot count:', m.spotCount);
  console.log('  New effective cost: \$' + m.totalEffectiveHr.toFixed(2) + '/hr');
  console.log('  New savings: ' + m.savingsPercent + '%');
"

echo ""

# Scenario 4: Shift to more Reserved
echo -e "4. ${BOLD}Adding Reserved capacity (+2)${NC}"
curl -s -X POST "$BASE/api/fleet" \
  -H "Content-Type: application/json" \
  -d '{"reservedDelta":2}' | node -e "
  const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
  const m = d.state;
  console.log('  Reserved count:', m.reservedCount);
  console.log('  Effective cost: \$' + m.totalEffectiveHr.toFixed(2) + '/hr');
  console.log('  Savings: ' + m.savingsPercent + '%');
"

echo -e "\n${GREEN}Demo complete. Dashboard: http://localhost:3000${NC}"
