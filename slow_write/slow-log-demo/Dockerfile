FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY app ./app
COPY dashboard ./dashboard

EXPOSE 3000

CMD ["npm", "start"]
