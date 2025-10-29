FROM node:18-alpine

WORKDIR /app

# Install curl for healthcheck
RUN apk add --no-cache curl

COPY package*.json ./
RUN npm install --only=production

COPY . .

EXPOSE 3001

CMD ["npm", "start"]
