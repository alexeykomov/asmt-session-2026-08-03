# Stage 1: Generate Go proto code
FROM golang:1.23-alpine AS proto-builder

RUN apk add --no-cache protobuf protobuf-dev
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0

WORKDIR /proto

# Build context is repo root
COPY api/proto/*.proto ./

RUN mkdir -p /gen/funwithactivity/api && \
    protoc \
        --go_out=/gen/funwithactivity/api \
        --go_opt=paths=source_relative \
        --go-grpc_out=/gen/funwithactivity/api \
        --go-grpc_opt=paths=source_relative \
        --proto_path=. \
        ./*.proto && \
    printf 'module github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api\n\ngo 1.23\n\nrequire (\n\tgoogle.golang.org/grpc v1.60.0\n\tgoogle.golang.org/protobuf v1.31.0\n)\n' > /gen/funwithactivity/api/go.mod

# Stage 2: Build Go binary
FROM golang:1.23-alpine AS builder

WORKDIR /build

COPY app-server/go.mod app-server/go.sum ./
COPY --from=proto-builder /gen/ ./api/gen/go/
COPY app-server/ ./

# Fix replace path: local dev uses ../api/gen/...; in the container the proto-gen
# output is colocated under ./api/gen/...
RUN sed -i 's|=> ../api/gen/go/funwithactivity/api|=> ./api/gen/go/funwithactivity/api|g' go.mod

RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o bin/server ./cmd/server

# Stage 3: Runtime image
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /build/bin/ ./bin/

EXPOSE 50051 50052

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:50052/health || exit 1

CMD ["./bin/server"]
