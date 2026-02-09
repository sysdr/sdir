FROM node:18-slim

RUN apt-get update && apt-get install -y \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json .
RUN npm install
COPY transcoder.js .

RUN mkdir -p /output/1080p /output/720p /output/480p /output/360p

CMD ["node", "transcoder.js"]
