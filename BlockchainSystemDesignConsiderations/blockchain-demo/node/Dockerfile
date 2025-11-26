FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY *.js ./

EXPOSE 3000

CMD ["node", "server.js"]
