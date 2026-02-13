FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
COPY main.go .
RUN go build -o goservice main.go

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/goservice .

# Tuning env vars — override at runtime
ENV GOGC=100
ENV GOMEMLIMIT=""
ENV PORT=8081

EXPOSE 8081
CMD ["./goservice"]
