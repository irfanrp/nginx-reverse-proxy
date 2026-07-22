#!/usr/bin/env bash
# Issue / renew wildcard SSL (Certbot + Cloudflare DNS-01).
# Required env: CLOUDFLARE_API_TOKEN, EMAIL (or SSL_EMAIL)
# Optional: DOMAIN (default aboutdevops.my.id)
# Run from repo root. Needs passwordless sudo.

set -euo pipefail

DOMAIN="${DOMAIN:-aboutdevops.my.id}"
EMAIL="${EMAIL:-${SSL_EMAIL:-}}"
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
: "${EMAIL:?EMAIL or SSL_EMAIL is required}"
[[ -f docker-compose.yml ]] || { echo "ERROR: docker-compose.yml not found"; exit 1; }

printf 'DOMAIN=%s\nEMAIL=%s\nCLOUDFLARE_API_TOKEN=%s\n' \
  "${DOMAIN}" "${EMAIL}" "${CLOUDFLARE_API_TOKEN}" > .env

sudo true

certbot() {
  sudo -E docker compose run --rm --no-deps --entrypoint sh certbot -c "$*"
}

write_cf_ini='umask 077; printf "dns_cloudflare_api_token = %s\n" "$CLOUDFLARE_API_TOKEN" > /etc/cloudflare.ini'

if sudo test -f "${CERT}"; then
  expiry="$(sudo openssl x509 -enddate -noout -in "${CERT}" | cut -d= -f2)"
  days=$(( ( $(date -d "${expiry}" +%s) - $(date +%s) ) / 86400 ))
  echo "Cert OK — ${days} days left (expires ${expiry})"
  [[ "${days}" -ge 30 ]] && { echo "Skip renew"; exit 0; }

  echo "Renewing..."
  certbot "set -e; ${write_cf_ini}; certbot renew --dns-cloudflare --dns-cloudflare-credentials /etc/cloudflare.ini --quiet"
  echo "Renewed"
else
  echo "Issuing wildcard for ${DOMAIN}..."
  certbot "set -e; ${write_cf_ini}; certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/cloudflare.ini --non-interactive --agree-tos --email \"\$EMAIL\" -d \"\$DOMAIN\" -d \"*.\$DOMAIN\""
  echo "Issued"
fi
