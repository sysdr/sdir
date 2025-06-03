FROM node:18-alpine

WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S vectorclock -u 1001

# Copy application files
COPY vector_clock.js package.json ./

# Install dependencies (if any)
RUN npm install --production 2>/dev/null || true

# Set ownership
RUN chown -R vectorclock:nodejs /app
USER vectorclock

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/status || exit 1

EXPOSE ${PORT}

CMD ["node", "vector_clock.js"]
