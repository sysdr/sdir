#!/bin/bash

# Chaos Engineering Tests for Two-Phase Commit
echo "🔥 Running Chaos Engineering Tests"

# Function to simulate network partition
simulate_network_partition() {
    echo "🌐 Simulating network partition for payment-service..."
    
    # Block traffic to payment-service (requires docker network manipulation)
    docker exec two-phase-commit-demo_payment-service_1 \
        sh -c "iptables -A INPUT -p tcp --dport 8000 -j DROP" 2>/dev/null || \
        echo "⚠️  Network partition simulation requires privileged container access"
    
    sleep 10
    
    # Restore network
    docker exec two-phase-commit-demo_payment-service_1 \
        sh -c "iptables -F" 2>/dev/null || \
        echo "⚠️  Network restoration requires privileged container access"
}

# Function to simulate coordinator failure
simulate_coordinator_failure() {
    echo "💥 Simulating coordinator failure..."
    
    # Stop coordinator
    docker-compose stop coordinator
    
    sleep 15
    
    # Restart coordinator
    docker-compose start coordinator
    
    # Wait for recovery
    sleep 10
}

# Function to simulate participant failure
simulate_participant_failure() {
    echo "⚡ Simulating participant failure..."
    
    # Stop inventory service during transaction
    docker-compose stop inventory-service &
    
    # Start transaction immediately
    curl -X POST "http://localhost:8000/transaction" \
        -H "Content-Type: application/json" \
        -d '{
            "participants": ["payment-service", "inventory-service", "shipping-service"],
            "operation_data": {
                "amount": 150,
                "product": "phone",
                "quantity": 1,
                "shipping_address": "456 Chaos Lane"
            }
        }'
    
    sleep 5
    
    # Restart inventory service
    docker-compose start inventory-service
}

# Function to run load test
run_load_test() {
    echo "⚡ Running load test..."
    
    # Start 20 concurrent transactions
    for i in {1..20}; do
        curl -X POST "http://localhost:8000/transaction" \
            -H "Content-Type: application/json" \
            -d "{
                \"participants\": [\"payment-service\", \"inventory-service\", \"shipping-service\"],
                \"operation_data\": {
                    \"amount\": $((RANDOM % 500 + 50)),
                    \"product\": \"laptop\",
                    \"quantity\": $((RANDOM % 3 + 1)),
                    \"shipping_address\": \"Load Test Address $i\"
                }
            }" &
    done
    
    wait
    echo "Load test completed"
}

echo "Select chaos test to run:"
echo "1. Network Partition"
echo "2. Coordinator Failure"
echo "3. Participant Failure" 
echo "4. Load Test"
echo "5. All Tests"

read -p "Enter choice (1-5): " choice

case $choice in
    1) simulate_network_partition ;;
    2) simulate_coordinator_failure ;;
    3) simulate_participant_failure ;;
    4) run_load_test ;;
    5) 
        simulate_participant_failure
        sleep 30
        simulate_coordinator_failure
        sleep 30
        run_load_test
        ;;
    *) echo "Invalid choice" ;;
esac

echo "🔥 Chaos testing completed!"
