#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${CAPTURE_URL:?Set CAPTURE_URL}"
: "${CAPTURE_DIR:?Set CAPTURE_DIR}"

if ! /usr/bin/time -p test -f "$PROJECT_DIR/scripts/capture.mjs"; then
    echo "Missing capture driver: $PROJECT_DIR/scripts/capture.mjs" >&2
    exit 1
fi

/usr/bin/time -p mkdir -p "$CAPTURE_DIR"

exec /usr/bin/time -p node "$PROJECT_DIR/scripts/capture.mjs"
