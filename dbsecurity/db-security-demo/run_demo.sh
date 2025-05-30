#!/bin/bash
echo "🚀 Starting Database Security Demo..."

# Ensure Python dependencies are available
python3 -c "import cryptography" 2>/dev/null || {
    echo "📦 Installing required Python packages..."
    pip3 install cryptography --user
}

# Create logs directory
mkdir -p logs

echo "🔐 Running security demonstration..."
python3 src/security_middleware.py

echo -e "\n📊 Analyzing security logs..."
python3 src/security_monitor.py

echo -e "\n📋 Demo completed! Check logs/authorization.log for detailed audit trail"
echo "💡 Try modifying config/access_policies.json to test different security policies"
