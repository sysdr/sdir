#!/bin/bash

echo "🧪 Testing Dashboard Metrics Update"
echo "===================================="

# Function to execute query and log to dashboard
execute_query() {
    local query=$1
    local operation=$2
    local services=$3
    
    echo ""
    echo "📊 Executing: $operation"
    echo "   Services: $services"
    
    local start_time=$(date +%s%3N)
    
    # Execute query
    response=$(curl -s -X POST http://localhost:4000/graphql \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"$query\"}")
    
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    # Log to dashboard
    curl -s -X POST http://localhost:3000/log-query \
        -H "Content-Type: application/json" \
        -d "{\"operation\":\"$operation\",\"services\":$services,\"responseTime\":$response_time}" > /dev/null
    
    echo "   ✅ Response time: ${response_time}ms"
    
    # Check if response has data
    if echo "$response" | grep -q '"data"'; then
        echo "   ✅ Query successful"
    else
        echo "   ❌ Query failed: $response"
    fi
}

# Wait for dashboard to be ready
echo "⏳ Waiting for dashboard to be ready..."
sleep 2

# Execute test queries
execute_query "query GetUsers { users { id name email joinDate } }" \
    "GetUsers" \
    '["users"]'

execute_query "query GetProductsWithReviews { products { id name price reviews { rating comment date } avgRating reviewCount } }" \
    "GetProductsWithReviews" \
    '["products","reviews"]'

execute_query "query GetUserWithReviews { user(id: \\\"1\\\") { id name email reviews { rating comment date } } }" \
    "GetUserWithReviews" \
    '["users","reviews"]'

execute_query "query ComplexFederation { users { id name reviews { rating } } products { id name price reviews { rating author { name email } } avgRating } }" \
    "ComplexFederation" \
    '["users","products","reviews"]'

# Execute a few more queries to ensure metrics update
for i in {1..3}; do
    execute_query "query GetUsers { users { id name } }" \
        "GetUsers" \
        '["users"]'
    sleep 1
done

echo ""
echo "✅ Dashboard test queries completed!"
echo ""
echo "📊 Check dashboard at http://localhost:3000"
echo "   Metrics should show:"
echo "   - Total Queries > 0"
echo "   - Avg Response Time > 0ms"
echo "   - Service Invocations > 0 for each service"

