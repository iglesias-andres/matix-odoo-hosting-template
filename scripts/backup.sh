#!/usr/bin/env bash
# Backup de la base de datos y el filestore de Odoo (producción o staging).
# Pensado para correr vía cron desde este directorio.
# Ejemplo de crontab (usuario deploy), backup diario de producción a las 3am:
#   0 3 * * * cd /opt/<cliente> && ./scripts/backup.sh "$PROD_DB" >> /var/log/odoo-backup.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."
source .env

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"

DB_NAME="${1:?Uso: backup.sh <nombre_de_base> (ej: \$PROD_DB o \$STAGING_DB)}"
SERVICE="${2:-odoo}"   # contenedor de Odoo del que sacar el filestore: odoo u odoo-staging

echo "[$(date)] Dump de la base '$DB_NAME'..."
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -F c "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"

echo "[$(date)] Comprimiendo filestore..."
docker compose exec -T "$SERVICE" tar -czf - -C /var/lib/odoo/filestore "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_filestore_${TIMESTAMP}.tar.gz" 2>/dev/null || \
  echo "  (sin filestore todavía para $DB_NAME, se omite)"

echo "[$(date)] Eliminando backups locales de más de 7 días..."
find "$BACKUP_DIR" -type f -mtime +7 -delete

# Pendiente (opcional): subir los backups a almacenamiento externo (DigitalOcean
# Spaces con s3cmd/rclone) para no depender solo del disco del mismo droplet.

echo "[$(date)] Backup completo: $BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"
