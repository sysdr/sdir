FROM node:20-slim
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
COPY public ./public
CMD ["node", "server.js"]
