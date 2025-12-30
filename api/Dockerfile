FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod download
RUN go build checkers
RUN apk add --update openssl && rm -rf /var/cache/apk/*
RUN openssl ecparam -name prime256v1 -genkey -noout -out private_key.pem
RUN openssl ec -in private_key.pem -pubout > public_key.pem

FROM alpine:latest AS runner
WORKDIR /app
COPY --from=builder /app/checkers .
COPY --from=builder /app/*.pem .
EXPOSE 8080
ENTRYPOINT ["./checkers"]