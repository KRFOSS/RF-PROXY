FROM rust:latest AS builder

RUN apt update -y && apt install -y musl-tools

WORKDIR /app

COPY . .

RUN cargo build --release --target x86_64-unknown-linux-musl

FROM debian:stable-slim

WORKDIR /app

COPY --from=builder /app/target/release/rf-proxy .

CMD ["./rf-proxy"]
