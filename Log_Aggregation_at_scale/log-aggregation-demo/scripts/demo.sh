#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  Article 214 — Log Aggregation Demo        ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  Dashboard  →  http://localhost:8214"
echo "  Grafana    →  http://localhost:3001  (admin/demo123)"
echo "  Loki API   →  http://localhost:3100/ready"
echo "  ES Health  →  http://localhost:9200/_cluster/health"
echo ""
echo "Quick LogQL queries to try in Grafana:"
echo '  {service="payments"} | json | level="error"'
echo '  rate({job="app_logs"}[1m])'
echo '  {service="auth"} |= "timeout"'
echo ""
echo "To simulate cardinality explosion:"
echo "  Edit load-generator/config.json"
echo "  Set: add_user_id_as_label = true"
echo "  Then: docker-compose restart load-generator"
echo ""
