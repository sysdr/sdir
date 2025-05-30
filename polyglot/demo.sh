#!/bin/bash
# polyglot-demo.sh - Complete Polyglot Persistence Demo
# Demonstrates how different databases work together in a real application

set -e  # Exit on any error

echo "🚀 Setting up Polyglot Persistence Demo..."
echo "This demo shows how Netflix, Uber, and LinkedIn use multiple databases"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Function to wait for service health
wait_for_service() {
    local service=$1
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for $service to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if docker-compose exec -T $service echo "Service ready" > /dev/null 2>&1; then
            echo "✅ $service is ready"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done
    echo "❌ $service failed to start within expected time"
    return 1
}

# Start all services
echo "🐳 Starting database services..."
docker-compose up -d

# Wait for each service to be healthy
wait_for_service postgres
wait_for_service mongodb  
wait_for_service redis
wait_for_service elasticsearch

echo ""
echo "📊 Setting up database schemas and sample data..."

# PostgreSQL setup - User accounts and transactional data
echo "🐘 Setting up PostgreSQL (User & Order data)..."
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "
-- Drop tables if they exist
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;

-- Create users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table  
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    total_amount DECIMAL(10,2),
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample users
INSERT INTO users (email, first_name, last_name) VALUES 
    ('alice@example.com', 'Alice', 'Johnson'),
    ('bob@example.com', 'Bob', 'Smith'),
    ('carol@example.com', 'Carol', 'Davis');
    
-- Insert sample orders
INSERT INTO orders (user_id, total_amount, status) VALUES 
    (1, 1299.99, 'completed'),
    (1, 49.99, 'completed'),
    (2, 149.99, 'pending'),
    (3, 899.99, 'processing');
"

# MongoDB setup - Product catalog with flexible schema
echo "🍃 Setting up MongoDB (Product catalog)..."
docker-compose exec -T mongodb mongosh ecommerce --eval "
// Clear existing data
db.products.deleteMany({});

// Insert diverse product data showcasing flexible schema
db.products.insertMany([
    {
        sku: 'LAPTOP-001',
        name: 'Gaming Laptop Pro',
        price: 1299.99,
        category: 'electronics',
        inStock: true,
        specifications: {
            brand: 'TechCorp',
            processor: 'Intel i7',
            ram: '16GB DDR4',
            storage: '512GB NVMe SSD',
            graphics: 'RTX 3070',
            display: '15.6\" 144Hz'
        },
        reviews: {
            average: 4.5,
            count: 127
        },
        tags: ['gaming', 'laptop', 'high-performance']
    },
    {
        sku: 'BOOK-001',
        name: 'System Design Interview Guide',
        price: 49.99,
        category: 'books',
        inStock: true,
        specifications: {
            author: 'Alex Xu',
            publisher: 'ByteByteGo',
            pages: 320,
            format: 'paperback',
            isbn: '978-1234567890',
            language: 'English'
        },
        reviews: {
            average: 4.8,
            count: 2341
        },
        tags: ['programming', 'interview', 'system-design']
    },
    {
        sku: 'PHONE-001',
        name: 'Smartphone Ultra',
        price: 899.99,
        category: 'electronics',
        inStock: false,
        specifications: {
            brand: 'MobileTech',
            storage: '128GB',
            camera: '108MP Triple Camera',
            battery: '4500mAh',
            display: '6.7\" OLED',
            os: 'Android 13'
        },
        reviews: {
            average: 4.2,
            count: 89
        },
        tags: ['smartphone', 'mobile', 'photography']
    }
]);

print('✅ MongoDB product catalog setup complete');
"

# Elasticsearch setup - Search and analytics
echo "🔍 Setting up Elasticsearch (Search engine)..."
sleep 5  # Give Elasticsearch more time to fully start

# Create product search index
curl -X PUT "localhost:9200/products" -H 'Content-Type: application/json' -d'{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "analysis": {
      "analyzer": {
        "product_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "sku": {"type": "keyword"},
      "name": {"type": "text", "analyzer": "product_analyzer"},
      "category": {"type": "keyword"},
      "price": {"type": "float"},
      "inStock": {"type": "boolean"},
      "tags": {"type": "keyword"},
      "reviews": {
        "properties": {
          "average": {"type": "float"},
          "count": {"type": "integer"}
        }
      }
    }
  }
}' > /dev/null 2>&1

# Index products for search
curl -X POST "localhost:9200/products/_doc/1" -H 'Content-Type: application/json' -d'{
  "sku": "LAPTOP-001",
  "name": "Gaming Laptop Pro",
  "category": "electronics",
  "price": 1299.99,
  "inStock": true,
  "tags": ["gaming", "laptop", "high-performance"],
  "reviews": {"average": 4.5, "count": 127}
}' > /dev/null 2>&1

curl -X POST "localhost:9200/products/_doc/2" -H 'Content-Type: application/json' -d'{
  "sku": "BOOK-001", 
  "name": "System Design Interview Guide",
  "category": "books",
  "price": 49.99,
  "inStock": true,
  "tags": ["programming", "interview", "system-design"],
  "reviews": {"average": 4.8, "count": 2341}
}' > /dev/null 2>&1

# Redis setup - Session management and caching
echo "⚡ Setting up Redis (Session & Cache)..."
docker-compose exec -T redis redis-cli << 'EOF'
SET "session:alice@example.com" '{"userId":1,"loginTime":"2024-01-15T10:30:00Z","cartItems":["LAPTOP-001"],"preferences":{"theme":"dark","language":"en"}}' EX 3600
SET "session:bob@example.com" '{"userId":2,"loginTime":"2024-01-15T11:45:00Z","cartItems":["BOOK-001","PHONE-001"],"preferences":{"theme":"light","language":"en"}}' EX 3600
HSET "product:LAPTOP-001" name "Gaming Laptop Pro" price "1299.99" views "1547"
HSET "product:BOOK-001" name "System Design Interview Guide" price "49.99" views "892"
SADD "cart:user:1" "LAPTOP-001"
SADD "cart:user:2" "BOOK-001" "PHONE-001"
LPUSH "recent:user:1" "LAPTOP-001" "BOOK-001"
LPUSH "recent:user:2" "PHONE-001" "LAPTOP-001" "BOOK-001"
ECHO "Redis session and cache data setup complete"
EOF

echo ""
echo "🎯 Demo environment ready! Testing polyglot persistence patterns..."
echo "═══════════════════════════════════════════════════════════════"

# Simulate real-world user journey across multiple databases
echo ""
echo "👤 SCENARIO: Alice logs in and makes a purchase"
echo "This demonstrates how a single user action touches multiple databases:"

echo ""
echo "1️⃣  User Authentication (PostgreSQL)"
echo "   Query: Find user by email for login"
USER_DATA=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -c "SELECT id, first_name, last_name, email FROM users WHERE email='alice@example.com';" | tr -d ' ')
echo "   Result: User found → $USER_DATA"

echo ""
echo "2️⃣  Session Management (Redis)"
echo "   Query: Load user session data"
SESSION_DATA=$(docker-compose exec -T redis redis-cli GET "session:alice@example.com")
echo "   Result: Active session → $SESSION_DATA"

echo ""
echo "3️⃣  Product Search (Elasticsearch)"
echo "   Query: Search for 'gaming laptop'"
SEARCH_RESULTS=$(curl -s -X GET "localhost:9200/products/_search" -H 'Content-Type: application/json' -d'{
  "query": {
    "multi_match": {
      "query": "gaming laptop",
      "fields": ["name^2", "tags"]
    }
  }
}' | grep -o '"_score":[0-9.]*' | head -1)
echo "   Result: Found relevant products → $SEARCH_RESULTS"

echo ""
echo "4️⃣  Product Details (MongoDB)"
echo "   Query: Get full product information"
PRODUCT_DETAILS=$(docker-compose exec -T mongodb mongosh ecommerce --quiet --eval "
const product = db.products.findOne({sku: 'LAPTOP-001'});
print(product.name + ' - $' + product.price + ' (Rating: ' + product.reviews.average + '/5)');
") 
echo "   Result: $PRODUCT_DETAILS"

This script shows how a single user action (like browsing and purchasing) touches multiple database systems, each optimized for its specific role.

## Key Insights for Production Success

### The Cost-Benefit Analysis

Every database you add has costs:
- **Operational overhead**: Monitoring, backup, maintenance
- **Team complexity**: Different expertise requirements  
- **Integration complexity**: Synchronization and consistency challenges
- **Licensing costs**: Commercial databases add up quickly

The benefits must clearly outweigh these costs. Don't add database types just because you can—add them because you must.

### The Evolution Path

Most successful polyglot implementations follow this evolution:

1. **Start monolithic**: Single database, well-understood patterns
2. **Extract clear boundaries**: Identify distinct data domains
3. **Add specialized stores**: Only when clear performance or scaling needs emerge
4. **Build integration layers**: Abstract complexity behind clean interfaces
5. **Iterate and optimize**: Continuous improvement based on operational learnings

### The Team Readiness Factor

Your team's capabilities should influence your architecture choices. A team comfortable with PostgreSQL shouldn't jump to Cassandra without proper preparation. The best architecture is one your team can operate reliably.

## The Path Forward

Polyglot persistence isn't about using every database technology available—it's about thoughtfully matching data characteristics to storage capabilities while managing the inevitable complexity. The companies that succeed with this approach treat it as an evolutionary step, not a revolutionary leap.

Start with clear boundaries. Add complexity incrementally. Always measure the operational cost. And remember: the goal isn't to build the most sophisticated system possible—it's to build the most effective system for your specific needs.

The next time you're tempted to add another database type to your architecture, ask yourself: "Am I solving a real problem, or am I just falling in love with technology?" The answer will guide you toward the right decision.

---

*Ready to implement polyglot persistence in your system? Start by mapping your current data boundaries and identifying the single most compelling use case for a specialized database. Master that transition first—the rest will follow naturally.* + product.price + ' (Rating: ' + product.reviews.average + '/5)');
")
echo "   Result: $PRODUCT_DETAILS"

echo ""
echo "5️⃣  Order Creation (PostgreSQL)"
echo "   Query: Create new order with ACID transaction"
docker-compose exec -T postgres psql -U postgres -d ecommerce << 'EOSQL' > /dev/null 2>&1
BEGIN;
INSERT INTO orders (user_id, total_amount, status) VALUES (1, 1299.99, 'processing');
COMMIT;
EOSQL

ORDER_CREATED=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -A -c "SELECT 'Order #' || id || ' - "

echo ""
echo "5️⃣  Order Creation (PostgreSQL)"
echo "   Query: Create new order with ACID transaction"
docker-compose exec -T postgres psql -U postgres -d ecommerce -c "
BEGIN;
INSERT INTO orders (user_id, total_amount, status) VALUES (1, 1299.99, 'processing');
UPDATE users SET created_at = CURRENT_TIMESTAMP WHERE id = 1;
COMMIT;
" > /dev/null 2>&1
ORDER_CREATED=$(docker-compose exec -T postgres psql -U postgres -d ecommerce -t -c "SELECT id, total_amount, status, created_at FROM orders WHERE user_id=1 ORDER BY created_at DESC LIMIT 1;")
echo "   Result: Order created → $ORDER_CREATED"

echo ""
echo "6️⃣  Cache Update (Redis)"
echo "   Query: Update product view count and clear cart"
docker-compose exec -T redis redis-cli << 'EOF' > /dev/null 2>&1
HINCRBY "product:LAPTOP-001" views 1
DEL "cart:user:1"
LPUSH "recent:user:1" "LAPTOP-001"
EOF
VIEWS=$(docker-compose exec -T redis redis-cli HGET "product:LAPTOP-001" views)
echo "   Result: Product views updated → $VIEWS total views"

echo ""
echo "📊 PERFORMANCE COMPARISON:"
echo "═══════════════════════════════════════════════════════════════"
echo "Database Type    | Operation          | Typical Response Time"
echo "-----------------|--------------------|-----------------------"
echo "Redis            | Session lookup     | < 1ms"
echo "PostgreSQL       | User authentication| 2-5ms"  
echo "Elasticsearch    | Product search     | 10-50ms"
echo "MongoDB          | Product details    | 5-15ms"
echo "PostgreSQL       | Order transaction  | 10-100ms"

echo ""
echo "🏗️  ARCHITECTURE INSIGHTS:"
echo "═══════════════════════════════════════════════════════════════"
echo "• PostgreSQL: ACID compliance for critical business data (users, orders)"
echo "• MongoDB: Flexible schema for diverse product catalogs"
echo "• Redis: Sub-millisecond access for sessions and frequently accessed data"
echo "• Elasticsearch: Full-text search with relevance scoring and analytics"

echo ""
echo "🎉 Polyglot Persistence Demo Complete!"
echo ""
echo "💡 Key Takeaways:"
echo "• Each database optimizes for specific access patterns"
echo "• Cross-database consistency requires careful coordination"  
echo "• Performance characteristics vary dramatically by database type"
echo "• Real applications orchestrate multiple databases seamlessly"
echo ""
echo "🧹 To clean up: docker-compose down -v"