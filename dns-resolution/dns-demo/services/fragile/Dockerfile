FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o fragile main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/fragile .
EXPOSE 8081
CMD ["./fragile"]
