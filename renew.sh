#!/usr/bin/env bash
set -euo pipefail

msg() {
    echo -e "\n=== $1 ==="
}

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_MODE_FILE="/etc/tls-renew.conf"

# ================= Checks =================

if [[ ! -f "$TLS_MODE_FILE" ]]; then
    echo "ERROR: /etc/tls-renew/conf not found!"
    exit 1
fi

# shellcheck disable=SC1090
source "$TLS_MODE_FILE"

# ================= Renew =================

case "$TLS_MODE" in
    letsencrypt)
        msg "Renewing Let's Encrypt TLS certificate"

        if ! command -v certbot >/dev/null 2>&1; then
            echo "certbot is not installed"
            exit 1
        fi

        sudo certbot renew --quiet
        ;;
    *)
        echo "ERROR: Unsupported TLS_MODE: $TLS_MODE"
        exit 1
        ;;
esac