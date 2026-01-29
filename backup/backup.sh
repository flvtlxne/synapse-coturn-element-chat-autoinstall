#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/$PROJECT_ROOT" && pwd)"
DATE="$(date +%F_%H_%M)"

mkdir -p \
    "$BACKUP_ROOT/postgres" \
    "$BACKUP_ROOT/synapse"  \
    "$BACKUP_ROOT/element"

echo "===> PostgreSQL backup..."

docker exec "$POSTGRES_CONTAINER" \
    pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
    | gzip > "$BACKUP_ROOT/postgres/db_$DATE.sql.gz"

echo "===> Synapse data backup..."

docker exec "$SYNAPSE_CONTAINER" \
    tar -C /data -cf - . \
| zstd -3 \
> "$BACKUP_ROOT/synapse/synapse_$DATE.tar.zst"

echo "===> Element config backup..."

tar -C "$PROJECT_ROOT" \
    -czf "$BACKUP_ROOT/element/element_$DATE.tar.gz" element/config.json

echo "===> Cleanup old backups..."

find "$BACKUP_ROOT" -type f -mtime +"$RETENTION_DAYS" -delete

echo "Backup completed successfully!"