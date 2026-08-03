#!/bin/bash
# Generate code for all platforms from .proto files
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== FunWithActivity Proto Code Generation ==="
echo ""

echo "[1/3] Go..."
if ./generate_go.sh; then
  echo "  OK"
else
  echo "  FAILED (see error above)"
  exit 1
fi
echo ""

echo "[2/3] JavaScript (optional)..."
if ./generate_js.sh; then
  echo "  OK (or SKIPPED — see above)"
else
  echo "  FAILED (see error above)"
  exit 1
fi
echo ""

echo "[3/3] iOS/Objective-C (optional)..."
if command -v grpc_objective_c_plugin &> /dev/null || \
   [ -x "/opt/homebrew/bin/grpc_objective_c_plugin" ] || \
   [ -x "/usr/local/bin/grpc_objective_c_plugin" ]; then
  if ./generate_ios.sh; then
    echo "  OK"
  else
    echo "  FAILED (see error above) — non-fatal, continuing"
  fi
else
  echo "SKIPPED: grpc_objective_c_plugin not found — generated Objective-C is"
  echo "not required on CI (e.g. a Linux box building app-server/web-proxy has"
  echo "no Xcode toolchain). To generate it, install: brew install grpc"
fi
echo ""

echo "=== Generation Complete ==="
