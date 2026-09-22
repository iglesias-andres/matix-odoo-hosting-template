#!/usr/bin/env bash
# Genera config/odoo.conf, config/odoo-staging.conf y Caddyfile a partir de los
# .template de este repo + los valores de .env. Correr de nuevo cada vez que
# cambies algo en .env o en los .template (nunca editar los archivos generados
# a mano, se pisan la próxima vez que se corra esto).
#
# Uso: ./scripts/render-config.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "No existe .env - copiá .env.example a .env y completalo primero." >&2
  exit 1
fi

if ! command -v envsubst &>/dev/null; then
  echo "Falta 'envsubst' (paquete gettext-base). Instalalo con: sudo apt-get install -y gettext-base" >&2
  exit 1
fi

set -a
source .env
set +a

envsubst < config/odoo.conf.template > config/odoo.conf
envsubst < config/odoo-staging.conf.template > config/odoo-staging.conf

if [ -n "${PROD_DOMAIN:-}" ] && [ -n "${STAGING_DOMAIN:-}" ]; then
  envsubst '${PROD_DOMAIN} ${STAGING_DOMAIN}' < Caddyfile.template > Caddyfile
  echo "Caddyfile generado con dominios: $PROD_DOMAIN / $STAGING_DOMAIN"
else
  echo "PROD_DOMAIN y/o STAGING_DOMAIN vacíos en .env - no se tocó Caddyfile."
  echo "Si todavía no tenés dominio, copiá Caddyfile.no-domain.example a Caddyfile a mano (ver README)."
fi

echo "Listo: config/odoo.conf y config/odoo-staging.conf generados."
