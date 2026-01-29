#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd )"

if [ -n "${SUDO_USER:-}" ]; then
    BACKUP_USER="$SUDO_USER"
else
    BACKUP_USER="$(id -un)"
fi

echo "Installing Matrix backup for user: $BACKUP_USER"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/env.tpl" "$SCRIPT_DIR/.env"
    echo "backup/.env created from env.tpl"
else
    echo "backup/.env already exists"
fi

sudo mkdir -p /opt/backups/matrix
sudo chown -R "$BACKUP_USER:docker" /opt/backups/matrix
sudo chmod 750 /opt/backups/matrix

sed \
    -e "s|{{ BACKUP_USER }}|$BACKUP_USER|g" \
    -e "s|{{ PROJECT_ROOT }}|$PROJECT_ROOT|g" \
    "$SCRIPT_DIR/systemd/matrix.backup.service.tpl" \
    | sudo tee /etc/systemd/system/matrix.backup.service > /dev/null

sudo cp "$SCRIPT_DIR/systemd/matrix.backup.timer" /etc/systemd/system

sudo systemctl daemon-reload
sudo systemctl enable --now matrix.backup.timer

echo "Matrix backup installed and enabled."
echo "Run service once manually with:"
echo "  $PROJECT_ROOT/backup/backup.sh"