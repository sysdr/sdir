FROM node:22-alpine

WORKDIR /app

# Install dependencies first (layer caching)
COPY backend/package.json ./
RUN npm install --production --no-audit

# Copy backend source and frontend (dashboard)
COPY backend/server.js backend/test.js ./
COPY frontend ./frontend

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=5s --retries=10 \
  CMD wget -qO- http://localhost:3000/api/status || exit 1

CMD ["node", "server.js"]
