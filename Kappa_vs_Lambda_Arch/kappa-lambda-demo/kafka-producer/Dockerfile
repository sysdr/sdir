FROM node:20-alpine
RUN apk add --no-cache wget
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "src/producer.js"]
