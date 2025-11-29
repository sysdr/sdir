FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o backend main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/backend .
EXPOSE 8080
CMD ["./backend"]
