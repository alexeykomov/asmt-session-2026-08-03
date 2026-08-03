# Stage 1: build the web-client bundle.
#
# Java lives ONLY here. web-client/scripts/compile-soy.js (Soy -> JS, via
# the closure-templates jar) and scripts/compile.js (google-closure-compiler,
# which itself shells out to a compiler.jar) both need a JRE at build time.
# Neither web-proxy nor the runtime image below touch Java at all — the
# output of this stage is plain static files (public/index.html,
# public/main.min.js).
FROM node:18-alpine AS client-builder

RUN apk add --no-cache openjdk17-jre-headless

WORKDIR /client

COPY web-client/package*.json ./
RUN npm ci

COPY ui-soy/ /ui-soy/
COPY web-client/scripts/ ./scripts/
COPY web-client/src/ ./src/
COPY web-client/third_party/ ./third_party/
# css/ is not optional either: npm run build now runs scripts/build-css.js
# first, which reads css/main.css unconditionally. Same failure mode as the
# api/dto/ omission below: builds fine locally (the file is already on
# disk) and fails only in a clean container, with an uncaught ENOENT.
COPY web-client/css/ ./css/
COPY web-client/public/ ./public/
# api/dto/ sits at the repo root, a sibling of web-client/ (not inside it) —
# scripts/compile.js resolves it as '../api/dto/**.js' relative to its own
# ROOT (/client here), which means /api/dto in this container, not
# /client/api/dto. Same failure mode as the css/ omission above: builds
# fine on a dev machine where the repo root already has api/dto/ on disk,
# and fails only in a clean container.
COPY api/dto/ /api/dto/

RUN npm run build

# Stage 2: assemble web-proxy + its static assets.
FROM node:18-alpine AS builder

WORKDIR /app

# Build context is repo root
COPY web-proxy/package*.json ./
RUN npm ci

COPY web-proxy/src/ ./web-proxy/src/
COPY api/proto/ ./api/proto/
COPY web-client/css/ ./web-client/css/
COPY --from=client-builder /client/public/ ./web-client/public/

# Stage 3: runtime — Node only. No Java, no ui-soy: web-client is already
# built to static files by the time this stage starts.
FROM node:18-alpine

WORKDIR /app

# Express's default error handler includes stack traces in responses unless
# NODE_ENV=production. Set it here (belt) as well as in both deploy specs
# (suspenders) — a malformed-JSON request must never leak internals.
ENV NODE_ENV=production

COPY web-proxy/package*.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/web-proxy/src/ ./web-proxy/src/
COPY --from=builder /app/api/ ./api/
COPY --from=builder /app/web-client/css/ ./web-client/css/
COPY --from=builder /app/web-client/public/ ./web-client/public/

EXPOSE 3000

# No SSR/Soy compile at startup — the server binds immediately.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "web-proxy/src/server.js"]
