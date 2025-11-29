FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o dns-server main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/dns-server .
EXPOSE 9000
CMD ["./dns-server"]
