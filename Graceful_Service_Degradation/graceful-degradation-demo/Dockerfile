FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY src/ ./src/
COPY static/ ./static/
COPY tests/ ./tests/

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S -u 1001 nodejs
USER nodejs

EXPOSE 3000 3001 3002 3003

CMD ["node", "src/gateway.js"]
