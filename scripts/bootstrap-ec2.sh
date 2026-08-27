#!/bin/bash
# Preparacion inicial de una EC2 Ubuntu 24.04 nueva para correr este proxy.
# Ejecutar una sola vez, con sudo, recien creada la instancia.
set -euo pipefail

apt-get update
apt-get upgrade -y

# Docker + el plugin "docker compose" (v2)
curl -fsSL https://get.docker.com | sh
usermod -aG docker "${SUDO_USER:-ubuntu}"

# Parches de seguridad del sistema operativo automaticos
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# Firewall: solo SSH, HTTP (para el challenge de certbot) y HTTPS
apt-get install -y ufw
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Listo. Cierra sesion y vuelve a entrar para que el usuario quede en el grupo docker."
echo "Luego: clona este repo, cp .env.example .env, completa los valores, y corre scripts/init-letsencrypt.sh"
