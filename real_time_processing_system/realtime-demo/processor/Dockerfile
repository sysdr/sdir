FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY processor.js .
CMD ["node", "processor.js"]
