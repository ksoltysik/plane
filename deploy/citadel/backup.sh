#!/usr/bin/env bash
# Plane CE backup — Postgres dump + MinIO uploads. Run before every upgrade
# (Plane has a documented history of migration breakage) and on a daily timer.
#
# Restore: see deploy/citadel/README.md. Keeps the last RETAIN backups.
set -euo pipefail

COMPOSE_DIR=${COMPOSE_DIR:-/srv/plane}
BACKUP_DIR=${BACKUP_DIR:-/srv/plane/backups}
RETAIN=${RETAIN:-14}
STAMP=$(date -u +%Y%m%d-%H%M%S)

cd "$COMPOSE_DIR"
mkdir -p "$BACKUP_DIR"

# Postgres: pg_dump inside the db container, gzip on the host.
docker compose exec -T plane-db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
    | gzip > "$BACKUP_DIR/db-$STAMP.sql.gz"

# MinIO uploads: tar the volume contents from inside the container.
docker compose exec -T plane-minio sh -c 'cd /export && tar czf - .' \
    > "$BACKUP_DIR/uploads-$STAMP.tar.gz"

# Retention — delete all but the newest $RETAIN of each kind.
ls -1t "$BACKUP_DIR"/db-*.sql.gz      2>/dev/null | tail -n +$((RETAIN + 1)) | xargs -r rm -f
ls -1t "$BACKUP_DIR"/uploads-*.tar.gz 2>/dev/null | tail -n +$((RETAIN + 1)) | xargs -r rm -f

echo "backup ok: db-$STAMP.sql.gz ($(du -h "$BACKUP_DIR/db-$STAMP.sql.gz" | cut -f1)), uploads-$STAMP.tar.gz ($(du -h "$BACKUP_DIR/uploads-$STAMP.tar.gz" | cut -f1))"
