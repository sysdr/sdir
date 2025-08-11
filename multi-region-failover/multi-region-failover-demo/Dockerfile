FROM node:18-alpine

WORKDIR /app

# Create logs directory
RUN mkdir -p logs

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --only=production

# Copy application code
COPY src/ ./src/
COPY web/ ./web/

# Expose port
EXPOSE 3000

# Start application
CMD ["npm", "start"]
