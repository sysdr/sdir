FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o resilient main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/resilient .
EXPOSE 8082
CMD ["./resilient"]
