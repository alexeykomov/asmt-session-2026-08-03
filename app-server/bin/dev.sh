#!/usr/bin/env bash
# Regenerate the Go protobuf bindings, build app-server, and run it with dev
# defaults.
#
#   ./app-server/bin/dev.sh          from the repo root
#   ./bin/dev.sh                     from app-server/
#   GRPC_PORT=51300 ./bin/dev.sh     override any default
#
# Only the Go bindings are regenerated. api/proto/generate_all.sh also builds
# the JS and Objective-C ones, which need their own protoc plugins installed;
# nothing in this path requires them.
set -euo pipefail

# Resolved BEFORE any cd. $0 is relative to the ORIGINAL working directory, so
# re-resolving it afterwards yields a path that does not exist — which is how a
# .env silently fails to load when the script is invoked by a relative path.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$SCRIPT_DIR/.."

# macOS ships an outdated /usr/local/go; prefer Homebrew's when present.
if [ -x /opt/homebrew/bin/go ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

# Load the repo-root .env — vendor endpoints and the shared gRPC token live
# there. Deliberately does NOT overwrite a variable already set, so a
# caller's `GRPC_PORT=... ./bin/dev.sh` still wins.
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

if [ ! -f "$REPO_ROOT/.env" ]; then
  echo "WARNING: no $REPO_ROOT/.env — copy .env.example and fill it in, or the" >&2
  echo "         providers will have no endpoints and auth will fail closed." >&2
fi

# Ports that do not collide with the deployed stack or with web-proxy.
export GRPC_PORT="${GRPC_PORT:-51200}"
export HEALTH_HTTP_PORT="${HEALTH_HTTP_PORT:-51201}"

# ALLOW_INSECURE_GRPC is deliberately NOT defaulted here. With
# INTERNAL_GRPC_TOKEN set in .env the server requires a bearer token exactly
# as in production; without one it fails closed and says so. A dev script that
# quietly disables auth is how an insecure default reaches a deployment.

echo "==> Regenerating Go protobuf bindings"
"$REPO_ROOT/api/proto/generate_go.sh"

echo "==> Building app-server"
go build -o bin/server ./cmd/server

echo "==> Starting app-server — gRPC :$GRPC_PORT, health :$HEALTH_HTTP_PORT"
exec ./bin/server
