FROM node:18-alpine

WORKDIR /app

COPY package.json .
RUN npm install --legacy-peer-deps
RUN npm install ajv@^8.0.0 --legacy-peer-deps

COPY public ./public
COPY src ./src

EXPOSE 3000

CMD ["npm", "start"]
