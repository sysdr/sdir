FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

EXPOSE 9001/udp 9002 3000

CMD ["npm", "run", "server"]
