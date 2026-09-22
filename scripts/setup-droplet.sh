#!/usr/bin/env bash
# Hardening inicial de un droplet Ubuntu 24.04 recién creado, antes de desplegar Odoo.
#
# IMPORTANTE: este script toca configuración de sudo/SSH/firewall del sistema.
# Correrlo siempre vos mismo, a mano, desde la consola del droplet - nunca
# pedirle a un asistente/IA que lo ejecute por vos.
#
# Uso, como root, la primera vez:
#   bash setup-droplet.sh <usuario_no_root> <ruta_clave_publica_ssh>
set -euo pipefail

NEW_USER="${1:?Uso: setup-droplet.sh <usuario> <ruta_clave_publica_ssh>}"
SSH_KEY_PATH="${2:?Uso: setup-droplet.sh <usuario> <ruta_clave_publica_ssh>}"

echo "== Actualizando el sistema =="
apt-get update && apt-get -y upgrade

echo "== Creando usuario no-root con sudo =="
if ! id "$NEW_USER" &>/dev/null; then
  adduser --disabled-password --gecos "" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
fi

mkdir -p /home/"$NEW_USER"/.ssh
cp "$SSH_KEY_PATH" /home/"$NEW_USER"/.ssh/authorized_keys
chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.ssh
chmod 700 /home/"$NEW_USER"/.ssh
chmod 600 /home/"$NEW_USER"/.ssh/authorized_keys

echo "== Deshabilitando login root por SSH y auth por password =="
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

echo "== Instalando fail2ban =="
apt-get install -y fail2ban
systemctl enable --now fail2ban

echo "== Configurando firewall interno (ufw) =="
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "== Instalando Docker + Docker Compose plugin =="
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$NEW_USER"

echo "== Listo. Reconectate como $NEW_USER (no root) para seguir con el despliegue. =="
echo "   ssh $NEW_USER@<ip-del-droplet>"
echo
echo "No te olvides (fuera de este script, manualmente):"
echo "  1) Crear un Cloud Firewall en DigitalOcean para este droplet (Networking > Firewalls)"
echo "     permitiendo 22/80/443 - es una capa SEPARADA del ufw de acá arriba, las dos"
echo "     tienen que estar de acuerdo o el tráfico se bloquea igual."
echo "  2) Si el droplet tiene poca RAM (menos de ~4GB), agregar un swapfile de 2GB:"
echo "       fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile"
echo "       swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab"
