FROM node:20-slim

WORKDIR /app

COPY package.json .
RUN npm install --production

COPY src/ ./src/
COPY ui/ ./ui/
COPY tests/ ./tests/

EXPOSE 3000

CMD ["node", "src/server.js"]
