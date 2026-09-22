#!/usr/bin/env bash
# Crea e inicializa las bases de producción y staging (módulo base, sin datos
# demo). Correr una sola vez, después de "docker compose up -d db odoo odoo-staging"
# y de haber generado los config con render-config.sh.
#
# Uso: ./scripts/init-databases.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

echo "[1/2] Inicializando base de producción: $PROD_DB"
docker compose exec -T odoo sh -c 'odoo --stop-after-init --no-http -d "$1" -i base --without-demo=all --db_host=db --db_user="$USER" --db_password="$PASSWORD"' _ "$PROD_DB"

echo "[2/2] Inicializando base de staging: $STAGING_DB"
docker compose exec -T odoo-staging sh -c 'odoo --stop-after-init --no-http -d "$1" -i base --without-demo=all --db_host=db --db_user="$USER" --db_password="$PASSWORD"' _ "$STAGING_DB"

docker compose restart odoo odoo-staging

echo "Listo. Verificar:"
echo "  https://${PROD_DOMAIN:-<IP-del-droplet>}"
echo "  https://${STAGING_DOMAIN:-<IP-del-droplet>:8080}"
echo
echo "Recordá cambiar el login/contraseña de admin por defecto en las dos bases"
echo "antes de dejarlas accesibles públicamente."
