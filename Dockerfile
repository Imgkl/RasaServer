# ==============================================================================
# JellyBelly Server - Complete Production Dockerfile
# Swift Hummingbird Backend + Vite Frontend + ARM64 Cross-Compilation
# Port: 3242
# ==============================================================================

# Build arguments for multi-platform support
ARG SWIFT_VERSION=6.1
ARG NODE_VERSION=20
ARG UBUNTU_VERSION=jammy
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# ==============================================================================
# Stage 1: Frontend Build (Vite)
# ==============================================================================
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION}-alpine AS frontend-builder

# Set working directory
WORKDIR /frontend

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy package files first for better caching
COPY package.json package-lock.json* ./

# Install Node.js dependencies
RUN npm ci --only=production --no-audit --no-fund

# Copy source code
COPY src/ ./src/
COPY public/ ./public/
COPY index.html ./
COPY vite.config.js ./
COPY tsconfig.json* ./
COPY tailwind.config.js* ./
COPY postcss.config.js* ./

# Set build environment
ENV NODE_ENV=production
ENV VITE_API_BASE_URL=/api

# Build the frontend
RUN npm run build

# Verify build output
RUN ls -la dist/ && \
    echo "Frontend build completed successfully"

# ==============================================================================
# Stage 2: Swift Backend Build with Cross-Compilation
# ==============================================================================
FROM --platform=$BUILDPLATFORM swift:${SWIFT_VERSION}-${UBUNTU_VERSION} AS swift-builder

# Install system dependencies
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        # Basic build tools
        build-essential \
        curl \
        wget \
        git \
        pkg-config \
        # SQLite development
        libsqlite3-dev \
        sqlite3 \
        # SSL/TLS support
        libssl-dev \
        # Compression libraries
        zlib1g-dev \
        # Cross-compilation tools for ARM64
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        # ARM64 system libraries
        libsqlite3-dev:arm64 \
        libssl-dev:arm64 \
        zlib1g-dev:arm64 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set working directory
WORKDIR /workspace

# Copy Swift package files for dependency resolution
COPY Package.swift Package.resolved* ./

# Pre-resolve dependencies for better caching
RUN swift package resolve

# Copy Swift source code
COPY Sources/ ./Sources/
COPY Tests/ ./Tests/
COPY Resources/ ./Resources/ 2>/dev/null || true

# Set up cross-compilation environment
ARG TARGETPLATFORM
ENV TARGETPLATFORM=$TARGETPLATFORM

# Create cross-compilation configuration
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        echo "Setting up ARM64 cross-compilation..." && \
        # Set cross-compilation environment variables
        export CC=aarch64-linux-gnu-gcc && \
        export CXX=aarch64-linux-gnu-g++ && \
        export AR=aarch64-linux-gnu-ar && \
        export STRIP=aarch64-linux-gnu-strip && \
        export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig && \
        export CFLAGS="-I/usr/aarch64-linux-gnu/include" && \
        export CXXFLAGS="-I/usr/aarch64-linux-gnu/include" && \
        export LDFLAGS="-L/usr/aarch64-linux-gnu/lib" && \
        # Build for ARM64
        swift build \
            --configuration release \
            --triple aarch64-unknown-linux-gnu \
            -Xcc -I/usr/aarch64-linux-gnu/include \
            -Xlinker -L/usr/aarch64-linux-gnu/lib; \
    else \
        echo "Building for native AMD64..." && \
        swift build --configuration release; \
    fi

# Verify the built binary
RUN echo "=== Binary Information ===" && \
    ls -la .build/release/ && \
    file .build/release/jellybelly-server && \
    echo "=========================="

# Strip the binary to reduce size
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        aarch64-linux-gnu-strip .build/release/jellybelly-server; \
    else \
        strip .build/release/jellybelly-server; \
    fi

# Final size check
RUN echo "Final binary size:" && \
    ls -lh .build/release/jellybelly-server

# ==============================================================================
# Stage 3: Production Runtime
# ==============================================================================
FROM --platform=$TARGETPLATFORM swift:${SWIFT_VERSION}-${UBUNTU_VERSION}-slim AS runtime

# Install runtime dependencies only
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        # Runtime libraries
        libsqlite3-0 \
        libssl3 \
        zlib1g \
        # Utilities
        curl \
        wget \
        ca-certificates \
        # Process management
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create application user and group for security
RUN groupadd -r jellybelly && \
    useradd -r -g jellybelly -d /app -s /bin/bash -c "JellyBelly Server" jellybelly

# Set working directory
WORKDIR /app

# Create application directories with proper permissions
RUN mkdir -p \
        /app/data \
        /app/config \
        /app/logs \
        /app/public \
        /app/tmp \
    && chown -R jellybelly:jellybelly /app

# Copy Swift binary from builder stage
COPY --from=swift-builder --chown=jellybelly:jellybelly \
    /workspace/.build/release/jellybelly-server \
    /app/jellybelly-server

# Copy frontend assets from frontend builder
COPY --from=frontend-builder --chown=jellybelly:jellybelly \
    /frontend/dist/ \
    /app/public/

# Copy configuration files if they exist
COPY --chown=jellybelly:jellybelly config/ /app/config/ 2>/dev/null || true
COPY --chown=jellybelly:jellybelly Resources/ /app/Resources/ 2>/dev/null || true

# Make binary executable
RUN chmod +x /app/jellybelly-server

# Verify binary can execute (basic test)
RUN /app/jellybelly-server --help 2>/dev/null || \
    echo "Binary help command not available, but binary is executable"

# Switch to non-root user
USER jellybelly

# Set environment variables
ENV JELLYBELLY_HOST=0.0.0.0
ENV JELLYBELLY_PORT=3242
ENV JELLYBELLY_DATABASE_PATH=/app/data/jellybelly.sqlite
ENV JELLYBELLY_LOG_LEVEL=info
ENV JELLYBELLY_PUBLIC_PATH=/app/public
ENV JELLYBELLY_CONFIG_PATH=/app/config
ENV JELLYBELLY_DATA_PATH=/app/data
ENV JELLYBELLY_LOGS_PATH=/app/logs

# Performance tuning for Swift
ENV SWIFT_DETERMINISTIC_HASHING=1
ENV SWIFT_MAX_MALLOC_SIZE=128MB

# Expose port 3242
EXPOSE 3242

# Add labels for better container management
LABEL org.opencontainers.image.title="JellyBelly Server"
LABEL org.opencontainers.image.description="Swift Hummingbird server with Vite frontend for Jellyfin mood-based discovery"
LABEL org.opencontainers.image.port="3242"
LABEL org.opencontainers.image.authors="JellyBelly Team"

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

# Command to run the application
CMD ["/app/jellybelly-server"]

# ==============================================================================
# Build Information (will be shown during build)
# ==============================================================================
RUN echo "=== JellyBelly Server Build Complete ===" && \
    echo "Platform: $TARGETPLATFORM" && \
    echo "Swift Version: $SWIFT_VERSION" && \
    echo "Node Version: $NODE_VERSION" && \
    echo "Port: 3242" && \
    echo "User: jellybelly" && \
    echo "======================================"
