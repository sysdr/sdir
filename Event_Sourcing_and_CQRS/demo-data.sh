#!/bin/bash

echo "🎬 Generating demo data for dashboard..."
echo "========================================"

BASE_URL="http://localhost:3002"
QUERY_URL="http://localhost:3003"

# Create account 1
echo "Creating account: demo-account-1"
curl -s -X POST ${BASE_URL}/commands/create-account \
  -H "Content-Type: application/json" \
  -d '{"accountId":"demo-account-1","initialBalance":5000}' > /dev/null

sleep 3

# Create account 2
echo "Creating account: demo-account-2"
curl -s -X POST ${BASE_URL}/commands/create-account \
  -H "Content-Type: application/json" \
  -d '{"accountId":"demo-account-2","initialBalance":3000}' > /dev/null

sleep 3

# Deposit to account 1
echo "Depositing $1000 to demo-account-1"
curl -s -X POST ${BASE_URL}/commands/deposit \
  -H "Content-Type: application/json" \
  -d '{"accountId":"demo-account-1","amount":1000}' > /dev/null

sleep 3

# Withdraw from account 1
echo "Withdrawing $500 from demo-account-1"
curl -s -X POST ${BASE_URL}/commands/withdraw \
  -H "Content-Type: application/json" \
  -d '{"accountId":"demo-account-1","amount":500}' > /dev/null

sleep 3

# Transfer from account 1 to account 2
echo "Transferring $200 from demo-account-1 to demo-account-2"
curl -s -X POST ${BASE_URL}/commands/transfer \
  -H "Content-Type: application/json" \
  -d '{"fromAccountId":"demo-account-1","toAccountId":"demo-account-2","amount":200}' > /dev/null

sleep 3

echo ""
echo "✅ Demo data generated!"
echo ""
echo "Dashboard metrics:"
echo "=================="
echo "Accounts:"
curl -s ${QUERY_URL}/accounts | python3 -m json.tool 2>/dev/null || curl -s ${QUERY_URL}/accounts
echo ""
echo ""
echo "Projection Stats:"
curl -s http://localhost:3004/stats | python3 -m json.tool 2>/dev/null || curl -s http://localhost:3004/stats
echo ""
echo ""
echo "Events count:"
EVENTS=$(curl -s http://localhost:3001/events/all/stream | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "N/A")
echo "Total events: $EVENTS"
echo ""
echo "🌐 Open http://localhost:3000 to view the dashboard"




