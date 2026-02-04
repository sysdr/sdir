#!/bin/bash

echo "Validating dashboard metrics..."
FAIL=0

mqtt_json=$(curl -s http://localhost:3001/metrics 2>/dev/null)
if [ -n "$mqtt_json" ]; then
  mqtt_msgs=$(echo "$mqtt_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('messagesReceived',0))" 2>/dev/null || echo "0")
  if [ "$mqtt_msgs" -gt 0 ]; then
    echo "  ✓ MQTT: $mqtt_msgs messages (non-zero)"
  else
    echo "  ✗ MQTT metrics zero - run demo and wait ~5 seconds"
    FAIL=1
  fi
else
  echo "  ✗ MQTT service not reachable"
  FAIL=1
fi

coap_json=$(curl -s http://localhost:3002/metrics 2>/dev/null)
if [ -n "$coap_json" ]; then
  coap_req=$(echo "$coap_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('requestsReceived',0))" 2>/dev/null || echo "0")
  coap_obs=$(echo "$coap_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('activeObservers',0))" 2>/dev/null || echo "0")
  if [ "$coap_req" -gt 0 ]; then
    echo "  ✓ CoAP: $coap_req requests, $coap_obs active observers"
  else
    echo "  ✗ CoAP metrics zero - run demo and wait ~5 seconds"
    FAIL=1
  fi
else
  echo "  ✗ CoAP service not reachable"
  FAIL=1
fi

[ $FAIL -eq 0 ] && echo "Dashboard metrics validation passed!" || exit 1
