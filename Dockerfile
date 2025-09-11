# syntax=docker/dockerfile:1.7-labs
# ==============================================================================
# Rasa Server - Dockerfile
# Swift Hummingbird Backend + Frontend + ARM64 Cross-Compilation
# Port: 3242
# ==============================================================================

ARG SWIFT_VERSION=6.1
ARG NODE_VERSION=20
ARG UBUNTU_VERSION=jammy
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG RASA_VERSION=dev

# ==============================================================================
# Stage 1: Frontend Build (from frontend/ directory)
# ==============================================================================
FROM node:${NODE_VERSION}-alpine AS frontend-builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++ git

# Copy frontend package files
COPY frontend/rasa-web/package.json frontend/rasa-web/package-lock.json* ./

# Install dependencies (include devDependencies for build tools)
RUN --mount=type=cache,id=npm-cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# Copy frontend source code
COPY frontend/rasa-web/ ./

# Build the frontend
ENV NODE_ENV=production
RUN npm run build

# Verify frontend build outputs to /public as configured by Vite
RUN ls -la /public/ && echo "Frontend build completed"

# ==============================================================================
# Stage 2: Swift Backend Build with Cross-Compilation  
# ==============================================================================
FROM swift:${SWIFT_VERSION}-${UBUNTU_VERSION} AS swift-builder

# Install native build dependencies
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        build-essential \
        curl \
        pkg-config \
        libsqlite3-dev \
        libssl-dev \
        zlib1g-dev \
        binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy Swift package files
COPY Package.swift Package.resolved* ./

# Resolve Swift dependencies
RUN --mount=type=cache,id=spm-cache,target=/root/.swiftpm \
    --mount=type=cache,id=spm-ccache,target=/root/.cache \
    swift package resolve

# Copy Swift source code
COPY Sources/ ./Sources/

# Build natively for the target platform (buildx/QEMU handles emulation)
ARG TARGETPLATFORM
RUN --mount=type=cache,id=spm-cache,target=/root/.swiftpm \
    --mount=type=cache,id=spm-ccache,target=/root/.cache \
    echo "Building Rasa Server for target platform: $TARGETPLATFORM" && \
    swift build --configuration release --product RasaServer

# Verify and display binary information
RUN echo "=== Binary Verification ===" && \
    ls -la .build/release/ && \
    file .build/release/RasaServer || true && \
    ldd .build/release/RasaServer 2>/dev/null || echo "Static binary (no dynamic dependencies)" && \
    echo "Binary size: $(stat -c%s .build/release/RasaServer) bytes" || true && \
    echo "=========================="

# Strip binary to reduce size
RUN strip .build/release/RasaServer || true && \
    echo "Final binary size: $(stat -c%s .build/release/RasaServer) bytes" || true

# ==============================================================================
# Stage 3: Production Runtime
# ==============================================================================
FROM swift:${SWIFT_VERSION}-${UBUNTU_VERSION}-slim

# Bring build args into this stage
ARG RASA_VERSION

# Install runtime dependencies
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        # Core runtime libraries
        libsqlite3-0 \
        libssl3 \
        zlib1g \
        # Utilities for health checks and debugging
        curl \
        wget \
        ca-certificates \
        # Process management
        tini \
        # Timezone data
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application user and group
RUN groupadd -r rasa && \
    useradd -r -g rasa -d /app -s /bin/bash -c "Rasa Server User" rasa

# Set working directory
WORKDIR /app

# Create application directory structure
RUN mkdir -p \
        /app/data \
        /app/config \
        /app/logs \
        /app/public \
        /app/static \
        /app/tmp \
    && chown -R rasa:rasa /app

# Copy Swift binary from builder stage
COPY --from=swift-builder --chown=rasa:rasa \
    /workspace/.build/release/RasaServer \
    /app/rasa-server

# Copy frontend build from frontend builder (Vite outDir -> /public)
COPY --from=frontend-builder --chown=rasa:rasa \
    /public/ \
    /app/public/

# Copy static assets from top-level public directory
COPY --chown=rasa:rasa public/ /app/static/

# Make binary executable
RUN chmod +x /app/rasa-server

# Switch to application user for security
USER rasa

# Environment variables for Rasa Server
ENV RASA_HOST=0.0.0.0
ENV RASA_PORT=3242
ENV WEBUI_PORT=3242
ENV RASA_DATABASE_PATH=/app/data/rasa.sqlite
ENV RASA_VERSION=${RASA_VERSION}

# Swift runtime optimizations
ENV SWIFT_DETERMINISTIC_HASHING=1
ENV SWIFT_MAX_MALLOC_SIZE=128MB

# Timezone (adjust as needed)
ENV TZ=UTC

# Working directory for runtime
WORKDIR /app

# Expose port 3242
EXPOSE 3242

# OCI labels
LABEL org.opencontainers.image.title="Rasa Server"
LABEL org.opencontainers.image.description="Self-hosted mood tagging server for Jellyfin with admin web UI"
LABEL org.opencontainers.image.vendor="Rasa Project"
LABEL org.opencontainers.image.port="3242"
LABEL org.opencontainers.image.version="${RASA_VERSION}"

# Health check configuration
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=60s \
            --retries=3 \
    CMD curl -f http://localhost:3242/health || exit 1

# Volume declarations for persistent data
VOLUME ["/app/data", "/app/config", "/app/logs"]

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Default command to run the server
CMD ["/app/rasa-server"]
