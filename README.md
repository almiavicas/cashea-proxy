# cashea-proxy

Reverse proxy con IP estática para las solicitudes de mdticket a la API de Cashea.
Cashea exige que las solicitudes lleguen desde una IP fija; como mdticket corre en
ECS Fargate (sin IPs de salida fijas), este proxy corre en una EC2 con una Elastic IP
asociada, y Django le apunta a él en vez de directamente a `external.cashea.app`.

```
Django (ECS Fargate) → https://cashea-proxy.mdticket.com → EC2 (nginx) → https://external.cashea.app
```

## Por qué un repo aparte

Se despliega a una EC2 vía `git pull` + `docker compose`, no a ECR/ECS como
`mdticket-v2`. Es una unidad de infraestructura de un solo propósito, con su propio
ciclo de vida - no depende del pipeline de tests/deploy de Django ni lo afecta.

## Requisitos previos (una sola vez)

1. Lanzar una EC2 Ubuntu 24.04 (`t4g.nano` alcanza).
2. Asignar una **Elastic IP** y asociarla a la instancia.
3. Security Group: permitir entrante 80 y 443. SSH preferiblemente vía **SSM Session
   Manager** en vez de abrir el puerto 22.
4. Crear un registro DNS tipo A: `cashea-proxy.mdticket.com` → la Elastic IP.
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
curl -I https://cashea-proxy.mdticket.com   # sin header -> 403 (correcto, el proxy está protegido)
curl -I -H "X-Proxy-Secret: <tu PROXY_SECRET>" https://cashea-proxy.mdticket.com/orders/1
```

La renovación del certificado es automática (el contenedor `certbot` corre `certbot
renew` cada 12 horas; Let's Encrypt solo renueva de verdad cuando falta poco para
expirar).

## Configurar mdticket-v2 para usar el proxy

En el `.env`/`prod.env` de producción (y de staging si el sandbox de Cashea también
exige IP fija):

```
CASHEA_BASE_URL=https://cashea-proxy.mdticket.com
```

`accounting/payment_gateways/cashea.py::CasheaService` necesita enviar el header
`X-Proxy-Secret` con el mismo valor configurado aquí en `.env` (`PROXY_SECRET`) - sin
eso el proxy devuelve 403. Falta agregar ese header y su variable de entorno del lado
de mdticket-v2; ver el `README` de ese repo o pedirlo como tarea aparte.

## Agregar el sandbox de staging de Cashea

Si además necesitas proxear `external.staging.cashea.app`, la forma más simple es
levantar un segundo subdominio (p. ej. `cashea-proxy-staging.mdticket.com`) con su
propio `server{}` en `nginx/templates/default.conf.template` (o un segundo archivo
`.template`), y correr `init-letsencrypt.sh` de nuevo para ese dominio.

## Notas de seguridad

- El proxy exige el header `X-Proxy-Secret` en cada solicitud - sin él, cualquiera en
  internet que descubra el subdominio podría usarlo como relay hacia la API de
  Cashea. Esto no reemplaza la API key de Cashea (que sigue viajando en el header
  `Authorization` sin que el proxy la toque), es solo para que el proxy no quede
  abierto.
- Si en algún momento mdticket-v2 pasa a correr detrás de un NAT Gateway propio (IP
  de salida fija para todo, no solo Cashea), este proxy deja de ser necesario y se
  puede dar de baja la instancia.
