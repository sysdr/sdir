FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json .
RUN npm install --legacy-peer-deps
COPY public/ ./public/
COPY src/ ./src/
ENV REACT_APP_BACKEND_URL=http://localhost:3001
RUN npm run build

FROM nginx:1.25-alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=5s --timeout=3s --retries=5 CMD wget -qO- http://localhost:80/ || exit 1
