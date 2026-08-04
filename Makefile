.PHONY: help setup proto codegen build build-server build-web test docker-up docker-down dev run-server run-proxy ios android clean

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
	@echo "  make ios            Build, install and launch iOS on a booted simulator"
	@echo "  make android        Build, install and launch Android on the emulator"
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

# Build, install and launch the mobile clients against whatever GRPC_HOST /
# GRPC_USE_TLS are currently uncommented in .env.
SIM_NAME ?= iPhone 16

ios:
	@test -f .env || { echo "No .env at repo root"; exit 1; }
	@echo "==> Regenerating xcconfig from .env"
	@./apple-client/Config/generate-xcconfig.sh
	# generate_project.rb parses the xcconfig and bakes the values into the
	# pbxproj's GCC_PREPROCESSOR_DEFINITIONS — the xcconfig is never read at
	# build time. Regenerating it alone therefore changes nothing, which is
	# exactly the trap this line exists to avoid. pod install must follow,
	# because regenerating the project drops the CocoaPods integration.
	@echo "==> Regenerating project + pods"
	@cd apple-client && ruby generate_project.rb >/dev/null && pod install >/dev/null 2>&1
	@echo "==> Building"
	@cd apple-client && xcodebuild -workspace FunWithActivity.xcworkspace \
		-scheme FunWithActivity -sdk iphonesimulator \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)' build \
		| grep -E "error:|BUILD" || true
	@echo "==> Installing and launching"
	@SIM=$$(xcrun simctl list devices booted | grep -oE "\([0-9A-F-]{36}\)" | head -1 | tr -d '()'); \
	 test -n "$$SIM" || { echo "No booted simulator — open Simulator.app first"; exit 1; }; \
	 APP=$$(find ~/Library/Developer/Xcode/DerivedData -name FunWithActivity.app -type d \
	        -path "*Debug-iphonesimulator*" 2>/dev/null | head -1); \
	 xcrun simctl install "$$SIM" "$$APP" && \
	 xcrun simctl terminate "$$SIM" com.funwithactivity.ios 2>/dev/null; \
	 xcrun simctl launch "$$SIM" com.funwithactivity.ios && echo "==> launched"

# The Android emulator cannot reach the host on loopback — 10.0.2.2 is its
# alias for the host machine. Rewriting it here keeps .env single-valued
# instead of needing a separate Android-only host key.
android:
	@test -f .env || { echo "No .env at repo root"; exit 1; }
	@HOST=$$(grep -E '^GRPC_HOST=' .env | cut -d= -f2- | sed 's/localhost/10.0.2.2/;s/127\.0\.0\.1/10.0.2.2/'); \
	 TLS=$$(grep -E '^GRPC_USE_TLS=' .env | cut -d= -f2-); \
	 TOKEN=$$(grep -E '^INTERNAL_GRPC_TOKEN=' .env | cut -d= -f2-); \
	 echo "==> Building against $$HOST (TLS=$$TLS)"; \
	 cd android-client && ./gradlew assembleDebug -q \
	   -PserverHost="$$HOST" -PserverTls="$$TLS" -PserverToken="$$TOKEN"
	@echo "==> Installing and launching"
	@adb install -r android-client/app/build/outputs/apk/debug/app-debug.apk | tail -1
	@adb shell am force-stop com.funwithactivity.app
	@adb shell am start -n com.funwithactivity.app/.features.app.MainActivity >/dev/null \
	 && echo "==> launched"

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
