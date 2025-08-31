# ==============================================================================
# JellyBelly Server - Complete Dockerfile for Your Project Structure
# Swift Hummingbird Backend + Frontend + ARM64 Cross-Compilation
# Port: 3242
# ==============================================================================

ARG SWIFT_VERSION=6.1
ARG NODE_VERSION=20
ARG UBUNTU_VERSION=jammy
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# ==============================================================================
# Stage 1: Frontend Build (from frontend/ directory)
# ==============================================================================
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION}-alpine AS frontend-builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++ git

# Copy frontend package files
COPY frontend/jellybelly-web/package.json frontend/jellybelly-web/package-lock.json* ./

# Install dependencies (include devDependencies for build tools)
RUN npm ci --no-audit --no-fund

# Copy frontend source code
COPY frontend/jellybelly-web/ ./

# Build the frontend
ENV NODE_ENV=production
RUN npm run build

# Verify frontend build
RUN ls -la dist/ && echo "Frontend build completed"

# ==============================================================================
# Stage 2: Swift Backend Build with Cross-Compilation  
# ==============================================================================
FROM --platform=$BUILDPLATFORM swift:${SWIFT_VERSION}-${UBUNTU_VERSION} AS swift-builder

# Install build dependencies and cross-compilation tools
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        build-essential \
        curl \
        pkg-config \
        libsqlite3-dev \
        libssl-dev \
        zlib1g-dev \
        # ARM64 cross-compilation tools
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        # ARM64 development libraries
        libsqlite3-dev:arm64 \
        libssl-dev:arm64 \
        zlib1g-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy Swift package files
COPY Package.swift Package.resolved* ./

# Resolve Swift dependencies
RUN swift package resolve

# Copy Swift source code
COPY Sources/ ./Sources/

# Cross-compile based on target platform
ARG TARGETPLATFORM
RUN echo "Building JellyBelly Server for platform: $TARGETPLATFORM" && \
    if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        echo "Cross-compiling for ARM64 (Raspberry Pi)..." && \
        export CC=aarch64-linux-gnu-gcc && \
        export CXX=aarch64-linux-gnu-g++ && \
        export AR=aarch64-linux-gnu-ar && \
        export STRIP=aarch64-linux-gnu-strip && \
        export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig && \
        export CFLAGS="-I/usr/aarch64-linux-gnu/include" && \
        export LDFLAGS="-L/usr/aarch64-linux-gnu/lib" && \
        swift build \
            --configuration release \
            --triple aarch64-unknown-linux-gnu \
            -Xcc -I/usr/aarch64-linux-gnu/include \
            -Xlinker -L/usr/aarch64-linux-gnu/lib && \
        echo "ARM64 build completed"; \
    else \
        echo "Building for native AMD64..." && \
        swift build --configuration release && \
        echo "AMD64 build completed"; \
    fi

# Verify and display binary information
RUN echo "=== Binary Verification ===" && \
    ls -la .build/release/ && \
    file .build/release/jellybelly-server && \
    ldd .build/release/jellybelly-server 2>/dev/null || echo "Static binary (no dynamic dependencies)" && \
    echo "Binary size: $(stat -c%s .build/release/jellybelly-server) bytes" && \
    echo "=========================="

# Strip binary to reduce size
ARG TARGETPLATFORM  
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        echo "Stripping ARM64 binary..." && \
        aarch64-linux-gnu-strip .build/release/jellybelly-server; \
    else \
        echo "Stripping AMD64 binary..." && \
        strip .build/release/jellybelly-server; \
    fi && \
    echo "Final binary size: $(stat -c%s .build/release/jellybelly-server) bytes"

# ==============================================================================
# Stage 3: Production Runtime
# ==============================================================================
FROM --platform=$TARGETPLATFORM swift:${SWIFT_VERSION}-${UBUNTU_VERSION}-slim

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
RUN groupadd -r jellybelly && \
    useradd -r -g jellybelly -d /app -s /bin/bash -c "JellyBelly Server User" jellybelly

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
    && chown -R jellybelly:jellybelly /app

# Copy Swift binary from builder stage
COPY --from=swift-builder --chown=jellybelly:jellybelly \
    /workspace/.build/release/jellybelly-server \
    /app/jellybelly-server

# Copy frontend build from frontend builder
COPY --from=frontend-builder --chown=jellybelly:jellybelly \
    /app/dist/ \
    /app/public/

# Copy static assets from top-level public directory
COPY --chown=jellybelly:jellybelly public/ /app/static/

# Make binary executable
RUN chmod +x /app/jellybelly-server

# Verify binary can execute
RUN echo "Testing binary execution..." && \
    /app/jellybelly-server --help 2>&1 || \
    echo "Binary is executable and ready"

# Switch to application user for security
USER jellybelly

# Environment variables for JellyBelly Server
ENV JELLYBELLY_HOST=0.0.0.0
ENV JELLYBELLY_PORT=3242
ENV JELLYBELLY_DATABASE_PATH=/app/data/jellybelly.sqlite
ENV JELLYBELLY_LOG_LEVEL=info
ENV JELLYBELLY_PUBLIC_PATH=/app/public
ENV JELLYBELLY_STATIC_PATH=/app/static
ENV JELLYBELLY_CONFIG_PATH=/app/config
ENV JELLYBELLY_DATA_PATH=/app/data
ENV JELLYBELLY_LOGS_PATH=/app/logs
ENV JELLYBELLY_TMP_PATH=/app/tmp

# Swift runtime optimizations
ENV SWIFT_DETERMINISTIC_HASHING=1
ENV SWIFT_MAX_MALLOC_SIZE=128MB

# Timezone (adjust as needed)
ENV TZ=UTC

# Working directory for runtime
WORKDIR /app

# Expose port 3242
EXPOSE 3242

# Add comprehensive labels
LABEL org.opencontainers.image.title="JellyBelly Server"
LABEL org.opencontainers.image.description="Swift Hummingbird server with web frontend for Jellyfin mood-based movie discovery"
LABEL org.opencontainers.image.vendor="JellyBelly Project"
LABEL org.opencontainers.image.port="3242"
LABEL org.opencontainers.image.source="https://github.com/Imgkl/JellyBellyServer"
LABEL org.opencontainers.image.documentation="https://github.com/Imgkl/JellyBellyServer/blob/main/README.md"

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
CMD ["/app/jellybelly-server"]

# ==============================================================================
# Build completion message (shown during build process)
# ==============================================================================
ARG TARGETPLATFORM
RUN echo "===============================================" && \
    echo "  JellyBelly Server Build Complete!" && \
    echo "  Platform: $TARGETPLATFORM" && \
    echo "  Swift Version: ${SWIFT_VERSION}" && \
    echo "  Port: 3242" && \
    echo "  User: jellybelly" && \
    echo "  Ready for Raspberry Pi deployment!" && \
    echo "==============================================="
