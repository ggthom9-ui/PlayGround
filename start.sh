#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${OPENCODE_WEB_DIR:?OPENCODE_WEB_DIR is required}"
PORT="${PORT:-3000}"

case "$PORT" in
    ''|*[!0-9]*)
        echo "PORT must be a number, got: $PORT" >&2
        exit 1
        ;;
esac

WEB_SRC="$PROJECT_DIR/web"
SITE_DIR="$PROJECT_DIR/dist/web"
APK="$PROJECT_DIR/dist/thomkhali-1.0.0.apk"

if ! /usr/bin/time -p test -d "$WEB_SRC"; then
    echo "Missing static source directory: $WEB_SRC" >&2
    exit 1
fi

if ! /usr/bin/time -p test -f "$APK"; then
    echo "APK not found, building it first"
    /usr/bin/time -p bash "$PROJECT_DIR/app/build.sh"
fi

/usr/bin/time -p rm -rf "$SITE_DIR"
/usr/bin/time -p mkdir -p "$SITE_DIR"
/usr/bin/time -p cp -a "$WEB_SRC/." "$SITE_DIR/"
/usr/bin/time -p cp "$APK" "$SITE_DIR/thomkhali-1.0.0.apk"

/usr/bin/time -p mkdir -p "$OPENCODE_WEB_DIR"
/usr/bin/time -p node -e '
const fs = require("node:fs");
const [output, project, directory] = process.argv.slice(1);
fs.writeFileSync(output, JSON.stringify({ project, directory }) + "\n");
' "$OPENCODE_WEB_DIR/deployment-output.json" "$PROJECT_DIR" "$SITE_DIR"

/usr/bin/time -p printf 'Serving %s on http://0.0.0.0:%s\n' "$SITE_DIR" "$PORT"

cd "$SITE_DIR"
exec /usr/bin/time -p python3 -m http.server "$PORT" --bind 0.0.0.0
