#!/bin/bash
# Emite el certificado real de Let's Encrypt la primera vez.
# nginx no puede arrancar con el server block 443 apuntando a un certificado que no
# existe, asi que primero se genera uno "dummy" solo para poder levantar nginx y
# servir el challenge HTTP-01 en el puerto 80; luego se reemplaza por el real.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "No existe .env - copia .env.example a .env y completa los valores primero."
  exit 1
fi
set -a
source .env
set +a

if [ -z "${DOMAIN:-}" ] || [ -z "${EMAIL:-}" ]; then
  echo "Define DOMAIN y EMAIL en .env"
  exit 1
fi

mkdir -p certbot/conf certbot/www

if [ ! -e "certbot/conf/live/$DOMAIN" ]; then
  echo "==> Creando certificado dummy para $DOMAIN..."
  mkdir -p "certbot/conf/live/$DOMAIN"
  docker compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout '/etc/letsencrypt/live/$DOMAIN/privkey.pem' \
      -out '/etc/letsencrypt/live/$DOMAIN/fullchain.pem' \
      -subj '/CN=localhost'" certbot
fi

echo "==> Arrancando nginx con el certificado dummy..."
docker compose up -d nginx

echo "==> Borrando el certificado dummy..."
docker compose run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

echo "==> Solicitando el certificado real a Let's Encrypt..."
docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --email $EMAIL -d $DOMAIN \
    --rsa-key-size 2048 --agree-tos --non-interactive" certbot

echo "==> Recargando nginx con el certificado real..."
docker compose exec nginx nginx -s reload

echo "Listo. Verifica con: curl -I https://$DOMAIN"
