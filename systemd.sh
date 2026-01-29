#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="/etc/systemd/system"
BIN_DIR="/usr/local/bin"

SERVICE="tls-renew.service"
TIMER="tls-renew.timer"
RENEW_SCRIPT="renew-tls.sh"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

install_units() {
    echo "Installing systemd TLS renew units"

    sudo install -m 755 "$PROJECT_DIR/renew.sh" "$BIN_DIR/$RENEW_SCRIPT"

    sudo install -m 644 "$PROJECT_DIR/templates/$SERVICE" "$UNIT_DIR/$SERVICE"
    sudo install -m 644 "$PROJECT_DIR/templates/$TIMER" "$UNIT_DIR/$TIMER"

    sudo systemctl daemon-reload
    sudo systemctl enable --now "$TIMER"

    echo "Systemd TLS renew timer enabled:"
    systemctl list-timers --all | grep tls-renew || true
}

remove_units() {
    echo "Removind systemd TLS renew units"

    sudo systemctl disable --now "$TIMER" || true

    sudo rm -f \
        "$UNIT_DIR/$SERVICE" \
        "$UNIT_DIR/$TIMER" \
        "$BIN_DIR/$RENEW_SCRIPT"

    sudo systemctl daemon-reload

    echo "Systemd TLS renew removed"
}

status_units() {
    systemctl status "$TIMER" --no-pager || true
}

case "${1:-}" in
    install)
        install_units
        ;;
    remove)
        remove_units
        ;;
    status)
        status_units
        ;;
    *)
        echo "Usage: $0 {install|remove|status}"
        exit 1
    ;;
esac