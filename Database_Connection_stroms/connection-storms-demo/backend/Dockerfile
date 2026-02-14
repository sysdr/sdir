FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY src/ ./src/
EXPOSE 3001
HEALTHCHECK --interval=5s --timeout=3s --retries=5 \
  CMD wget -qO- http://localhost:3001/health || exit 1
CMD ["node", "src/server.js"]
