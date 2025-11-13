import psycopg2
import schedule
import time
import json
from datetime import datetime

def connect_db():
    return psycopg2.connect(
        host="postgres",
        database="gdpr_db",
        user="postgres",
        password="postgres"
    )

def enforce_retention():
    conn = connect_db()
    cur = conn.cursor()
    
    # Delete expired analytics data
    cur.execute("""
        DELETE FROM user_analytics 
        WHERE retention_until < NOW()
        RETURNING id, user_id, event_type
    """)
    
    deleted = cur.fetchall()
    
    if deleted:
        print(f"🗑️  Retention enforced: Deleted {len(deleted)} analytics records")
        
        # Log to audit
        for record in deleted:
            cur.execute("""
                INSERT INTO audit_log (user_id, action, details)
                VALUES (%s, %s, %s)
            """, (record[1], 'RETENTION_ENFORCED', json.dumps({'record_id': record[0], 'event_type': record[2]})))
    
    conn.commit()
    cur.close()
    conn.close()

def check_consent_compliance():
    conn = connect_db()
    cur = conn.cursor()
    
    # Check for users with withdrawn marketing consent but still in marketing analytics
    cur.execute("""
        SELECT DISTINCT ua.user_id
        FROM user_analytics ua
        JOIN consent_events ce ON ua.user_id = ce.user_id
        WHERE ce.consent_type = 'marketing'
        AND ce.status = 'withdrawn'
        AND ua.event_type LIKE '%marketing%'
    """)
    
    violations = cur.fetchall()
    
    if violations:
        print(f"⚠️  Consent compliance check: Found {len(violations)} potential violations")
    
    cur.close()
    conn.close()

print("🔒 Retention Service Started")
schedule.every(30).seconds.do(enforce_retention)
schedule.every(1).minutes.do(check_consent_compliance)

while True:
    schedule.run_pending()
    time.sleep(1)
