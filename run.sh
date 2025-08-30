#!/bin/sh
set -euo pipefail
cd frontend/jellybelly-web && npm install && npm run build
cd ../../
swift build
# Run built binary directly to avoid swift run teardown racing the HTTP client deinit
exec .build/debug/JellybellyServer
