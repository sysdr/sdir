FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

RUN mkdir -p database

EXPOSE 8000

CMD ["npm", "start"]
