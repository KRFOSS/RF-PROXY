FROM rust:latest AS builder

WORKDIR /app

COPY . .

RUN cargo build -r

FROM debian:stable-slim

WORKDIR /app

COPY --from=builder /app/target/release/rf-proxy .

CMD ["./rf-proxy"]
