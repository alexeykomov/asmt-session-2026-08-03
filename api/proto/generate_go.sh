#!/bin/bash
# Generate Go code from .proto files.
# Versions must stay in sync with app-server/Dockerfile and go.mod:
#   protoc-gen-go      v1.31.0
#   protoc-gen-go-grpc v1.3.0
#   google.golang.org/grpc v1.60.0
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Output path must match the go_package option in recommendations.proto:
#   github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api
OUT_DIR="$SCRIPT_DIR/../gen/go/funwithactivity/api"

if [ -d "/opt/homebrew/bin" ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
export PATH="$HOME/go/bin:$PATH"

if ! command -v protoc-gen-go &> /dev/null; then
  echo "Error: protoc-gen-go not found. Install with:"
  echo "  go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0"
  echo "  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Generating Go code..."
protoc \
  --go_out="$OUT_DIR" \
  --go_opt=paths=source_relative \
  --go-grpc_out="$OUT_DIR" \
  --go-grpc_opt=paths=source_relative \
  --proto_path="$SCRIPT_DIR" \
  "$SCRIPT_DIR"/*.proto

cat > "$OUT_DIR/go.mod" <<EOF
module github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api

go 1.23

require (
	google.golang.org/grpc v1.60.0
	google.golang.org/protobuf v1.31.0
)
EOF

echo "Go generation complete: $OUT_DIR"
