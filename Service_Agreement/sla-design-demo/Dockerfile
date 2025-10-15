FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --omit=dev

# Copy application code
COPY src/ ./src/
COPY web/ ./web/

# Create logs directory
RUN mkdir -p logs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/api/sla-status', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => { process.exit(1) })"

# Start application
CMD ["npm", "start"]
