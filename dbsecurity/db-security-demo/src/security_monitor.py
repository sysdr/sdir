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
