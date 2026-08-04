#!/usr/bin/env bash
# Run web-proxy with dev defaults, pointed at a locally running app-server.
#
#   ./web-proxy/bin/dev.sh           from the repo root
#   ./bin/dev.sh                     from web-proxy/
#   PORT=51400 ./bin/dev.sh          override any default
#
# Start app-server first (app-server/bin/dev.sh) — this process starts fine
# without it and every /api call then answers 502 upstream_unavailable, which
# looks like a proxy bug and is not one.
set -euo pipefail

# Resolved BEFORE any cd, for the same reason as app-server/bin/dev.sh: $0 is
# relative to the original working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR/.."

# Load the repo-root .env without overwriting anything already set, so a
# caller's `PORT=... ./bin/dev.sh` still wins. INTERNAL_GRPC_TOKEN comes from
# here and must match what app-server is running with, or every call returns
# 16 UNAUTHENTICATED while the browser just sees a gateway error.
__fwa_load_dotenv() {
  local envf="$1" line key
  [ -f "$envf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"
    [ "$key" = "$line" ] && continue
    [ -z "${!key:-}" ] && export "$line"
  done < "$envf"
  return 0
}
__fwa_load_dotenv "$REPO_ROOT/.env"

export PORT="${PORT:-51202}"
export APP_SERVER_URL="${APP_SERVER_URL:-localhost:${GRPC_PORT:-51200}}"

if [ ! -d node_modules ]; then
  echo "==> Installing dependencies"
  npm install
fi

# web-proxy serves web-client/public as static files. Without a build there is
# no bundle to serve and the page loads to a blank shell — a failure with
# nothing in the console to explain it.
if [ ! -f "$REPO_ROOT/web-client/public/main.min.js" ]; then
  echo "WARNING: web-client is not built — run 'npm run build' in web-client/," >&2
  echo "         or the page will load an empty shell." >&2
fi

echo "==> web-proxy on :$PORT, app-server at $APP_SERVER_URL"
exec node src/server.js
