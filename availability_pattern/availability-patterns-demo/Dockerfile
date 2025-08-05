FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY src/ ./src/
COPY dashboard/ ./dashboard/

EXPOSE 3000 4000 8000

CMD ["npm", "start"]
