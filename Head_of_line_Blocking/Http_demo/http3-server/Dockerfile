FROM node:18-alpine

WORKDIR /app

COPY package.json .
RUN npm install --production

COPY server.js .

EXPOSE 8444

CMD ["node", "server.js"]
