# Make it executable
# chmod +x run.sh
# and run it with ./run.sh

#!/bin/sh
set -euo pipefail
cd frontend/jellybelly-web && npm install && npm run build
cd ../../
mkdir -p data
swift build
DB_PATH="${JELLYBELLY_DATABASE_PATH:-$PWD/data/jellybelly.sqlite}"
exec env JELLYBELLY_DATABASE_PATH="$DB_PATH" .build/debug/JellybellyServer
