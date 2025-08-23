FROM node:18-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
