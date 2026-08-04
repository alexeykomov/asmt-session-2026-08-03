.PHONY: help setup proto codegen build build-server build-web test docker-up docker-down dev run-server run-proxy clean

help:
	@echo "FunWithActivity - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          Install all dependencies"
	@echo "  make proto          Regenerate ALL protos: Go, JS, Obj-C, Java"
	@echo "  make codegen        Same, minus Java (Go/JS/Obj-C only)"
	@echo ""
	@echo "Build:"
	@echo "  make build          Build all components"
	@echo "  make build-server   Build Go app-server binary"
	@echo "  make build-web      Build Closure web-client bundle"
	@echo ""
	@echo "Development:"
	@echo "  make run-server     Regenerate Go protos + run app-server locally"
	@echo "  make run-proxy      Run web-proxy locally against it"
	@echo "  make dev            docker-compose up (app-server + web-proxy)"
	@echo "  make docker-up      docker-compose up -d"
	@echo "  make docker-down    docker-compose down"
	@echo "  make test           Run all unit + integration tests"
	@echo "  make clean          Remove build artifacts"

setup:
	@echo "==> Installing dependencies"
	cd web-proxy && npm install
	cd web-client && npm install
	cd app-server && go mod download

codegen:
	@echo "==> Generating proto code"
	./api/proto/generate_all.sh

# Every platform, including Android. Android is separate because its bindings
# are not committed: protobuf-gradle-plugin regenerates them from api/proto on
# each build, so generate_all.sh has nothing to do for it. iOS is the reverse —
# its generated sources ARE committed (see docs/decisions/0003), which is why
# generate_all.sh writes them.
proto: codegen
	@echo "==> Java (Android, via protobuf-gradle-plugin)"
	cd android-client && ./gradlew :app:generateDebugProto

build: build-server build-web

build-server: codegen
	@echo "==> Building app-server"
	cd app-server && go build -o bin/server ./cmd/server

build-web:
	@echo "==> Building web-client (Closure ADVANCED)"
	cd web-client && npm run build

test:
	@echo "==> Running tests"
	cd app-server && go test ./...
	cd web-proxy && npm test
	cd web-client && npm test

docker-up:
	docker compose -f deploy/docker-compose.yml up -d --build

docker-down:
	docker compose -f deploy/docker-compose.yml down

dev:
	docker compose -f deploy/docker-compose.yml up --build

# Local run, without Docker. Regenerates only the Go bindings — `codegen`
# also builds the iOS and JS ones and therefore needs their protoc plugins
# installed, which this path does not require.
#
# Auth follows .env: with INTERNAL_GRPC_TOKEN set, app-server requires a
# bearer token exactly as in production. ALLOW_INSECURE_GRPC is deliberately
# NOT set here — a local default that silently disables auth is how an
# insecure config reaches a deploy.
GRPC_PORT ?= 51200
HEALTH_HTTP_PORT ?= 51201
PROXY_PORT ?= 51202

run-server:
	@test -f .env || { echo "No .env at repo root — copy .env.example and fill it in"; exit 1; }
	@echo "==> Generating Go proto bindings"
	@./api/proto/generate_go.sh
	@echo "==> app-server: gRPC :$(GRPC_PORT), health :$(HEALTH_HTTP_PORT)"
	@set -a; . ./.env; set +a; \
		cd app-server && \
		GRPC_PORT=$(GRPC_PORT) HEALTH_HTTP_PORT=$(HEALTH_HTTP_PORT) \
		go run ./cmd/server

run-proxy:
	@test -f .env || { echo "No .env at repo root — copy .env.example and fill it in"; exit 1; }
	@echo "==> web-proxy on :$(PROXY_PORT), app-server at localhost:$(GRPC_PORT)"
	@set -a; . ./.env; set +a; \
		cd web-proxy && \
		PORT=$(PROXY_PORT) APP_SERVER_URL=localhost:$(GRPC_PORT) \
		node src/server.js

clean:
	rm -rf app-server/bin
	rm -rf web-client/public/*.js
	rm -rf web-client/public/*.css
	rm -rf web-client/css/*.min.css
	rm -rf api/gen
	rm -rf .soy-cache
