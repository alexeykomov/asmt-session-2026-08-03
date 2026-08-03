#!/bin/bash
# Generate JavaScript code from .proto files for the web-proxy gRPC client.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../gen/js"

GRPC_TOOLS=""
if command -v grpc_tools_node_protoc &> /dev/null; then
  GRPC_TOOLS="grpc_tools_node_protoc"
elif [ -x "$SCRIPT_DIR/../../web-proxy/node_modules/.bin/grpc_tools_node_protoc" ]; then
  GRPC_TOOLS="$SCRIPT_DIR/../../web-proxy/node_modules/.bin/grpc_tools_node_protoc"
elif [ -x "$SCRIPT_DIR/../../node_modules/.bin/grpc_tools_node_protoc" ]; then
  GRPC_TOOLS="$SCRIPT_DIR/../../node_modules/.bin/grpc_tools_node_protoc"
fi

if [ -z "$GRPC_TOOLS" ]; then
  echo "SKIPPED: grpc_tools_node_protoc not found — generated JS is not"
  echo "required because web-proxy loads api/proto/recommendations.proto"
  echo "at runtime via @grpc/proto-loader. To generate JS anyway, install:"
  echo "  cd web-proxy && npm install -D grpc-tools"
  exit 0
fi

mkdir -p "$OUT_DIR"

echo "Generating JavaScript code..."
"$GRPC_TOOLS" \
  --js_out=import_style=commonjs,binary:"$OUT_DIR" \
  --grpc_out=grpc_js:"$OUT_DIR" \
  --proto_path="$SCRIPT_DIR" \
  "$SCRIPT_DIR"/*.proto

# Symlink node_modules so the generated stubs resolve @grpc/grpc-js and
# google-protobuf from web-proxy's deps (single singleton instance).
if [ ! -e "$OUT_DIR/node_modules" ]; then
  ln -s ../../../web-proxy/node_modules "$OUT_DIR/node_modules"
fi

echo "JavaScript generation complete: $OUT_DIR"
