FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY src/services/package*.json ./
RUN npm install --omit=dev

# Copy application code
COPY src/services/ ./

EXPOSE 3001 3002

CMD ["npm", "start"]
