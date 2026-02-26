FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY generator.js .
EXPOSE 4000
CMD ["node", "generator.js"]
