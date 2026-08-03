#!/bin/bash
# Generate Objective-C code from .proto files for the FunWithActivity iOS client.
#
# Adapted from cyberfight/api/proto/generate_ios.sh (same author, verified
# working command). Output lands in FunWithActivityCore/Generated so it
# compiles into the shared static library alongside the networking wrapper —
# app target owns only shell composition (see apple-client house rules).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../../apple-client/FunWithActivityCore/Generated"

# Check for grpc_objective_c_plugin
GRPC_PLUGIN=""
if command -v grpc_objective_c_plugin &> /dev/null; then
    GRPC_PLUGIN="$(which grpc_objective_c_plugin)"
elif [ -x "/opt/homebrew/bin/grpc_objective_c_plugin" ]; then
    GRPC_PLUGIN="/opt/homebrew/bin/grpc_objective_c_plugin"
elif [ -x "/usr/local/bin/grpc_objective_c_plugin" ]; then
    GRPC_PLUGIN="/usr/local/bin/grpc_objective_c_plugin"
fi

if [ -z "$GRPC_PLUGIN" ]; then
    echo "Error: grpc_objective_c_plugin not found. Install with:"
    echo "  brew install grpc"
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "Generating Objective-C code..."
protoc \
    --objc_out="$OUT_DIR" \
    --grpc_out="$OUT_DIR" \
    --plugin=protoc-gen-grpc="$GRPC_PLUGIN" \
    --proto_path="$SCRIPT_DIR" \
    "$SCRIPT_DIR"/recommendations.proto

echo "Objective-C generation complete: $OUT_DIR"
