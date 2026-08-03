#!/usr/bin/env bash
# Provision a DigitalOcean Droplet as the FunWithActivity edge.
#
# Result: nginx terminating TLS, routing gRPC to app-server over HTTP/2 and
# everything else to web-proxy over HTTP/1.1 — the topology App Platform's
# HTTP/1.1-only ingress cannot provide.
#
# Run FROM YOUR MACHINE, not on the droplet:
#     ./web-server/provision.sh <droplet-ip>
#
# Prerequisites:
#   - A droplet already created (ubuntu-24-04, s-1vcpu-1gb is enough) with
#     your SSH key attached.
#   - Go toolchain locally, to cross-compile the server binary.
#
# TLS without buying a domain: sslip.io resolves <ip>.sslip.io to <ip>, and
# Let's Encrypt will issue for it. That gives a genuine, publicly-trusted
# certificate — which is what iOS App Transport Security and Android's
# default network security config require. A self-signed cert would force
# per-app exceptions in both clients and is not worth the trouble.

set -euo pipefail

IP="${1:?usage: provision.sh <droplet-ip>}"
HOST="${IP}.sslip.io"
REMOTE="root@${IP}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Vendor endpoints and the shared gRPC secret come from the repo-root .env
# (copy .env.example to .env and fill in real values first — see
# .env.example for where to get them). Already-exported variables always
# win, so `PROVIDER1_URL=... ./provision.sh <ip>` still overrides — this
# only fills in values that aren't already set in the environment.
if [[ -f "${REPO_ROOT}/.env" ]]; then
  while IFS='=' read -r _key _value; do
    [[ -z "${_key}" || "${_key}" == \#* ]] && continue
    if [[ -z "${!_key:-}" ]]; then
      export "${_key}=${_value}"
    fi
  done < <(grep -v '^\s*#' "${REPO_ROOT}/.env" | grep -v '^\s*$')
else
  echo "==> No .env found at ${REPO_ROOT}/.env — copy .env.example to .env and fill in real values, or export PROVIDER1_URL/PROVIDER2_URL/INTERNAL_GRPC_TOKEN yourself." >&2
fi

PROVIDER1_URL="${PROVIDER1_URL:?PROVIDER1_URL is unset — set it in .env or export it before running this script}"
PROVIDER2_URL="${PROVIDER2_URL:?PROVIDER2_URL is unset — set it in .env or export it before running this script}"
INTERNAL_GRPC_TOKEN="${INTERNAL_GRPC_TOKEN:-$(openssl rand -hex 24)}"

echo "==> Edge host will be: ${HOST}"

echo "==> Cross-compiling app-server for linux/amd64"
(cd "${REPO_ROOT}/app-server" && \
   CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /tmp/fwa-app-server ./cmd/server)

echo "==> Installing packages on the droplet"
ssh -o StrictHostKeyChecking=accept-new "${REMOTE}" bash -s <<'REMOTE_SETUP'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx
mkdir -p /var/www/certbot /opt/funwithactivity
systemctl stop nginx || true
REMOTE_SETUP

echo "==> Uploading server binary"
# Stop the service first: on a re-run the old binary is still executing and
# scp fails with "Text file busy". This script must be safely re-runnable.
ssh "${REMOTE}" "systemctl stop fwa-app-server 2>/dev/null || true"
scp -q /tmp/fwa-app-server "${REMOTE}:/opt/funwithactivity/app-server"
ssh "${REMOTE}" "chmod +x /opt/funwithactivity/app-server"

echo "==> Installing systemd unit"
ssh "${REMOTE}" bash -s <<REMOTE_UNIT
set -euo pipefail
cat > /etc/systemd/system/fwa-app-server.service <<UNIT
[Unit]
Description=FunWithActivity app-server (gRPC)
After=network.target

[Service]
Type=simple
ExecStart=/opt/funwithactivity/app-server
Restart=always
RestartSec=3
# Bound to loopback only: nginx is the sole path in from the internet.
Environment=GRPC_PORT=50051
Environment=HEALTH_HTTP_PORT=50052
Environment=PROVIDER_TIMEOUT_MS=2000
# Real vendor endpoints (the presale team supplied them). To fall back to
# canned data if the vendors are down mid-session, swap these two lines for
# Environment=USE_STUB_PROVIDERS=true — the stubs name themselves
# "-stub" and the UI shows that in its Source column, so fabricated data
# can never be mistaken on screen for the customer's real vendors.
Environment=PROVIDER1_URL=${PROVIDER1_URL}
Environment=PROVIDER2_URL=${PROVIDER2_URL}
# Shared secret for the gRPC surface. app-server now FAILS CLOSED without
# this (see CR-009): with no token and no ALLOW_INSECURE_GRPC opt-out it
# rejects every non-health RPC. Both mobile clients send it as an
# "authorization: Bearer <token>" header.
#
# Do NOT use backticks anywhere in this heredoc. It is unquoted (so that
# ${PROVIDER1_URL} and friends expand), which also means the shell treats
# backticks as command substitution and tries to EXECUTE their contents.
# A backticked comment here previously produced a "syntax error near
# unexpected token" mid-provision, while the script carried on and still
# reported success.
Environment=INTERNAL_GRPC_TOKEN=${INTERNAL_GRPC_TOKEN}

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now fwa-app-server
sleep 2
systemctl is-active fwa-app-server
REMOTE_UNIT

echo "==> Obtaining a Let's Encrypt certificate for ${HOST}"
ssh "${REMOTE}" bash -s <<REMOTE_CERT
set -euo pipefail
# Standalone mode: nginx is stopped, so certbot can bind :80 itself.
certbot certonly --standalone --non-interactive --agree-tos \
  --register-unsafely-without-email -d "${HOST}"
REMOTE_CERT

echo "==> Installing nginx config"
sed "s/__HOST__/${HOST}/g" "${REPO_ROOT}/web-server/nginx-grpc.conf" > /tmp/fwa-nginx.conf
scp -q /tmp/fwa-nginx.conf "${REMOTE}:/etc/nginx/sites-available/funwithactivity"
ssh "${REMOTE}" bash -s <<'REMOTE_NGINX'
set -euo pipefail
ln -sf /etc/nginx/sites-available/funwithactivity /etc/nginx/sites-enabled/funwithactivity
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
systemctl is-active nginx
REMOTE_NGINX

echo
echo "==> Done. Verify from here:"
echo "    grpcurl ${HOST}:443 list"
echo "    grpcurl -d '{\"measurements\":{\"heightCm\":184,\"weightKg\":84}}' \\"
echo "      ${HOST}:443 funwithactivity.recommendations.v1.RecommendationsService/GetRecommendations"
echo
echo "==> Point the mobile clients at: ${HOST}:443  (TLS, not plaintext)"
