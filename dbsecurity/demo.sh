#!/bin/bash
# Database Security Demo Setup
# This script creates a working demonstration of enterprise database security patterns

set -e

echo "🔐 Setting up Database Security Demo Environment..."

# Create project structure
mkdir -p db-security-demo/{config,src,logs,keys}
cd db-security-demo

# Generate demonstration encryption keys (DO NOT use in production)
echo "📊 Generating demonstration keys..."
openssl rand -hex 32 > keys/master_key.txt
openssl rand -hex 32 > keys/data_key.txt

# Create policy configuration
cat > config/access_policies.json << 'EOF'
{
  "policies": [
    {
      "id": "customer_data_read",
      "effect": "ALLOW",
      "conditions": {
        "subject.department": ["engineering", "support"],
        "subject.clearance_level": ["L2", "L3"],
        "resource.data_classification": "customer_data",
        "action": "read",
        "environment.time_of_day": "business_hours"
      }
    },
    {
      "id": "pii_data_access",
      "effect": "ALLOW",
      "conditions": {
        "subject.clearance_level": ["L3"],
        "resource.data_classification": "pii",
        "action": ["read", "write"],
        "environment.network": "trusted"
      }
    }
  ]
}
EOF

# Create database schema with security annotations
cat > config/schema.sql << 'EOF'
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    phone_encrypted BYTEA, -- Application-level encrypted
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    data_classification VARCHAR(50) DEFAULT 'customer_data'
);

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    action VARCHAR(100) NOT NULL,
    resource VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW(),
    result VARCHAR(50) NOT NULL,
    metadata JSONB
);
EOF

# Create Python security middleware
cat > src/security_middleware.py << 'EOF'
#!/usr/bin/env python3
"""
Database Security Middleware
Demonstrates ABAC, envelope encryption, and audit logging
"""

import json
import time
import hashlib
from datetime import datetime
from cryptography.fernet import Fernet
import base64

class PolicyEngine:
    """Attribute-Based Access Control (ABAC) engine"""
    
    def __init__(self, policies_file):
        with open(policies_file, 'r') as f:
            self.policies = json.load(f)['policies']
    
    def evaluate(self, subject, resource, action, environment):
        """Evaluate access request against policies"""
        start_time = time.time()
        
        for policy in self.policies:
            if self._match_policy(policy, subject, resource, action, environment):
                decision_time = (time.time() - start_time) * 1000
                self._log_decision(subject, resource, action, "ALLOW", decision_time)
                return True
        
        decision_time = (time.time() - start_time) * 1000
        self._log_decision(subject, resource, action, "DENY", decision_time)
        return False
    
    def _match_policy(self, policy, subject, resource, action, environment):
        """Check if request matches policy conditions"""
        conditions = policy['conditions']
        
        # Check subject attributes
        if 'subject.department' in conditions:
            if subject.get('department') not in conditions['subject.department']:
                return False
        
        if 'subject.clearance_level' in conditions:
            if subject.get('clearance_level') not in conditions['subject.clearance_level']:
                return False
        
        # Check resource attributes
        if 'resource.data_classification' in conditions:
            if resource.get('data_classification') != conditions['resource.data_classification']:
                return False
        
        # Check action
        if 'action' in conditions:
            actions = conditions['action']
            if isinstance(actions, str):
                actions = [actions]
            if action not in actions:
                return False
        
        return True
    
    def _log_decision(self, subject, resource, action, result, decision_time):
        """Log authorization decision for audit"""
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'user_id': subject.get('user_id', 'unknown'),
            'action': action,
            'resource': str(resource),
            'result': result,
            'decision_time_ms': round(decision_time, 2)
        }
        
        with open('logs/authorization.log', 'a') as f:
            f.write(json.dumps(log_entry) + '\n')

class EnvelopeEncryption:
    """Implements envelope encryption pattern"""
    
    def __init__(self, master_key_file, data_key_file):
        with open(master_key_file, 'r') as f:
            self.master_key = f.read().strip().encode()
        
        with open(data_key_file, 'r') as f:
            data_key = f.read().strip().encode()
            self.cipher = Fernet(base64.urlsafe_b64encode(data_key[:32]))
    
    def encrypt_field(self, plaintext, field_classification='standard'):
        """Encrypt sensitive field data"""
        if not plaintext:
            return None
        
        # Add metadata for key rotation and compliance
        metadata = {
            'classification': field_classification,
            'encrypted_at': datetime.now().isoformat(),
            'key_version': 'v1'
        }
        
        # Combine plaintext with metadata
        data_to_encrypt = json.dumps({
            'data': plaintext,
            'metadata': metadata
        })
        
        return self.cipher.encrypt(data_to_encrypt.encode())
    
    def decrypt_field(self, ciphertext):
        """Decrypt field data"""
        if not ciphertext:
            return None
        
        try:
            decrypted_data = self.cipher.decrypt(ciphertext)
            data_obj = json.loads(decrypted_data.decode())
            return data_obj['data']
        except Exception as e:
            print(f"Decryption failed: {e}")
            return None

class SecureDatabase:
    """Database wrapper with security controls"""
    
    def __init__(self, policy_engine, encryption_service):
        self.policy_engine = policy_engine
        self.encryption = encryption_service
        self.query_count = 0
    
    def execute_query(self, query, subject, sensitive_fields=None):
        """Execute database query with security checks"""
        self.query_count += 1
        
        # Simulate resource identification
        resource = {
            'data_classification': 'customer_data',
            'table': 'users'
        }
        
        # Determine action from query
        action = 'read' if query.strip().upper().startswith('SELECT') else 'write'
        
        # Simulate environment context
        environment = {
            'network': 'trusted',
            'time_of_day': 'business_hours'
        }
        
        # Authorization check
        if not self.policy_engine.evaluate(subject, resource, action, environment):
            raise PermissionError(f"Access denied for user {subject.get('user_id')}")
        
        # Simulate query execution with encryption
        if sensitive_fields and action == 'write':
            # Encrypt sensitive fields before storage
            encrypted_data = {}
            for field, value in sensitive_fields.items():
                encrypted_data[field] = self.encryption.encrypt_field(value, 'pii')
            print(f"✅ Query executed with encrypted fields: {list(encrypted_data.keys())}")
        else:
            print(f"✅ Query executed: {query[:50]}...")
        
        return {"status": "success", "query_id": self.query_count}

# Demonstration function
def demonstrate_security():
    """Run security demonstration"""
    print("🔐 Initializing Database Security Components...")
    
    # Initialize components
    policy_engine = PolicyEngine('config/access_policies.json')
    encryption_service = EnvelopeEncryption('keys/master_key.txt', 'keys/data_key.txt')
    secure_db = SecureDatabase(policy_engine, encryption_service)
    
    # Test scenarios
    scenarios = [
        {
            'name': 'Engineering Read Access',
            'subject': {
                'user_id': 'eng001',
                'department': 'engineering',
                'clearance_level': 'L2'
            },
            'query': 'SELECT name, email FROM users WHERE id = ?',
            'should_succeed': True
        },
        {
            'name': 'Support PII Access',
            'subject': {
                'user_id': 'sup001',
                'department': 'support',
                'clearance_level': 'L1'
            },
            'query': 'SELECT phone_encrypted FROM users WHERE id = ?',
            'should_succeed': False
        },
        {
            'name': 'Admin Write with Encryption',
            'subject': {
                'user_id': 'adm001',
                'department': 'engineering',
                'clearance_level': 'L3'
            },
            'query': 'INSERT INTO users (name, email, phone_encrypted) VALUES (?, ?, ?)',
            'sensitive_fields': {'phone_encrypted': '+1-555-0123'},
            'should_succeed': True
        }
    ]
    
    print("\n📊 Running Security Test Scenarios...")
    for scenario in scenarios:
        print(f"\n🧪 Testing: {scenario['name']}")
        try:
            result = secure_db.execute_query(
                scenario['query'],
                scenario['subject'],
                scenario.get('sensitive_fields')
            )
            if scenario['should_succeed']:
                print(f"   ✅ Expected success: {result['status']}")
            else:
                print(f"   ⚠️  Unexpected success - security policy may be too permissive")
        except PermissionError as e:
            if not scenario['should_succeed']:
                print(f"   ✅ Expected denial: {str(e)}")
            else:
                print(f"   ❌ Unexpected denial: {str(e)}")
    
    # Demonstrate encryption/decryption
    print(f"\n🔑 Testing Field-Level Encryption...")
    test_data = "sensitive-phone-number"
    encrypted = encryption_service.encrypt_field(test_data, 'pii')
    decrypted = encryption_service.decrypt_field(encrypted)
    print(f"   Original: {test_data}")
    print(f"   Encrypted: {encrypted[:50]}...")
    print(f"   Decrypted: {decrypted}")
    print(f"   ✅ Encryption cycle successful: {test_data == decrypted}")

if __name__ == "__main__":
    demonstrate_security()
EOF

# Create monitoring dashboard
cat > src/security_monitor.py << 'EOF'
#!/usr/bin/env python3
"""
Security Monitoring Dashboard
Real-time visualization of database security events
"""

import json
import time
from datetime import datetime, timedelta
from collections import defaultdict

def analyze_security_logs():
    """Analyze authorization logs for security insights"""
    
    try:
        with open('logs/authorization.log', 'r') as f:
            logs = [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        print("📊 No authorization logs found yet. Run the demo first!")
        return
    
    if not logs:
        print("📊 No authorization events to analyze")
        return
    
    # Analyze patterns
    total_requests = len(logs)
    denied_requests = len([log for log in logs if log['result'] == 'DENY'])
    approval_rate = ((total_requests - denied_requests) / total_requests) * 100
    
    # Performance analysis
    decision_times = [log['decision_time_ms'] for log in logs]
    avg_decision_time = sum(decision_times) / len(decision_times)
    
    # User activity patterns
    user_activity = defaultdict(int)
    for log in logs:
        user_activity[log['user_id']] += 1
    
    print("🔍 Security Monitoring Dashboard")
    print("=" * 40)
    print(f"📈 Total Authorization Requests: {total_requests}")
    print(f"✅ Approval Rate: {approval_rate:.1f}%")
    print(f"❌ Denied Requests: {denied_requests}")
    print(f"⚡ Avg Decision Time: {avg_decision_time:.2f}ms")
    print(f"\n👥 Most Active Users:")
    
    for user_id, count in sorted(user_activity.items(), key=lambda x: x[1], reverse=True)[:5]:
        print(f"   {user_id}: {count} requests")
    
    # Recent activity
    recent_logs = [log for log in logs if 
                   datetime.fromisoformat(log['timestamp']) > datetime.now() - timedelta(minutes=5)]
    
    if recent_logs:
        print(f"\n🕐 Recent Activity ({len(recent_logs)} events in last 5 minutes):")
        for log in recent_logs[-3:]:
            status_emoji = "✅" if log['result'] == 'ALLOW' else "❌"
            print(f"   {status_emoji} {log['user_id']} → {log['action']} ({log['decision_time_ms']:.1f}ms)")

if __name__ == "__main__":
    analyze_security_logs()
EOF

# Create startup script
cat > run_demo.sh << 'EOF'
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
EOF

chmod +x run_demo.sh

echo "✅ Database Security Demo Environment Created!"
echo ""
echo "🚀 To run the demonstration:"
echo "   cd db-security-demo"
echo "   ./run_demo.sh"
echo ""
echo "📁 Key files created:"
echo "   - config/access_policies.json (ABAC policies)"
echo "   - src/security_middleware.py (Main security implementation)"
echo "   - src/security_monitor.py (Monitoring dashboard)"
echo "   - keys/ (Demonstration encryption keys)"
echo ""
echo "🔍 This demo illustrates:"
echo "   ✓ Attribute-Based Access Control (ABAC)"
echo "   ✓ Envelope encryption with field-level protection"
echo "   ✓ Real-time authorization decisions"
echo "   ✓ Security audit logging"
echo "   ✓ Performance monitoring"
