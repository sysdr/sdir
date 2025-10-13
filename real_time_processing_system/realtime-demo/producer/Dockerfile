FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY producer.js .
CMD ["node", "producer.js"]
