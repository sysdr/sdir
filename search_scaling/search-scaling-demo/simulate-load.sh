#!/bin/bash

# Search Scaling Demo - Load Simulation Script
# This script simulates realistic search load to demonstrate performance differences

set -e  # Exit on any error

echo "🔍 Search Load Simulation"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_demo() {
    echo -e "${PURPLE}[DEMO]${NC} $1"
}

print_performance() {
    echo -e "${CYAN}[PERF]${NC} $1"
}

# Check if demo is running
check_demo_running() {
    print_status "Checking if demo is running..."
    
    if ! curl -s http://localhost:5000/health > /dev/null 2>&1; then
        print_error "Demo is not running. Please start it first with './start-demo.sh'"
        exit 1
    fi
    
    print_success "Demo is running and accessible"
}

# Generate search queries
generate_queries() {
    local query_type=$1
    local count=$2
    
    case $query_type in
        "technology")
            queries=("artificial intelligence" "machine learning" "cloud computing" "blockchain" "cybersecurity" "data science" "web development" "mobile apps" "devops" "microservices")
            ;;
        "business")
            queries=("startup funding" "market analysis" "business strategy" "digital transformation" "customer acquisition" "revenue growth" "competitive analysis" "product management" "sales strategy" "venture capital")
            ;;
        "science")
            queries=("quantum physics" "climate change" "genetic engineering" "space exploration" "renewable energy" "biotechnology" "neuroscience" "nanotechnology" "astronomy" "chemistry")
            ;;
        "health")
            queries=("mental health" "nutrition" "exercise" "medical research" "public health" "telemedicine" "vaccines" "mental wellness" "fitness" "healthcare technology")
            ;;
        "education")
            queries=("online learning" "educational technology" "curriculum design" "student engagement" "distance education" "learning analytics" "teaching methods" "academic research" "skill development" "educational psychology")
            ;;
        "random")
            queries=("innovation" "sustainability" "leadership" "creativity" "collaboration" "problem solving" "communication" "adaptation" "growth" "excellence")
            ;;
        *)
            queries=("technology" "business" "science" "health" "education" "innovation" "research" "development" "analysis" "strategy")
            ;;
    esac
    
    # Return random queries from the selected category
    for ((i=0; i<count; i++)); do
        echo "${queries[$((RANDOM % ${#queries[@]}))]}"
    done
}

# Perform search and measure performance
perform_search() {
    local query=$1
    local search_type=$2
    local limit=$3
    
    local start_time=$(date +%s%N)
    local response=$(curl -s "http://localhost:5000/search?q=${query}&type=${search_type}&limit=${limit}")
    local end_time=$(date +%s%N)
    
    local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    # Extract result count from response
    local result_count=$(echo "$response" | grep -o '"count":[0-9]*' | cut -d':' -f2)
    
    echo "$duration:$result_count"
}

# Run performance test
run_performance_test() {
    local test_name=$1
    local search_type=$2
    local query_category=$3
    local num_queries=$4
    local limit=$5
    
    print_performance "Running $test_name test..."
    print_status "Search Type: $search_type"
    print_status "Query Category: $query_category"
    print_status "Number of Queries: $num_queries"
    print_status "Results Limit: $limit"
    echo ""
    
    local total_time=0
    local total_results=0
    local successful_queries=0
    local failed_queries=0
    
    # Generate queries
    local queries=($(generate_queries "$query_category" "$num_queries"))
    
    for query in "${queries[@]}"; do
        print_status "Searching: '$query'"
        
        local result=$(perform_search "$query" "$search_type" "$limit")
        local duration=$(echo "$result" | cut -d':' -f1)
        local count=$(echo "$result" | cut -d':' -f2)
        
        if [ "$duration" -gt 0 ]; then
            total_time=$((total_time + duration))
            total_results=$((total_results + count))
            successful_queries=$((successful_queries + 1))
            
            print_performance "  ✓ ${duration}ms - ${count} results"
        else
            failed_queries=$((failed_queries + 1))
            print_error "  ✗ Failed"
        fi
        
        # Small delay between requests
        sleep 0.1
    done
    
    # Calculate averages
    local avg_time=0
    local avg_results=0
    
    if [ $successful_queries -gt 0 ]; then
        avg_time=$((total_time / successful_queries))
        avg_results=$((total_results / successful_queries))
    fi
    
    echo ""
    print_performance "=== $test_name Results ==="
    print_performance "Successful Queries: $successful_queries/$num_queries"
    print_performance "Failed Queries: $failed_queries"
    print_performance "Average Response Time: ${avg_time}ms"
    print_performance "Average Results: ${avg_results}"
    print_performance "Total Time: ${total_time}ms"
    echo ""
    
    # Store results for comparison
    echo "$search_type:$avg_time:$avg_results:$successful_queries" >> /tmp/search_performance_results.txt
}

# Run comparison test
run_comparison_test() {
    print_demo "Running comprehensive comparison test..."
    echo ""
    
    # Clear previous results
    rm -f /tmp/search_performance_results.txt
    
    local test_queries=20
    local test_limit=20
    
    # Test different search types
    run_performance_test "Database Search" "database" "technology" $test_queries $test_limit
    run_performance_test "Elasticsearch Search" "elasticsearch" "technology" $test_queries $test_limit
    run_performance_test "Cached Search" "cached" "technology" $test_queries $test_limit
    
    # Display comparison results
    print_demo "=== Performance Comparison Summary ==="
    echo ""
    
    if [ -f /tmp/search_performance_results.txt ]; then
        while IFS=':' read -r type avg_time avg_results successful; do
            print_performance "$type: ${avg_time}ms avg, ${avg_results} avg results, ${successful} successful"
        done < /tmp/search_performance_results.txt
    fi
    
    echo ""
    print_demo "💡 Performance Insights:"
    echo "   • Database: Good for simple text search"
    echo "   • Elasticsearch: Best for complex queries and relevance"
    echo "   • Cached: Fastest for repeated queries"
    echo ""
}

# Run stress test
run_stress_test() {
    print_demo "Running stress test with high concurrent load..."
    echo ""
    
    local concurrent_users=10
    local queries_per_user=5
    local total_queries=$((concurrent_users * queries_per_user))
    
    print_status "Concurrent Users: $concurrent_users"
    print_status "Queries per User: $queries_per_user"
    print_status "Total Queries: $total_queries"
    echo ""
    
    local start_time=$(date +%s)
    
    # Run concurrent searches
    for ((i=1; i<=concurrent_users; i++)); do
        (
            print_status "User $i starting..."
            for ((j=1; j<=queries_per_user; j++)); do
                query=$(generate_queries "random" 1)
                search_type=$(echo "database elasticsearch cached" | tr ' ' '\n' | shuf -n1)
                perform_search "$query" "$search_type" 10 > /dev/null
                sleep 0.2
            done
            print_success "User $i completed"
        ) &
    done
    
    # Wait for all background processes
    wait
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    echo ""
    print_performance "=== Stress Test Results ==="
    print_performance "Total Duration: ${total_duration}s"
    print_performance "Queries per Second: $(echo "scale=2; $total_queries / $total_duration" | bc)"
    print_performance "Average per User: $(echo "scale=2; $total_duration / $concurrent_users" | bc)s"
    echo ""
}

# Interactive mode
interactive_mode() {
    print_demo "Starting interactive search mode..."
    echo ""
    print_status "Type search queries and press Enter. Type 'quit' to exit."
    echo ""
    
    while true; do
        echo -n "🔍 Search: "
        read -r query
        
        if [ "$query" = "quit" ] || [ "$query" = "exit" ]; then
            break
        fi
        
        if [ -n "$query" ]; then
            print_status "Testing all search types..."
            
            for search_type in "database" "elasticsearch" "cached"; do
                print_status "Testing $search_type..."
                result=$(perform_search "$query" "$search_type" 10)
                duration=$(echo "$result" | cut -d':' -f1)
                count=$(echo "$result" | cut -d':' -f2)
                print_performance "  $search_type: ${duration}ms - ${count} results"
            done
            echo ""
        fi
    done
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  comparison    Run performance comparison test"
    echo "  stress        Run stress test with concurrent users"
    echo "  interactive   Start interactive search mode"
    echo "  quick         Run quick performance test"
    echo "  help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 comparison    # Compare all search types"
    echo "  $0 stress        # Test with concurrent load"
    echo "  $0 interactive   # Interactive search testing"
    echo ""
}

# Main function
main() {
    local mode=${1:-"comparison"}
    
    check_demo_running
    
    case $mode in
        "comparison")
            run_comparison_test
            ;;
        "stress")
            run_stress_test
            ;;
        "interactive")
            interactive_mode
            ;;
        "quick")
            run_performance_test "Quick Test" "elasticsearch" "technology" 5 10
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown mode: $mode"
            show_usage
            exit 1
            ;;
    esac
    
    print_success "Load simulation completed!"
}

# Run main function
main "$@" 