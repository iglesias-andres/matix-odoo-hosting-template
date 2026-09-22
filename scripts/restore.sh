#!/usr/bin/env bash
# Restaura un dump + filestore generados por backup.sh.
# USO: probar siempre primero contra un entorno de staging, nunca directo en
# producción, salvo que sea justamente una restauración de emergencia de producción.
# ./restore.sh <archivo.dump> <archivo_filestore.tar.gz> <nombre_db_destino> [servicio_odoo]
set -euo pipefail

cd "$(dirname "$0")/.."

DUMP_FILE="${1:?Uso: restore.sh <dump> <filestore.tar.gz> <db_destino> [servicio_odoo]}"
FILESTORE_FILE="${2:?Uso: restore.sh <dump> <filestore.tar.gz> <db_destino> [servicio_odoo]}"
DB_NAME="${3:?Uso: restore.sh <dump> <filestore.tar.gz> <db_destino> [servicio_odoo]}"
SERVICE="${4:-odoo-staging}"   # por defecto restaura contra staging, no producción

source .env

echo "== Creando base '$DB_NAME' vacía =="
docker compose exec -T db createdb -U "$POSTGRES_USER" "$DB_NAME"

echo "== Restaurando dump =="
docker compose exec -T db pg_restore -U "$POSTGRES_USER" -d "$DB_NAME" --no-owner < "$DUMP_FILE"

echo "== Restaurando filestore =="
docker compose exec -T "$SERVICE" mkdir -p /var/lib/odoo/filestore/"$DB_NAME"
docker compose exec -T "$SERVICE" tar -xzf - -C /var/lib/odoo/filestore < "$FILESTORE_FILE"

echo "== Listo. Reiniciar el contenedor '$SERVICE' y entrar a la base '$DB_NAME'. =="
echo "   docker compose restart $SERVICE"
