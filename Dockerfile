###############################################
# http_caching_server Dockerfile
# Multi-stage build for smaller runtime image.
# Supports linux/amd64 & linux/arm64 (use buildx for multi-arch push).
###############################################

### 1) Build Stage ###########################################################
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG RUSTFLAGS
ARG CARGO_PROFILE=release
ENV CARGO_TERM_COLOR=always \
	RUSTFLAGS="${RUSTFLAGS}"

WORKDIR /app

# (A) Cache deps layer: copy manifests only, build a dummy to pre-build deps
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo "fn main(){}" > src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/app/target \
	cargo build --${CARGO_PROFILE} || true

# (B) Copy real sources & build
COPY src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/app/target \
	cargo build --${CARGO_PROFILE}

# Result binary path
RUN cp target/${CARGO_PROFILE}/http_caching_server /app/server

### 2) Runtime Stage #########################################################
# Use slim Debian for OpenSSL (hyper-tls / native-tls) + smaller footprint
FROM debian:bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \ 
	&& apt-get install -y --no-install-recommends ca-certificates openssl tzdata \ 
	&& rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd -u 10001 -m -d /app appuser
WORKDIR /app

# Copy binary
COPY --from=builder /app/server /app/http_caching_server

# Create default cache dir (can be mounted as volume)
RUN mkdir -p /app/cache && chown -R appuser:appuser /app

ENV LISTEN_ADDR=0.0.0.0:8080 \
	CACHE_DIR=/app/cache \
	DEFAULT_TTL_SECS=300 \
	MAX_CACHE_SIZE_BYTES=$((5*1024*1024*1024))

EXPOSE 8080
USER appuser

# Healthcheck: simple TCP connect attempt to the port
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && echo -e "GET /health HTTP/1.0\r\n\r\n" >&3 && timeout 2 cat <&3 | grep -qi "200" || exit 1' || exit 1

ENTRYPOINT ["/app/http_caching_server"]

# Build examples:
#   docker build -t http-caching-server .
#   docker run --rm -p 8080:8080 -e UPSTREAM_BASE=https://example.com \
#       -v cache_data:/app/cache http-caching-server
# Multi-arch buildx:
#   docker buildx build --platform linux/amd64,linux/arm64 -t user/http-caching-server:latest . --push
