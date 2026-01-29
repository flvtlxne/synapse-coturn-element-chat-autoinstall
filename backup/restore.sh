#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/$PROJECT_ROOT" && pwd)"

echo "This action will stop docker containers and restore data from backup."
read -rp "Continue? [y/N]: " ans
[[ "$ans" == "y" ]] || exit 1

echo "===> Available backups:"

mapfile -t BACKUPS < <(
    ls -1 "$BACKUP_ROOT/synapse"/synapse_*.tar.zst 2>/dev/null \
    | sed -E 's|.*/synapse_([0-9_-]+)\.tar\.zst|\1|' \
    | sort
)

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    echo "No backups found in $BACKUP_ROOT"
    exit 1
fi

for b in "${BACKUPS[@]}"; do
    printf "    - %s\n" "$b"
done

LATEST_BACKUP="${BACKUPS[-1]}"

echo
echo "Press Enter to use latest backup: $LATEST_BACKUP"

read -rp "Backup timestamp (YYYY-MM-DD_HH_MM): " TS
TS="${TS:-$LATEST_BACKUP}"

BACKUP_SYN="$BACKUP_ROOT/synapse/synapse_$TS.tar.zst"
BACKUP_DB="$BACKUP_ROOT/postgres/db_$TS.sql.gz"

if [[ ! -f "$BACKUP_SYN" || ! -f "$BACKUP_DB" ]]; then
    echo "Backup is incomplete for timestamp: $TS"
    exit 1
fi

echo "===> Stopping all containers..."
docker compose down

# -------------------- PostgreSQL --------------------

echo "===> Restoring PostgreSQL database..."

docker compose up -d postgres
sleep 5

docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" template1 <<EOF
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$POSTGRES_DB'
    AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS "$POSTGRES_DB";
CREATE DATABASE "$POSTGRES_DB" OWNER "$POSTGRES_USER";
EOF

echo "===> Importing database dump..." 

gunzip -c "$BACKUP_DB" \
| docker exec -i "$POSTGRES_CONTAINER" \
psql -U "$POSTGRES_USER" "$POSTGRES_DB"

# -------------------- Synapse --------------------

docker compose up -d synapse
sleep 5

docker exec "$SYNAPSE_CONTAINER" sh -c 'rm -rf /data/*'

zstd -dc "$BACKUP_SYN" \
| docker exec -i "$SYNAPSE_CONTAINER" \
tar -C /data -xf -

# -------------------- Finishing --------------------

echo "===> Starting containers..."
docker compose up -d

echo "Data restore completed!"