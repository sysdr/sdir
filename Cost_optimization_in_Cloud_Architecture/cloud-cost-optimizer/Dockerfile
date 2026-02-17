# Using Node.js LTS Alpine for minimal footprint
FROM node:20-alpine

# Non-root user for security
RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Install dependencies first (layer caching)
COPY package.json .
RUN npm install --production

# Copy application source
COPY src/ ./src/
COPY public/ ./public/
COPY tests/ ./tests/

# Own the files
RUN chown -R app:app /app
USER app

EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=5s --start-period=8s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/server.js"]
