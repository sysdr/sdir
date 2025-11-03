#!/bin/bash

# Monitor Database Pipeline Status
# Usage: ./monitor-database-pipeline.sh [pipeline-id]

PIPELINE_ID=${1:-""}

if [ -z "$PIPELINE_ID" ]; then
    echo "🔍 Finding latest database pipeline..."
    PIPELINE_ID=$(curl -s http://localhost:3001/api/pipelines | \
        python3 -c "import sys, json; pipes=json.load(sys.stdin); db_pipes=[p for p in pipes if p['service']=='database']; print(sorted(db_pipes, key=lambda x: x['createdAt'], reverse=True)[0]['id'] if db_pipes else '')" 2>/dev/null)
    
    if [ -z "$PIPELINE_ID" ]; then
        echo "❌ No database pipeline found. Triggering a new one..."
        PIPELINE_ID=$(curl -s -X POST http://localhost:3001/api/pipelines/database/trigger \
            -H "Content-Type: application/json" \
            -d '{"commit":"monitor-test","author":"monitor","message":"Pipeline monitoring test"}' | \
            grep -o '"pipelineId":"[^"]*"' | cut -d'"' -f4)
        echo "✅ New pipeline triggered: $PIPELINE_ID"
        sleep 3
    fi
fi

echo "📊 Monitoring Pipeline: $PIPELINE_ID"
echo "=================================="
echo ""

while true; do
    PIPELINE=$(curl -s "http://localhost:3001/api/pipelines/$PIPELINE_ID")
    
    if echo "$PIPELINE" | grep -q '"id"'; then
        STATUS=$(echo "$PIPELINE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        SERVICE=$(echo "$PIPELINE" | grep -o '"service":"[^"]*"' | cut -d'"' -f4)
        CURRENT_STAGE=$(echo "$PIPELINE" | grep -o '"currentStage":[0-9]*' | cut -d':' -f2)
        
        echo -ne "\r\033[K" # Clear line
        echo -n "Status: $STATUS | Service: $SERVICE | Current Stage: $CURRENT_STAGE"
        
        # Get stage details
        STAGES=$(echo "$PIPELINE" | python3 -c "
import sys, json
p = json.load(sys.stdin)
stages = p.get('stages', [])
for i, s in enumerate(stages[:4]):  # Show first 4 stages
    icon = '❌' if s['status'] == 'failed' else '✅' if s['status'] == 'success' else '⏸️' if s['status'] == 'waiting-approval' else '🔄' if s['status'] == 'running' else '⏳'
    print(f\"{icon} {s['name']}: {s['status']}\")
" 2>/dev/null)
        
        if [ "$STATUS" == "completed" ] || [ "$STATUS" == "failed" ]; then
            echo ""
            echo ""
            echo "📋 Final Pipeline Summary:"
            echo "$PIPELINE" | python3 -c "
import sys, json
p = json.load(sys.stdin)
print(f\"Pipeline ID: {p['id']}\")
print(f\"Service: {p['service']}\")
print(f\"Status: {p['status']}\")
print(f\"Created: {p['createdAt']}\")
print(f\"\nStage Details:\")
for s in p['stages']:
    icon = '❌' if s['status'] == 'failed' else '✅' if s['status'] == 'success' else '⏸️' if s['status'] == 'waiting-approval' else '🔄' if s['status'] == 'running' else '⏳'
    print(f\"  {icon} {s['name']}: {s['status']}\")
    if s.get('startTime'):
        print(f\"     Started: {s['startTime']}\")
    if s.get('endTime'):
        print(f\"     Ended: {s['endTime']}\")
    if s.get('securityFindings'):
        print(f\"     Security Findings: {len(s['securityFindings'])} issues\")
        for finding in s['securityFindings']:
            print(f\"       - {finding['severity'].upper()}: {finding['type']} ({finding['count']})\")
" 2>/dev/null
            break
        fi
        
        sleep 2
    else
        echo "❌ Pipeline not found!"
        break
    fi
done

