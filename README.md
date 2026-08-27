# cashea-proxy

Reverse proxy con IP estática para las solicitudes de tu backend a la API de Cashea.
Cashea exige que las solicitudes lleguen desde una IP fija; si tu backend corre en
infraestructura sin IP de salida fija (por ejemplo, contenedores en ECS Fargate, Cloud
Run, etc.), este proxy corre en una EC2 con una Elastic IP asociada, y tu app le apunta
a él en vez de directamente a `external.cashea.app`.

```
Tu backend → https://cashea-proxy.example.com → EC2 (nginx) → https://external.cashea.app
```

## Requisitos previos (una sola vez)

1. Lanzar una EC2 Ubuntu 24.04 (`t4g.nano` alcanza).
2. Asignar una **Elastic IP** y asociarla a la instancia.
3. Security Group: permitir entrante 80 y 443. SSH preferiblemente vía **SSM Session
   Manager** en vez de abrir el puerto 22.
4. Crear un registro DNS tipo A: `cashea-proxy.example.com` → la Elastic IP.
5. Darle esta IP a Cashea para que la agreguen a su whitelist.

## Setup en la instancia

```bash
git clone <url-de-este-repo> cashea-proxy
cd cashea-proxy
sudo scripts/bootstrap-ec2.sh   # instala Docker, ufw, unattended-upgrades
# cerrar sesión y volver a entrar (para que el usuario quede en el grupo docker)

cp .env.example .env
nano .env   # completar DOMAIN, UPSTREAM_HOST, PROXY_SECRET (openssl rand -hex 32), EMAIL

scripts/init-letsencrypt.sh   # emite el certificado real de Let's Encrypt y arranca nginx
```

Verificar:
```bash
curl -I https://cashea-proxy.example.com   # sin header -> 403 (correcto, el proxy está protegido)
curl -I -H "X-Proxy-Secret: <tu PROXY_SECRET>" https://cashea-proxy.example.com/orders/1
```

La renovación del certificado es automática (el contenedor `certbot` corre `certbot
renew` cada 12 horas; Let's Encrypt solo renueva de verdad cuando falta poco para
expirar).

## Configurar tu backend para usar el proxy

En la configuración de producción de tu app (y de staging si el sandbox de Cashea
también exige IP fija), apunta la URL base de la API de Cashea a este proxy en vez del
dominio real, por ejemplo vía una variable de entorno:

```
CASHEA_BASE_URL=https://cashea-proxy.example.com
```

Tu cliente HTTP hacia Cashea necesita enviar el header `X-Proxy-Secret` con el mismo
valor configurado aquí en `.env` (`PROXY_SECRET`) - sin eso el proxy devuelve 403.

## Agregar el sandbox de staging de Cashea

Si además necesitas proxear `external.staging.cashea.app`, la forma más simple es
levantar un segundo subdominio (p. ej. `cashea-proxy-staging.example.com`) con su
propio `server{}` en `nginx/templates/default.conf.template` (o un segundo archivo
`.template`), y correr `init-letsencrypt.sh` de nuevo para ese dominio.

## Notas de seguridad

- El proxy exige el header `X-Proxy-Secret` en cada solicitud - sin él, cualquiera en
  internet que descubra el subdominio podría usarlo como relay hacia la API de
  Cashea. Esto no reemplaza la API key de Cashea (que sigue viajando en el header
  `Authorization` sin que el proxy la toque), es solo para que el proxy no quede
  abierto.
- Si en algún momento tu backend pasa a correr detrás de un NAT Gateway propio (IP de
  salida fija para todo, no solo Cashea), este proxy deja de ser necesario y se puede
  dar de baja la instancia.
