#!/usr/bin/env bash
# refresh-staging.sh - pisa la base de staging con una copia fresca de producción
# (datos + filestore), y neutraliza la copia (sin mails salientes, cron ni pagos
# reales). Pensado para correr manualmente cuando haga falta un staging al día.
#
# Uso: ./scripts/refresh-staging.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

DUMP_FILE="/tmp/${PROD_DB}_refresh_$(date +%Y%m%d_%H%M%S).dump"

echo "=== Refresh de staging desde producción - $(date) ==="

echo "[1/7] Deteniendo odoo-staging..."
docker compose stop odoo-staging

echo "[2/7] Dump de producción ($PROD_DB)..."
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -Fc "$PROD_DB" > "$DUMP_FILE"

echo "[3/7] Recreando base $STAGING_DB..."
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$STAGING_DB';" >/dev/null 2>&1 || true
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $STAGING_DB;"
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $STAGING_DB OWNER \"$POSTGRES_USER\";"

echo "[4/7] Restaurando dump en $STAGING_DB..."
cat "$DUMP_FILE" | docker compose exec -T db pg_restore -U "$POSTGRES_USER" -d "$STAGING_DB" --no-owner --no-privileges
rm -f "$DUMP_FILE"

echo "[5/7] Copiando filestore de producción a staging..."
docker compose exec -T odoo sh -c "mkdir -p /var/lib/odoo/filestore/$PROD_DB && tar -cf - -C /var/lib/odoo/filestore $PROD_DB" | \
  docker compose exec -T odoo-staging sh -c "mkdir -p /var/lib/odoo/filestore && rm -rf /var/lib/odoo/filestore/$STAGING_DB && tar -xf - -C /var/lib/odoo/filestore && mv /var/lib/odoo/filestore/$PROD_DB /var/lib/odoo/filestore/$STAGING_DB"

echo "[6/7] Neutralizando staging (mails, cron, pagos, base_url)..."
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$STAGING_DB" -v ON_ERROR_STOP=1 <<SQL
UPDATE ir_mail_server SET active = false;
UPDATE fetchmail_server SET active = false;
UPDATE ir_cron SET active = false WHERE active = true;
UPDATE payment_provider SET state = 'disabled' WHERE state != 'disabled';
DELETE FROM ir_config_parameter WHERE key = 'web.base.url';
INSERT INTO ir_config_parameter (key, value, create_uid, create_date, write_uid, write_date)
  VALUES ('web.base.url', 'https://${STAGING_DOMAIN}', 1, now(), 1, now());
SQL

echo "[7/7] Reiniciando odoo-staging..."
docker compose start odoo-staging

echo "=== Listo. $STAGING_DB es ahora una copia de $PROD_DB al $(date). ==="
echo "Recordá: mails salientes, cron jobs y proveedores de pago quedaron desactivados en staging."
