#!/bin/bash

set -e

echo "🚀 GraphQL Federation Demo Setup"
echo "================================"

# Create project structure
mkdir -p graphql-federation/{gateway,users-service,products-service,reviews-service,dashboard/public}

# Create Gateway Service
cat > graphql-federation/gateway/package.json <<'EOF'
{
  "name": "federation-gateway",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@apollo/gateway": "^2.5.5",
    "@apollo/server": "^4.9.5",
    "graphql": "^16.8.1",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > graphql-federation/gateway/server.js <<'EOF'
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { ApolloGateway, IntrospectAndCompose } from '@apollo/gateway';
import express from 'express';
import cors from 'cors';

const gateway = new ApolloGateway({
  supergraphSdl: new IntrospectAndCompose({
    subgraphs: [
      { name: 'users', url: 'http://users-service:4001/graphql' },
      { name: 'products', url: 'http://products-service:4002/graphql' },
      { name: 'reviews', url: 'http://reviews-service:4003/graphql' }
    ],
    pollIntervalInMs: 10000
  }),
  experimental_didResolveQueryPlan: function(options) {
    const plan = options.queryPlan;
    const queryPlanInfo = {
      timestamp: new Date().toISOString(),
      operationName: options.operationContext.operationName,
      services: extractServicesFromPlan(plan),
      parallelSteps: countParallelSteps(plan),
      totalSteps: countTotalSteps(plan)
    };
    console.log('Query Plan:', JSON.stringify(queryPlanInfo, null, 2));
  }
});

function extractServicesFromPlan(plan) {
  const services = new Set();
  JSON.stringify(plan, (key, value) => {
    if (key === 'serviceName') services.add(value);
    return value;
  });
  return Array.from(services);
}

function countParallelSteps(plan) {
  let count = 0;
  JSON.stringify(plan, (key, value) => {
    if (key === 'parallel' && Array.isArray(value)) count++;
    return value;
  });
  return count;
}

function countTotalSteps(plan) {
  let count = 0;
  JSON.stringify(plan, (key, value) => {
    if (key === 'fetch' || key === 'parallel') count++;
    return value;
  });
  return count;
}

const app = express();

const server = new ApolloServer({ gateway });

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server, {
    context: async ({ req }) => ({ req })
  })
);

app.get('/metrics', (req, res) => {
  res.json({
    gateway: 'running',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

app.listen(4000, () => {
  console.log('🚪 Gateway running at http://localhost:4000/graphql');
});
EOF

cat > graphql-federation/gateway/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create Users Service
cat > graphql-federation/users-service/package.json <<'EOF'
{
  "name": "users-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@apollo/server": "^4.9.5",
    "@apollo/subgraph": "^2.5.5",
    "graphql": "^16.8.1",
    "graphql-tag": "^2.12.6",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > graphql-federation/users-service/server.js <<'EOF'
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const users = [
  { id: '1', name: 'Alice Johnson', email: 'alice@example.com', joinDate: '2023-01-15' },
  { id: '2', name: 'Bob Smith', email: 'bob@example.com', joinDate: '2023-03-22' },
  { id: '3', name: 'Carol White', email: 'carol@example.com', joinDate: '2023-05-10' }
];

const typeDefs = gql`
  type User @key(fields: "id") {
    id: ID!
    name: String!
    email: String!
    joinDate: String!
  }

  type Query {
    users: [User!]!
    user(id: ID!): User
  }
`;

const resolvers = {
  Query: {
    users: () => {
      console.log('Fetching all users');
      return users;
    },
    user: (_, { id }) => {
      console.log(`Fetching user: ${id}`);
      return users.find(u => u.id === id);
    }
  },
  User: {
    __resolveReference: (reference) => {
      console.log(`Resolving User entity: ${reference.id}`);
      return users.find(u => u.id === reference.id);
    }
  }
};

const app = express();

const server = new ApolloServer({
  schema: buildSubgraphSchema({ typeDefs, resolvers })
});

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server)
);

app.listen(4001, () => {
  console.log('👤 Users Service running at http://localhost:4001/graphql');
});
EOF

cat > graphql-federation/users-service/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create Products Service
cat > graphql-federation/products-service/package.json <<'EOF'
{
  "name": "products-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@apollo/server": "^4.9.5",
    "@apollo/subgraph": "^2.5.5",
    "graphql": "^16.8.1",
    "graphql-tag": "^2.12.6",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > graphql-federation/products-service/server.js <<'EOF'
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const products = [
  { id: '101', name: 'Laptop Pro', price: 1299.99, category: 'Electronics' },
  { id: '102', name: 'Wireless Mouse', price: 29.99, category: 'Electronics' },
  { id: '103', name: 'Desk Chair', price: 249.99, category: 'Furniture' },
  { id: '104', name: 'Monitor 27"', price: 399.99, category: 'Electronics' }
];

const typeDefs = gql`
  type Product @key(fields: "id") {
    id: ID!
    name: String!
    price: Float!
    category: String!
  }

  type Query {
    products: [Product!]!
    product(id: ID!): Product
  }
`;

const resolvers = {
  Query: {
    products: () => {
      console.log('Fetching all products');
      return products;
    },
    product: (_, { id }) => {
      console.log(`Fetching product: ${id}`);
      return products.find(p => p.id === id);
    }
  },
  Product: {
    __resolveReference: (reference) => {
      console.log(`Resolving Product entity: ${reference.id}`);
      return products.find(p => p.id === reference.id);
    }
  }
};

const app = express();

const server = new ApolloServer({
  schema: buildSubgraphSchema({ typeDefs, resolvers })
});

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server)
);

app.listen(4002, () => {
  console.log('📦 Products Service running at http://localhost:4002/graphql');
});
EOF

cat > graphql-federation/products-service/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create Reviews Service
cat > graphql-federation/reviews-service/package.json <<'EOF'
{
  "name": "reviews-service",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@apollo/server": "^4.9.5",
    "@apollo/subgraph": "^2.5.5",
    "graphql": "^16.8.1",
    "graphql-tag": "^2.12.6",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > graphql-federation/reviews-service/server.js <<'EOF'
import { ApolloServer } from '@apollo/server';
import { expressMiddleware } from '@apollo/server/express4';
import { buildSubgraphSchema } from '@apollo/subgraph';
import gql from 'graphql-tag';
import express from 'express';
import cors from 'cors';

const reviews = [
  { id: '1', productId: '101', userId: '1', rating: 5, comment: 'Excellent laptop!', date: '2024-01-20' },
  { id: '2', productId: '101', userId: '2', rating: 4, comment: 'Great performance', date: '2024-01-22' },
  { id: '3', productId: '102', userId: '1', rating: 5, comment: 'Perfect mouse', date: '2024-02-05' },
  { id: '4', productId: '103', userId: '3', rating: 4, comment: 'Comfortable chair', date: '2024-02-10' },
  { id: '5', productId: '104', userId: '2', rating: 5, comment: 'Crystal clear display', date: '2024-02-15' }
];

const typeDefs = gql`
  type Review {
    id: ID!
    rating: Int!
    comment: String!
    date: String!
    author: User!
  }

  extend type Product @key(fields: "id") {
    id: ID! @external
    reviews: [Review!]!
    avgRating: Float!
    reviewCount: Int!
  }

  extend type User @key(fields: "id") {
    id: ID! @external
    reviews: [Review!]!
  }
`;

const resolvers = {
  Product: {
    reviews: (product) => {
      console.log(`Fetching reviews for product: ${product.id}`);
      return reviews.filter(r => r.productId === product.id);
    },
    avgRating: (product) => {
      const productReviews = reviews.filter(r => r.productId === product.id);
      if (productReviews.length === 0) return 0;
      const sum = productReviews.reduce((acc, r) => acc + r.rating, 0);
      return parseFloat((sum / productReviews.length).toFixed(2));
    },
    reviewCount: (product) => {
      return reviews.filter(r => r.productId === product.id).length;
    }
  },
  User: {
    reviews: (user) => {
      console.log(`Fetching reviews for user: ${user.id}`);
      return reviews.filter(r => r.userId === user.id);
    }
  },
  Review: {
    author: (review) => {
      return { __typename: 'User', id: review.userId };
    }
  }
};

const app = express();

const server = new ApolloServer({
  schema: buildSubgraphSchema({ typeDefs, resolvers })
});

await server.start();

app.use(
  '/graphql',
  cors(),
  express.json(),
  expressMiddleware(server)
);

app.listen(4003, () => {
  console.log('⭐ Reviews Service running at http://localhost:4003/graphql');
});
EOF

cat > graphql-federation/reviews-service/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create Dashboard
cat > graphql-federation/dashboard/package.json <<'EOF'
{
  "name": "federation-dashboard",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "cors": "^2.8.5"
  }
}
EOF

cat > graphql-federation/dashboard/server.js <<'EOF'
import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

const server = createServer(app);
const wss = new WebSocketServer({ server });

let queryLogs = [];
let metrics = {
  totalQueries: 0,
  avgResponseTime: 0,
  servicesInvoked: { users: 0, products: 0, reviews: 0 }
};

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'init', data: { queryLogs, metrics } }));
});

function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
}

app.post('/log-query', (req, res) => {
  const log = {
    ...req.body,
    timestamp: new Date().toISOString(),
    id: Date.now()
  };
  
  queryLogs.unshift(log);
  if (queryLogs.length > 50) queryLogs.pop();
  
  metrics.totalQueries++;
  metrics.avgResponseTime = ((metrics.avgResponseTime * (metrics.totalQueries - 1)) + log.responseTime) / metrics.totalQueries;
  
  log.services.forEach(service => {
    if (metrics.servicesInvoked[service] !== undefined) {
      metrics.servicesInvoked[service]++;
    }
  });
  
  broadcast({ type: 'query', data: log });
  broadcast({ type: 'metrics', data: metrics });
  
  res.json({ success: true });
});

server.listen(3000, () => {
  console.log('📊 Dashboard running at http://localhost:3000');
});
EOF

cat > graphql-federation/dashboard/public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GraphQL Federation Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: #333;
      padding: 20px;
      min-height: 100vh;
    }
    .container {
      max-width: 1400px;
      margin: 0 auto;
    }
    h1 {
      color: white;
      text-align: center;
      margin-bottom: 30px;
      font-size: 2.5em;
      text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    .stat-card {
      background: white;
      padding: 25px;
      border-radius: 15px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      transition: transform 0.3s ease;
    }
    .stat-card:hover {
      transform: translateY(-5px);
    }
    .stat-label {
      font-size: 0.9em;
      color: #666;
      margin-bottom: 10px;
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .stat-value {
      font-size: 2.5em;
      font-weight: bold;
      color: #667eea;
    }
    .service-stats {
      display: flex;
      justify-content: space-around;
      margin-top: 15px;
    }
    .service-stat {
      text-align: center;
    }
    .service-name {
      font-size: 0.8em;
      color: #666;
    }
    .service-count {
      font-size: 1.5em;
      font-weight: bold;
      color: #764ba2;
    }
    .query-log {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      max-height: 600px;
      overflow-y: auto;
    }
    .query-log h2 {
      margin-bottom: 20px;
      color: #667eea;
    }
    .query-item {
      padding: 15px;
      border-left: 4px solid #667eea;
      margin-bottom: 15px;
      background: #f8f9fa;
      border-radius: 8px;
      transition: all 0.3s ease;
    }
    .query-item:hover {
      background: #e9ecef;
      transform: translateX(5px);
    }
    .query-header {
      display: flex;
      justify-content: space-between;
      margin-bottom: 10px;
    }
    .query-time {
      font-size: 0.85em;
      color: #666;
    }
    .query-operation {
      font-weight: bold;
      color: #333;
      margin-bottom: 8px;
    }
    .query-services {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
    }
    .service-badge {
      background: #667eea;
      color: white;
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 0.8em;
    }
    .response-time {
      background: #28a745;
      color: white;
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 0.8em;
      font-weight: bold;
    }
    .test-section {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      margin-bottom: 30px;
    }
    .test-section h2 {
      margin-bottom: 20px;
      color: #667eea;
    }
    .test-buttons {
      display: flex;
      gap: 15px;
      flex-wrap: wrap;
    }
    button {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 1em;
      font-weight: bold;
      transition: all 0.3s ease;
      box-shadow: 0 4px 15px rgba(0,0,0,0.2);
    }
    button:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0,0,0,0.3);
    }
    button:active {
      transform: translateY(0);
    }
    .status-indicator {
      display: inline-block;
      width: 12px;
      height: 12px;
      border-radius: 50%;
      background: #28a745;
      animation: pulse 2s infinite;
      margin-right: 8px;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1><span class="status-indicator"></span>GraphQL Federation Dashboard</h1>
    
    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">Total Queries</div>
        <div class="stat-value" id="totalQueries">0</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Avg Response Time</div>
        <div class="stat-value" id="avgResponseTime">0ms</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Service Invocations</div>
        <div class="service-stats">
          <div class="service-stat">
            <div class="service-name">Users</div>
            <div class="service-count" id="usersCount">0</div>
          </div>
          <div class="service-stat">
            <div class="service-name">Products</div>
            <div class="service-count" id="productsCount">0</div>
          </div>
          <div class="service-stat">
            <div class="service-name">Reviews</div>
            <div class="service-count" id="reviewsCount">0</div>
          </div>
        </div>
      </div>
    </div>

    <div class="test-section">
      <h2>Test Queries</h2>
      <div class="test-buttons">
        <button onclick="testQuery1()">Get Users</button>
        <button onclick="testQuery2()">Get Products with Reviews</button>
        <button onclick="testQuery3()">Get User with Reviews</button>
        <button onclick="testQuery4()">Complex Federation Query</button>
      </div>
    </div>

    <div class="query-log">
      <h2>Query Execution Log</h2>
      <div id="queryLog"></div>
    </div>
  </div>

  <script>
    const ws = new WebSocket('ws://localhost:3000');
    
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      
      if (message.type === 'init') {
        updateMetrics(message.data.metrics);
        message.data.queryLogs.forEach(addQueryLog);
      } else if (message.type === 'query') {
        addQueryLog(message.data);
      } else if (message.type === 'metrics') {
        updateMetrics(message.data);
      }
    };

    function updateMetrics(metrics) {
      document.getElementById('totalQueries').textContent = metrics.totalQueries;
      document.getElementById('avgResponseTime').textContent = metrics.avgResponseTime.toFixed(2) + 'ms';
      document.getElementById('usersCount').textContent = metrics.servicesInvoked.users;
      document.getElementById('productsCount').textContent = metrics.servicesInvoked.products;
      document.getElementById('reviewsCount').textContent = metrics.servicesInvoked.reviews;
    }

    function addQueryLog(log) {
      const logElement = document.createElement('div');
      logElement.className = 'query-item';
      logElement.innerHTML = `
        <div class="query-header">
          <span class="query-time">${new Date(log.timestamp).toLocaleTimeString()}</span>
          <span class="response-time">${log.responseTime}ms</span>
        </div>
        <div class="query-operation">${log.operation}</div>
        <div class="query-services">
          ${log.services.map(s => `<span class="service-badge">${s}</span>`).join('')}
        </div>
      `;
      
      const logContainer = document.getElementById('queryLog');
      logContainer.insertBefore(logElement, logContainer.firstChild);
      
      if (logContainer.children.length > 20) {
        logContainer.removeChild(logContainer.lastChild);
      }
    }

    async function executeQuery(query, operation, services) {
      const startTime = Date.now();
      
      try {
        const response = await fetch('http://localhost:4000/graphql', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query })
        });
        
        const data = await response.json();
        const responseTime = Date.now() - startTime;
        
        await fetch('http://localhost:3000/log-query', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ operation, services, responseTime })
        });
        
        console.log('Query result:', data);
      } catch (error) {
        console.error('Query failed:', error);
      }
    }

    function testQuery1() {
      const query = `query GetUsers { users { id name email joinDate } }`;
      executeQuery(query, 'GetUsers', ['users']);
    }

    function testQuery2() {
      const query = `query GetProductsWithReviews {
        products {
          id name price
          reviews { rating comment date }
          avgRating reviewCount
        }
      }`;
      executeQuery(query, 'GetProductsWithReviews', ['products', 'reviews']);
    }

    function testQuery3() {
      const query = `query GetUserWithReviews {
        user(id: "1") {
          id name email
          reviews { rating comment date }
        }
      }`;
      executeQuery(query, 'GetUserWithReviews', ['users', 'reviews']);
    }

    function testQuery4() {
      const query = `query ComplexFederation {
        users {
          id name
          reviews {
            rating comment
          }
        }
        products {
          id name price
          reviews {
            rating
            author { name email }
          }
          avgRating
        }
      }`;
      executeQuery(query, 'ComplexFederation', ['users', 'products', 'reviews']);
    }
  </script>
</body>
</html>
EOF

cat > graphql-federation/dashboard/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
EOF

# Create docker-compose.yml
cat > graphql-federation/docker-compose.yml <<'EOF'
version: '3.8'

services:
  users-service:
    build: ./users-service
    ports:
      - "4001:4001"
    networks:
      - federation-network

  products-service:
    build: ./products-service
    ports:
      - "4002:4002"
    networks:
      - federation-network

  reviews-service:
    build: ./reviews-service
    ports:
      - "4003:4003"
    networks:
      - federation-network

  gateway:
    build: ./gateway
    ports:
      - "4000:4000"
    depends_on:
      - users-service
      - products-service
      - reviews-service
    networks:
      - federation-network

  dashboard:
    build: ./dashboard
    ports:
      - "3000:3000"
    depends_on:
      - gateway
    networks:
      - federation-network

networks:
  federation-network:
    driver: bridge
EOF

# Create test script
cat > graphql-federation/test.sh <<'EOF'
#!/bin/bash

echo "🧪 Running Federation Tests..."
echo "=============================="

sleep 5

echo -e "\n1️⃣ Test: Query Users Service"
curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ users { id name email } }"}' | jq .

echo -e "\n2️⃣ Test: Query Products with Reviews (Federation)"
curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ products { id name price reviews { rating comment } avgRating } }"}' | jq .

echo -e "\n3️⃣ Test: Query User with Reviews (Federation)"
curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ user(id: \"1\") { id name reviews { rating comment } } }"}' | jq .

echo -e "\n4️⃣ Test: Complex Federation Query"
curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ users { id name reviews { rating } } products { id name avgRating reviewCount } }"}' | jq .

echo -e "\n✅ All tests completed!"
EOF

chmod +x graphql-federation/test.sh

cd graphql-federation

echo "📦 Building Docker images..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 15

echo "🧪 Running tests..."
./test.sh

echo ""
echo "✅ Setup complete!"
echo "================================"
echo "📊 Dashboard: http://localhost:3000"
echo "🚪 Gateway: http://localhost:4000/graphql"
echo "👤 Users Service: http://localhost:4001/graphql"
echo "📦 Products Service: http://localhost:4002/graphql"
echo "⭐ Reviews Service: http://localhost:4003/graphql"
echo ""
echo "Try the test queries from the dashboard!"
echo "Watch query execution plans in the gateway logs:"
echo "  docker-compose logs -f gateway"