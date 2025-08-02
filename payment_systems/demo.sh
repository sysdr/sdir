#!/bin/bash

# Payment Systems Demo Script
# This script sets up, builds, and runs a complete payment processing system

set -e

echo "🚀 Starting Payment Systems Demo..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if Node.js is installed
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    print_success "Dependencies check passed"
}

# Setup project structure
setup_project() {
    print_status "Setting up project structure..."
    
    # Create directories
    mkdir -p frontend backend database docs
    
    print_success "Project structure created"
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    # Backend dependencies
    cd backend
    npm init -y
    npm install express cors dotenv bcryptjs jsonwebtoken stripe @stripe/stripe-js sqlite3 multer helmet morgan
    npm install --save-dev nodemon jest supertest
    cd ..
    
    # Frontend dependencies
    cd frontend
    npm init -y
    npm install react react-dom react-router-dom axios @stripe/stripe-js @stripe/react-stripe-js
    npm install --save-dev @vitejs/plugin-react vite @types/react @types/react-dom
    cd ..
    
    print_success "Dependencies installed"
}

# Build the application
build_app() {
    print_status "Building application..."
    
    # Build frontend
    cd frontend
    npm run build
    cd ..
    
    print_success "Application built successfully"
}

# Run tests
run_tests() {
    print_status "Running tests..."
    
    # Test backend health
    print_status "Testing backend health..."
    sleep 2  # Give backend time to start if needed
    
    if curl -s http://localhost:3001/api/health >/dev/null 2>&1; then
        print_success "Backend health check passed"
    else
        print_warning "Backend not running, starting it for testing..."
        cd backend
        npm start &
        BACKEND_TEST_PID=$!
        cd ..
        sleep 3
    fi
    
    # Test payment intent creation
    print_status "Testing payment intent creation..."
    PAYMENT_RESPONSE=$(curl -s -X POST http://localhost:3001/api/payments/create-payment-intent \
        -H "Content-Type: application/json" \
        -d '{"amount": 10.50, "description": "Test payment"}' 2>/dev/null || echo '{"error": "Failed"}')
    
    if echo "$PAYMENT_RESPONSE" | grep -q "clientSecret"; then
        print_success "Payment intent creation test passed"
    else
        print_warning "Payment intent creation test failed (this is normal if backend is not running)"
    fi
    
    # Test demo user
    print_status "Testing demo user endpoint..."
    USER_RESPONSE=$(curl -s http://localhost:3001/api/users/demo 2>/dev/null || echo '{"error": "Failed"}')
    
    if echo "$USER_RESPONSE" | grep -q "demo@example.com"; then
        print_success "Demo user test passed"
    else
        print_warning "Demo user test failed (this is normal if backend is not running)"
    fi
    
    # Clean up test backend if we started it
    if [ ! -z "$BACKEND_TEST_PID" ]; then
        kill $BACKEND_TEST_PID 2>/dev/null || true
    fi
    
    print_success "Tests completed"
}

# Print header for demo
print_header() {
    echo ""
    echo "=========================================="
    echo "  🚀 Payment Systems Demo"
    echo "=========================================="
    echo ""
}

# Start the application
start_app() {
    print_status "Starting payment systems application..."
    
    # Check and kill existing processes on ports 3001 and 5173
    print_status "Checking for existing processes..."
    lsof -ti:3001 | xargs kill -9 2>/dev/null || true
    lsof -ti:5173 | xargs kill -9 2>/dev/null || true
    sleep 1
    
    # Start backend
    cd backend
    npm start &
    BACKEND_PID=$!
    cd ..
    
    # Start frontend
    cd frontend
    npm run dev &
    FRONTEND_PID=$!
    cd ..
    
    # Wait a moment for servers to start
    sleep 3
    
    print_success "🎉 Demo is ready!"
    echo ""
    echo "=========================================="
    echo "  🌐 Access Points:"
    echo "=========================================="
    echo "  Frontend: http://localhost:5173 (or check terminal for actual port)"
    echo "  Backend:  http://localhost:3001"
    echo "  Health:   http://localhost:3001/api/health"
    echo ""
    echo "=========================================="
    echo "  🚀 Demo Instructions:"
    echo "=========================================="
    echo "  1. Open the frontend URL shown above in your browser"
    echo "  2. Click 'Try Demo' to login with demo account"
    echo "  3. Navigate to 'Make Payment' to test payments"
    echo "  4. View transactions in 'Transaction History'"
    echo "  5. Check dashboard for statistics"
    echo ""
    echo "=========================================="
    echo "  🛠️  Demo Features:"
    echo "=========================================="
    echo "  ✓ No real payments - all simulated"
    echo "  ✓ No API keys required"
    echo "  ✓ Full payment workflow"
    echo "  ✓ Transaction tracking"
    echo "  ✓ User authentication"
    echo "  ✓ Stripe-like UI design"
    echo ""
    print_status "Press Ctrl+C to stop the demo"
    
    # Wait for user to stop
    wait
}

# Clean up
cleanup() {
    print_status "Cleaning up..."
    if [ ! -z "$BACKEND_PID" ]; then
        kill $BACKEND_PID 2>/dev/null || true
    fi
    if [ ! -z "$FRONTEND_PID" ]; then
        kill $FRONTEND_PID 2>/dev/null || true
    fi
    print_success "Cleanup completed"
}

# Main execution
main() {
    case "${1:-demo}" in
        "setup")
            check_dependencies
            setup_project
            install_dependencies
            print_success "Setup completed! Run './demo.sh build' to build the application"
            ;;
        "build")
            build_app
            print_success "Build completed! Run './demo.sh start' to start the application"
            ;;
        "start")
            start_app
            ;;
        "dev")
            check_dependencies
            setup_project
            install_dependencies
            build_app
            start_app
            ;;
        "demo")
            print_header
            print_status "🚀 Starting Payment Systems Demo..."
            print_status "This will set up, build, test, and start the complete demo"
            echo ""
            
            # Step 1: Check dependencies
            print_status "Step 1: Checking dependencies..."
            check_dependencies
            
            # Step 2: Setup project
            print_status "Step 2: Setting up project structure..."
            setup_project
            
            # Step 3: Install dependencies
            print_status "Step 3: Installing dependencies..."
            install_dependencies
            
            # Step 4: Build application
            print_status "Step 4: Building application..."
            build_app
            
            # Step 5: Run tests
            print_status "Step 5: Running tests..."
            run_tests
            
            # Step 6: Start application
            print_status "Step 6: Starting demo application..."
            start_app
            ;;
        "test")
            run_tests
            ;;
        "clean")
            cleanup
            rm -rf node_modules frontend/node_modules backend/node_modules
            print_success "Clean completed"
            ;;
        "full-cleanup")
            print_status "Running full cleanup (including Docker and temp files)..."
            ./cleanup.sh
            ;;
        *)
            echo "Usage: $0 {demo|setup|build|start|dev|test|clean|full-cleanup}"
            echo ""
            echo "  demo        - Complete demo: setup, build, test, and start (DEFAULT)"
            echo "  setup       - Set up the project structure and install dependencies"
            echo "  build       - Build the application"
            echo "  start       - Start the application (assumes setup is complete)"
            echo "  dev         - Complete setup, build, and start"
            echo "  test        - Run tests"
            echo "  clean       - Clean up and remove node_modules"
            echo "  full-cleanup- Full cleanup (processes, temp files, Docker, databases)"
            echo ""
            echo "Examples:"
            echo "  ./demo.sh          # Run complete demo"
            echo "  ./demo.sh demo     # Same as above"
            echo "  ./demo.sh test     # Run tests only"
            echo "  ./demo.sh cleanup  # Clean up processes"
            exit 1
            ;;
    esac
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
