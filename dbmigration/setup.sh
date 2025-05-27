#!/bin/bash

# Zero-Downtime Database Migration Demo Script
# This script demonstrates the concepts of zero-downtime migration by simulating
# a gradual migration process with real-time monitoring and safety mechanisms.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
DEMO_DIR="/tmp/db_migration_demo"
LOG_FILE="${DEMO_DIR}/migration.log"
METRICS_FILE="${DEMO_DIR}/metrics.json"
OLD_DB_FILE="${DEMO_DIR}/old_database.txt"
NEW_DB_FILE="${DEMO_DIR}/new_database.txt"
MIGRATION_STATE_FILE="${DEMO_DIR}/migration_state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Migration configuration
MIGRATION_PERCENTAGE=0
MAX_ERROR_RATE=5.0  # 5% error rate threshold
MAX_LATENCY_MS=200  # 200ms latency threshold
CIRCUIT_BREAKER_THRESHOLD=3

echo_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo_colored "$CYAN" "[$level] $message"
}

setup_demo_environment() {
    echo_colored "$BLUE" "🔧 Setting up migration demo environment..."
    
    # Create demo directory structure
    mkdir -p "$DEMO_DIR"
    
    # Initialize log file
    echo "Migration Demo Started at $(date)" > "$LOG_FILE"
    
    # Initialize old database with sample data
    echo_colored "$YELLOW" "   Setting up legacy database..."
    cat > "$OLD_DB_FILE" << EOF
user_1|John Doe|john@example.com|active
user_2|Jane Smith|jane@example.com|active
user_3|Bob Johnson|bob@example.com|inactive
user_4|Alice Brown|alice@example.com|active
user_5|Charlie Wilson|charlie@example.com|active
EOF
    
    # Initialize new database (empty initially)
    echo_colored "$YELLOW" "   Setting up new database..."
    touch "$NEW_DB_FILE"
    
    # Initialize migration state
    cat > "$MIGRATION_STATE_FILE" << EOF
{
    "migration_percentage": 0,
    "state": "not_started",
    "start_time": "$(date -Iseconds)",
    "total_requests": 0,
    "successful_requests": 0,
    "failed_requests": 0,
    "inconsistencies": 0
}
EOF
    
    # Initialize metrics file
    cat > "$METRICS_FILE" << EOF
{
    "old_db": {
        "total_requests": 0,
        "errors": 0,
        "avg_latency_ms": 0,
        "circuit_breaker_failures": 0
    },
    "new_db": {
        "total_requests": 0,
        "errors": 0,
        "avg_latency_ms": 0,
        "circuit_breaker_failures": 0
    }
}
EOF
    
    echo_colored "$GREEN" "✅ Demo environment setup complete!"
    echo_colored "$CYAN" "   Demo directory: $DEMO_DIR"
    echo_colored "$CYAN" "   Logs: $LOG_FILE"
}

simulate_database_query() {
    local db_type=$1
    local query=$2
    local user_id=$3
    
    # Simulate database latency (new DB is faster)
    local latency_ms
    if [[ "$db_type" == "old" ]]; then
        latency_ms=$((80 + RANDOM % 40))  # 80-120ms
    else
        latency_ms=$((40 + RANDOM % 30))  # 40-70ms
    fi
    
    # Simulate processing time
    sleep $(echo "scale=3; $latency_ms/1000" | bc)
    
    # Simulate occasional errors (5% chance for old DB, 2% for new DB)
    local error_chance
    if [[ "$db_type" == "old" ]]; then
        error_chance=5
    else
        error_chance=2
    fi
    
    if (( RANDOM % 100 < error_chance )); then
        echo "ERROR: Database connection timeout"
        return 1
    fi
    
    # Simulate successful query
    if [[ "$db_type" == "old" ]]; then
        grep "^${user_id}|" "$OLD_DB_FILE" 2>/dev/null || echo "User not found"
    else
        grep "^${user_id}|" "$NEW_DB_FILE" 2>/dev/null || echo "User not found"
    fi
    
    return 0
}

update_metrics() {
    local db_type=$1
    local success=$2
    local latency_ms=$3
    
    # Read current metrics
    local current_metrics=$(cat "$METRICS_FILE")
    
    # Update metrics using jq (if available) or simple append
    if command -v jq >/dev/null 2>&1; then
        local new_metrics=$(echo "$current_metrics" | jq \
            --arg db_type "$db_type" \
            --arg success "$success" \
            --arg latency "$latency_ms" \
            '.[$db_type].total_requests += 1 |
             if $success == "false" then .[$db_type].errors += 1 else . end |
             .[$db_type].avg_latency_ms = ((.[$db_type].avg_latency_ms + ($latency | tonumber)) / 2)')
        
        echo "$new_metrics" > "$METRICS_FILE"
    else
        # Simple logging without jq
        echo "[$db_type] Requests: +1, Success: $success, Latency: ${latency_ms}ms" >> "$LOG_FILE"
    fi
}

should_route_to_new_db() {
    local user_id=$1
    
    # Simple hash-based routing for consistent user experience
    # Handle different systems that might have different md5 commands
    local hash=""
    if command -v md5sum >/dev/null 2>&1; then
        hash=$(echo -n "$user_id" | md5sum | cut -d' ' -f1)
    elif command -v md5 >/dev/null 2>&1; then
        hash=$(echo -n "$user_id" | md5 -q)
    else
        # Fallback to a simple hash if md5 is not available
        hash=$(printf "%s" "$user_id" | od -A n -t x1 | tr -d ' \n' | head -c 8)
    fi
    
    # Convert hex to decimal safely
    local numeric_hash
    if [[ ${#hash} -ge 8 ]]; then
        # Take first 8 characters and convert, handling potential overflow
        local hex_substr="${hash:0:8}"
        numeric_hash=$((16#$hex_substr))
    else
        # Fallback for shorter hashes
        numeric_hash=$((16#$hash))
    fi
    
    local user_percentage=$((numeric_hash % 100))
    
    if (( user_percentage < MIGRATION_PERCENTAGE )); then
        echo "true"
    else
        echo "false"
    fi
}

sync_databases() {
    echo_colored "$YELLOW" "🔄 Synchronizing databases..."
    
    # In dual-write phase, copy data from old to new database
    if [[ -s "$OLD_DB_FILE" ]] && [[ "$MIGRATION_PERCENTAGE" -gt 0 ]]; then
        cp "$OLD_DB_FILE" "$NEW_DB_FILE"
        log_message "INFO" "Database synchronization completed"
        echo_colored "$GREEN" "   ✅ Databases synchronized"
    fi
}

execute_migration_query() {
    local query=$1
    local user_id=$2
    
    # Use a more portable approach for timing
    local start_time_sec=$(date +%s)
    local start_time_ns=0
    
    # Try to get nanoseconds if available, fallback to seconds
    if date +%N >/dev/null 2>&1; then
        start_time_ns=$(date +%N)
    fi
    
    local route_to_new=$(should_route_to_new_db "$user_id")
    local success="true"
    local result=""
    
    log_message "INFO" "Executing query for $user_id (route_to_new: $route_to_new)"
    
    if [[ "$route_to_new" == "true" ]]; then
        # Route to new database
        if result=$(simulate_database_query "new" "$query" "$user_id"); then
            echo_colored "$GREEN" "   ✅ NEW DB: $result"
        else
            echo_colored "$RED" "   ❌ NEW DB: Query failed - $result"
            success="false"
            
            # Fallback to old database
            echo_colored "$YELLOW" "   🔄 Falling back to legacy database..."
            if result=$(simulate_database_query "old" "$query" "$user_id"); then
                echo_colored "$GREEN" "   ✅ OLD DB (fallback): $result"
            else
                echo_colored "$RED" "   ❌ OLD DB (fallback): Query failed - $result"
            fi
        fi
        
        # Calculate latency more safely
        local end_time_sec=$(date +%s)
        local latency_sec=$((end_time_sec - start_time_sec))
        local latency_ms=$((latency_sec * 1000))
        
        # Add some simulated variance for demo purposes
        latency_ms=$((latency_ms + RANDOM % 100 + 50))
        
        update_metrics "new_db" "$success" "$latency_ms"
    else
        # Route to old database
        if result=$(simulate_database_query "old" "$query" "$user_id"); then
            echo_colored "$GREEN" "   ✅ OLD DB: $result"
        else
            echo_colored "$RED" "   ❌ OLD DB: Query failed - $result"
            success="false"
        fi
        
        # Calculate latency more safely
        local end_time_sec=$(date +%s)
        local latency_sec=$((end_time_sec - start_time_sec))
        local latency_ms=$((latency_sec * 1000))
        
        # Add some simulated variance for demo purposes  
        latency_ms=$((latency_ms + RANDOM % 100 + 80))
        
        update_metrics "old_db" "$success" "$latency_ms"
    fi
    
    # In dual-write mode, also write to the other database
    if [[ "$MIGRATION_PERCENTAGE" -gt 0 ]] && [[ "$MIGRATION_PERCENTAGE" -lt 100 ]]; then
        if [[ "$query" =~ ^(INSERT|UPDATE|DELETE) ]]; then
            echo_colored "$CYAN" "   🔄 Dual write: Updating both databases"
            sync_databases
        fi
    fi
}

check_system_health() {
    local current_metrics=""
    
    if [[ -f "$METRICS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        current_metrics=$(cat "$METRICS_FILE")
        
        local old_db_error_rate=$(echo "$current_metrics" | jq -r '.old_db | if .total_requests > 0 then (.errors / .total_requests * 100) else 0 end')
        local new_db_error_rate=$(echo "$current_metrics" | jq -r '.new_db | if .total_requests > 0 then (.errors / .total_requests * 100) else 0 end')
        local old_db_latency=$(echo "$current_metrics" | jq -r '.old_db.avg_latency_ms')
        local new_db_latency=$(echo "$current_metrics" | jq -r '.new_db.avg_latency_ms')
        
        echo_colored "$BLUE" "📊 System Health Check:"
        echo_colored "$CYAN" "   Migration Percentage: ${MIGRATION_PERCENTAGE}%"
        echo_colored "$CYAN" "   Old DB - Error Rate: ${old_db_error_rate}%, Avg Latency: ${old_db_latency}ms"
        echo_colored "$CYAN" "   New DB - Error Rate: ${new_db_error_rate}%, Avg Latency: ${new_db_latency}ms"
        
        # Check if rollback should be triggered
        if (( $(echo "$old_db_error_rate > $MAX_ERROR_RATE" | bc -l) )) || 
           (( $(echo "$new_db_error_rate > $MAX_ERROR_RATE" | bc -l) )) ||
           (( $(echo "$old_db_latency > $MAX_LATENCY_MS" | bc -l) )) ||
           (( $(echo "$new_db_latency > $MAX_LATENCY_MS" | bc -l) )); then
            
            echo_colored "$RED" "🚨 ALERT: Safety thresholds exceeded! Consider rollback."
            log_message "CRITICAL" "Safety thresholds exceeded - Error rates: Old=${old_db_error_rate}%, New=${new_db_error_rate}%"
            return 1
        fi
    else
        echo_colored "$YELLOW" "⚠️  Health check requires 'jq' command for JSON processing"
    fi
    
    return 0
}

gradual_migration() {
    local target_percentage=$1
    local step_size=${2:-10}
    local step_delay=${3:-5}
    
    echo_colored "$PURPLE" "🚀 Starting gradual migration to ${target_percentage}%"
    
    # Sync databases before starting migration
    sync_databases
    
    while (( MIGRATION_PERCENTAGE < target_percentage )); do
        # Increase migration percentage
        MIGRATION_PERCENTAGE=$((MIGRATION_PERCENTAGE + step_size))
        if (( MIGRATION_PERCENTAGE > target_percentage )); then
            MIGRATION_PERCENTAGE=$target_percentage
        fi
        
        echo_colored "$PURPLE" "📈 Migration percentage increased to: ${MIGRATION_PERCENTAGE}%"
        log_message "INFO" "Migration percentage updated to ${MIGRATION_PERCENTAGE}%"
        
        # Simulate some traffic to test the new percentage
        echo_colored "$BLUE" "🔄 Testing with sample traffic..."
        for i in {1..5}; do
            execute_migration_query "SELECT * FROM users" "user_$i"
            sleep 0.5
        done
        
        # Check system health
        if ! check_system_health; then
            echo_colored "$RED" "🚨 Health check failed! Triggering rollback..."
            trigger_rollback "Health check failure at ${MIGRATION_PERCENTAGE}%"
            return 1
        fi
        
        # Wait before next step
        if (( MIGRATION_PERCENTAGE < target_percentage )); then
            echo_colored "$CYAN" "⏳ Waiting ${step_delay} seconds before next step..."
            sleep "$step_delay"
        fi
    done
    
    echo_colored "$GREEN" "🎉 Migration to ${target_percentage}% completed successfully!"
}

trigger_rollback() {
    local reason=$1
    
    echo_colored "$RED" "🔴 ROLLBACK TRIGGERED: $reason"
    log_message "CRITICAL" "ROLLBACK: $reason"
    
    # Reset migration percentage to 0
    MIGRATION_PERCENTAGE=0
    
    echo_colored "$YELLOW" "   📉 Migration percentage reset to 0%"
    echo_colored "$YELLOW" "   🔄 All traffic routed back to legacy database"
    
    # Update state file
    if command -v jq >/dev/null 2>&1; then
        local state_update=$(cat "$MIGRATION_STATE_FILE" | jq \
            --arg reason "$reason" \
            '.migration_percentage = 0 | .state = "rollback" | .rollback_reason = $reason | .rollback_time = now')
        echo "$state_update" > "$MIGRATION_STATE_FILE"
    fi
    
    log_message "INFO" "Rollback completed successfully"
}

demonstrate_circuit_breaker() {
    echo_colored "$PURPLE" "⚡ Demonstrating Circuit Breaker Pattern"
    
    # Simulate high error rate to trigger circuit breaker
    echo_colored "$YELLOW" "   Simulating database failures..."
    
    local failure_count=0
    for i in {1..10}; do
        # Force errors by trying to query non-existent database
        if ! simulate_database_query "new" "SELECT * FROM users" "user_$i" 2>/dev/null; then
            failure_count=$((failure_count + 1))
            echo_colored "$RED" "   ❌ Failure $failure_count"
            
            if (( failure_count >= CIRCUIT_BREAKER_THRESHOLD )); then
                echo_colored "$RED" "🔴 Circuit breaker triggered! Failing fast for subsequent requests."
                break
            fi
        else
            echo_colored "$GREEN" "   ✅ Success"
        fi
        sleep 0.5
    done
    
    echo_colored "$CYAN" "   Circuit breaker demonstration complete"
}

run_comprehensive_demo() {
    echo_colored "$PURPLE" "🎬 Starting Comprehensive Migration Demo"
    echo_colored "$CYAN" "================================================"
    
    # Phase 1: Setup
    setup_demo_environment
    sleep 2
    
    # Phase 2: Test initial state (0% migration)
    echo_colored "$BLUE" "\n📋 Phase 1: Testing Initial State (0% migration)"
    for i in {1..3}; do
        execute_migration_query "SELECT * FROM users" "user_$i"
        sleep 1
    done
    check_system_health
    sleep 2
    
    # Phase 3: Gradual migration to 25%
    echo_colored "$BLUE" "\n📋 Phase 2: Gradual Migration to 25%"
    gradual_migration 25 5 3
    sleep 2
    
    # Phase 4: Test at 25%
    echo_colored "$BLUE" "\n📋 Phase 3: Testing at 25% Migration"
    for i in {1..8}; do
        execute_migration_query "SELECT * FROM users" "user_$i"
        sleep 0.5
    done
    check_system_health
    sleep 2
    
    # Phase 5: Circuit breaker demonstration
    echo_colored "$BLUE" "\n📋 Phase 4: Circuit Breaker Demo"
    demonstrate_circuit_breaker
    sleep 2
    
    # Phase 6: Continue migration to 75%
    echo_colored "$BLUE" "\n📋 Phase 5: Migration to 75%"
    gradual_migration 75 10 2
    sleep 2
    
    # Phase 7: Final health check
    echo_colored "$BLUE" "\n📋 Phase 6: Final Health Check"
    check_system_health
    
    echo_colored "$GREEN" "\n🎉 Demo completed successfully!"
    echo_colored "$CYAN" "Check the logs at: $LOG_FILE"
    echo_colored "$CYAN" "Check the metrics at: $METRICS_FILE"
}

# Command line interface
case "${1:-demo}" in
    "setup")
        setup_demo_environment
        ;;
    "query")
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 query <query> <user_id>"
            exit 1
        fi
        execute_migration_query "$2" "$3"
        ;;
    "migrate")
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 migrate <percentage> [step_size] [delay]"
            exit 1
        fi
        gradual_migration "$2" "${3:-10}" "${4:-5}"
        ;;
    "health")
        check_system_health
        ;;
    "rollback")
        trigger_rollback "${2:-Manual rollback}"
        ;;
    "circuit")
        demonstrate_circuit_breaker
        ;;
    "demo")
        run_comprehensive_demo
        ;;
    "help"|"-h"|"--help")
        echo "Zero-Downtime Database Migration Demo"
        echo ""
        echo "Commands:"
        echo "  demo     - Run complete demonstration (default)"
        echo "  setup    - Setup demo environment"
        echo "  query    - Execute single query: query <query> <user_id>"
        echo "  migrate  - Gradual migration: migrate <percentage> [step] [delay]"
        echo "  health   - Check system health"
        echo "  rollback - Trigger rollback: rollback [reason]"
        echo "  circuit  - Demonstrate circuit breaker"
        echo "  help     - Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac