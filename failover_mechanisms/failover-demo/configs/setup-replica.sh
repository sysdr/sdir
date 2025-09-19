#!/bin/bash
set -e

if [ -z "$(ls -A /var/lib/postgresql/data)" ]; then
    echo "Setting up streaming replication..."
    PGPASSWORD=replica123 pg_basebackup -h postgres-primary -D /var/lib/postgresql/data -U replicator -v -P -W
    
    cat > /var/lib/postgresql/data/recovery.conf << RECOVERY_EOF
standby_mode = 'on'
primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=replica123'
RECOVERY_EOF
    
    chown postgres:postgres /var/lib/postgresql/data/recovery.conf
fi
