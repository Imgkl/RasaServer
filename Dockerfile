# Build stage
FROM --platform=$BUILDPLATFORM node:20-alpine AS web

WORKDIR /workspace

# Install dependencies and build frontend → writes to /workspace/public
COPY frontend/jellybelly-web/package*.json frontend/jellybelly-web/
RUN cd frontend/jellybelly-web && npm ci
COPY frontend/jellybelly-web frontend/jellybelly-web
RUN cd frontend/jellybelly-web && npm run build

# Build stage
FROM --platform=$BUILDPLATFORM swift:6.0-jammy AS builder

WORKDIR /app

# No cross-compilation: Buildx/QEMU will run native builds per platform

# Copy package files first for better layer caching
COPY Package.swift Package.resolved ./

# Resolve dependencies
RUN swift package resolve

# Copy source code
COPY Sources ./Sources

# Copy built web assets from the web stage
COPY --from=web /workspace/public ./public

# Build the application (native within the emulated platform)
RUN swift build -c release --static-swift-stdlib

# Runtime stage - use ARM64-capable base for Pi
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN groupadd -r jellybelly && useradd -r -g jellybelly jellybelly

# Create app directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/.build/release/JellybellyServer /app/jellybelly-server

# Copy public directory for web dashboard
COPY --from=builder /app/public /app/public

# Default config mount point
VOLUME ["/app/data", "/app/config", "/app/logs"]

# Create data directories and set permissions
RUN mkdir -p /app/data /app/config /app/logs && \
    chown -R jellybelly:jellybelly /app && \
    chmod +x /app/jellybelly-server

# Switch to app user
USER jellybelly

# Default server port; Jellybelly reads JELLYBELLY_PORT
ENV JELLYBELLY_PORT=8001

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${JELLYBELLY_PORT}/health || exit 1

# Set default command
ENTRYPOINT ["/app/jellybelly-server"]
