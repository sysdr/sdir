FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

RUN mkdir -p /app/views && ls -la /app/views/

EXPOSE 3000

CMD ["npm", "start"]
