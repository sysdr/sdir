#!/bin/bash

# Search Scaling Demo - Project Information
# This script displays comprehensive project information

echo "📋 Search Scaling Demo - Project Information"
echo "============================================"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${PURPLE}$1${NC}"
}

print_section() {
    echo -e "${BLUE}$1${NC}"
}

print_item() {
    echo -e "${GREEN}  • $1${NC}"
}

print_command() {
    echo -e "${CYAN}    $ $1${NC}"
}

print_description() {
    echo -e "${YELLOW}      $1${NC}"
}

# Show project overview
show_overview() {
    print_header "🎯 Project Overview"
    echo ""
    echo "This demo showcases search technology scaling with:"
    print_item "PostgreSQL full-text search"
    print_item "Elasticsearch advanced search"
    print_item "Redis caching layer"
    print_item "Real-time performance metrics"
    print_item "Load simulation and testing"
    echo ""
}

# Show project structure
show_structure() {
    print_header "📁 Project Structure"
    echo ""
    
    print_section "Core Application Files"
    print_item "app/app.py - Main Flask application"
    print_item "app/templates/index.html - Web interface"
    print_item "app/static/ - Static assets"
    echo ""
    
    print_section "Configuration Files"
    print_item "docker-compose.yml - Service orchestration"
    print_item "Dockerfile - Application container"
    print_item "requirements.txt - Python dependencies"
    print_item "config/init.sql - Database schema"
    echo ""
    
    print_section "Demo Scripts"
    print_item "demo.sh - One-click demo experience"
    print_item "build.sh - Environment build script"
    print_item "start-demo.sh - Demo startup script"
    print_item "simulate-load.sh - Load testing script"
    print_item "test-demo.sh - Environment testing"
    print_item "cleanup.sh - Cleanup script"
    echo ""
    
    print_section "Documentation"
    print_item "README.md - Project overview"
    print_item "demo-guide.md - Complete guide"
    echo ""
}

# Show available commands
show_commands() {
    print_header "🛠️ Available Commands"
    echo ""
    
    print_section "Quick Start"
    print_command "./demo.sh"
    print_description "Interactive demo menu with all options"
    echo ""
    
    print_section "Build & Deploy"
    print_command "./build.sh"
    print_description "Build the entire demo environment"
    print_command "./start-demo.sh"
    print_description "Start the demo with monitoring"
    print_command "./cleanup.sh"
    print_description "Stop and clean up all services"
    echo ""
    
    print_section "Testing & Simulation"
    print_command "./simulate-load.sh comparison"
    print_description "Compare performance of all search types"
    print_command "./simulate-load.sh stress"
    print_description "Run stress test with concurrent users"
    print_command "./simulate-load.sh interactive"
    print_description "Interactive search testing mode"
    print_command "./test-demo.sh"
    print_description "Test environment and functionality"
    echo ""
    
    print_section "Monitoring"
    print_command "docker-compose ps"
    print_description "View service status"
    print_command "docker-compose logs -f"
    print_description "Monitor service logs"
    print_command "curl http://localhost:5000/health"
    print_description "Check application health"
    print_command "curl http://localhost:5000/metrics"
    print_description "View performance metrics"
    echo ""
}

# Show access points
show_access_points() {
    print_header "🌐 Access Points"
    echo ""
    
    print_section "Web Interface"
    print_item "Main Demo: http://localhost:5000"
    print_description "Modern search interface with real-time metrics"
    echo ""
    
    print_section "API Endpoints"
    print_item "Health Check: http://localhost:5000/health"
    print_item "Search API: http://localhost:5000/search?q=query&type=elasticsearch"
    print_item "Metrics API: http://localhost:5000/metrics"
    echo ""
    
    print_section "Service Ports"
    print_item "Flask App: localhost:5000"
    print_item "Elasticsearch: localhost:9200"
    print_item "Redis: localhost:6379"
    print_item "PostgreSQL: localhost:5432"
    echo ""
}

# Show demo scenarios
show_scenarios() {
    print_header "🎭 Demo Scenarios"
    echo ""
    
    print_section "System Design Interview"
    print_item "Demonstrate search architecture knowledge"
    print_item "Show performance optimization skills"
    print_item "Explain caching strategies"
    print_item "Discuss scalability considerations"
    echo ""
    
    print_section "Performance Testing"
    print_item "Compare search technology performance"
    print_item "Test system behavior under load"
    print_item "Measure response times and throughput"
    print_item "Identify performance bottlenecks"
    echo ""
    
    print_section "Learning & Development"
    print_item "Hands-on experience with search engines"
    print_item "Docker and microservices practice"
    print_item "Performance testing and optimization"
    print_item "Modern web development patterns"
    echo ""
}

# Show expected results
show_results() {
    print_header "📊 Expected Results"
    echo ""
    
    print_section "Performance Characteristics"
    echo "┌──────────────┬──────────────┬─────────────┬─────────────┐"
    echo "│ Search Type  │ Response Time│ Relevance   │ Complexity  │"
    echo "├──────────────┼──────────────┼─────────────┼─────────────┤"
    echo "│ Database     │ 50-200ms     │ Basic       │ Low         │"
    echo "│ Elasticsearch│ 20-100ms     │ High        │ Medium      │"
    echo "│ Cached       │ 5-20ms       │ High*       │ Low         │"
    echo "└──────────────┴──────────────┴─────────────┴─────────────┘"
    echo ""
    print_description "*Cached results maintain the relevance of the underlying search engine"
    echo ""
    
    print_section "Performance Patterns"
    print_item "First Query: Elasticsearch > Database > Cached (cache miss)"
    print_item "Repeated Query: Cached > Elasticsearch > Database"
    print_item "Complex Query: Elasticsearch > Database (cached may not apply)"
    print_item "High Load: Cached > Elasticsearch > Database"
    echo ""
}

# Show troubleshooting
show_troubleshooting() {
    print_header "🔧 Troubleshooting"
    echo ""
    
    print_section "Common Issues"
    print_item "Services not starting - Check Docker and port availability"
    print_item "Slow performance - Monitor resource usage and service health"
    print_item "Search failures - Verify data loading and service connectivity"
    echo ""
    
    print_section "Debug Commands"
    print_command "docker-compose logs [service-name]"
    print_description "Check specific service logs"
    print_command "docker exec -it search-app bash"
    print_description "Access application container"
    print_command "docker stats"
    print_description "Monitor resource usage"
    echo ""
    
    print_section "Health Checks"
    print_command "curl http://localhost:5000/health"
    print_description "Application health"
    print_command "curl http://localhost:9200/_cluster/health"
    print_description "Elasticsearch health"
    print_command "docker exec search-redis redis-cli ping"
    print_description "Redis health"
    print_command "docker exec search-postgres pg_isready -U searchuser -d searchdb"
    print_description "PostgreSQL health"
    echo ""
}

# Show next steps
show_next_steps() {
    print_header "🚀 Next Steps"
    echo ""
    
    print_section "Get Started"
    print_command "./demo.sh"
    print_description "Run the interactive demo menu"
    echo ""
    
    print_section "Explore"
    print_item "Open http://localhost:5000 in your browser"
    print_item "Try different search queries"
    print_item "Compare search types"
    print_item "Monitor real-time metrics"
    echo ""
    
    print_section "Learn More"
    print_item "Read demo-guide.md for detailed instructions"
    print_item "Experiment with different query types"
    print_item "Test performance under various loads"
    print_item "Customize the demo for your needs"
    echo ""
}

# Main function
main() {
    show_overview
    show_structure
    show_commands
    show_access_points
    show_scenarios
    show_results
    show_troubleshooting
    show_next_steps
    
    echo ""
    print_header "🎉 Ready to explore search scaling!"
    echo ""
    echo "Start your journey with: ./demo.sh"
    echo ""
}

# Run main function
main "$@" 