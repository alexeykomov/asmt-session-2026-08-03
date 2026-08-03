.PHONY: help setup codegen build build-server build-web test docker-up docker-down dev clean

help:
	@echo "FunWithActivity - Development Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          Install all dependencies"
	@echo "  make codegen        Generate code from .proto files"
	@echo ""
	@echo "Build:"
	@echo "  make build          Build all components"
	@echo "  make build-server   Build Go app-server binary"
	@echo "  make build-web      Build Closure web-client bundle"
	@echo ""
	@echo "Development:"
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

clean:
	rm -rf app-server/bin
	rm -rf web-client/public/*.js
	rm -rf web-client/public/*.css
	rm -rf web-client/css/*.min.css
	rm -rf api/gen
	rm -rf .soy-cache
