# Plantilla de hosting Odoo (producción + staging en un mismo droplet)

Plantilla genérica sacada de la puesta en marcha real de Comercial Nevada.
Sirve para levantar un cliente nuevo de Primate con: un droplet de
DigitalOcean, Odoo 19 + Enterprise, Postgres, Caddy con HTTPS automático, y un
entorno de staging aparte en el mismo servidor.

No tiene ningún dato ni contraseña de ningún cliente - todo lo específico se
completa en `.env` y en las variables que le pasás a cada script.

## Antes de arrancar: qué hace un humano y qué se puede automatizar

Los pasos que tocan **seguridad del sistema operativo o del firewall**
(usuarios sudo, SSH, `ufw`, el Cloud Firewall de DigitalOcean, resetear
 contraseñas de login) siempre los tiene que ejecutar una persona, a mano,
desde la consola del droplet - nunca un asistente/IA, aunque se le pida
explícitamente. Todo lo demás (Docker, Odoo, Postgres, Caddy, scripts de este
                               repo) sí se puede automatizar con tranquilidad.

## Paso a paso para un cliente nuevo

1. **Crear el droplet** en DigitalOcean (Ubuntu 24.04, el tamaño según la
                                            cantidad de usuarios esperada - ver notas de sizing más abajo).

2. **Hardening inicial** - conectate como `root` por SSH o por la Web Console
   de DigitalOcean y corré, vos mismo:
   ```
   bash scripts/setup-droplet.sh <usuario> <ruta_a_tu_clave_publica_ssh>
   ```
   Esto crea el usuario no-root con sudo, deshabilita login root y password
   auth por SSH, instala fail2ban + ufw (22/80/443), y Docker + Compose.

3. **Crear el Cloud Firewall de DigitalOcean** (Networking → Firewalls) para
   este droplet, permitiendo 22/80/443. **Es una capa separada del `ufw` del
   paso anterior** - las dos tienen que estar de acuerdo, si te olvidás de
   ésta el tráfico se sigue bloqueando aunque el `ufw` esté bien. Esto ya nos
   pasó una vez con Comercial Nevada, cuesta detectarlo si no lo tenés
   presente.

4. Si el droplet tiene poca RAM (menos de ~4GB), agregar un swapfile:
   ```
   fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile
   swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```

5. **Copiar este repo** a `/opt/<cliente>` en el droplet (ya conectado como el
                                                             usuario no-root creado en el paso 2).

6. **Completar `.env`**: copiar `.env.example` a `.env` y llenarlo (nombres de
                                                                       base, dominios, contraseñas de Postgres y de `admin_passwd` de cada
                                                                       entorno - usar contraseñas distintas para producción y staging).

7. **Clonar Odoo Enterprise** dentro de `./enterprise` (repo privado de Odoo
                                                           SA, necesita un Personal Access Token de GitHub de la cuenta con acceso a
                                                           la partnership de Primate). Si el cliente no va a usar Enterprise, se puede
   sacar el mount de `./enterprise` en `docker-compose.yml` y del
   `addons_path` en los `.conf.template`.

8. **Generar los config**:
   ```
   ./scripts/render-config.sh
   ```
   Esto arma `config/odoo.conf`, `config/odoo-staging.conf` y `Caddyfile` a
   partir de los `.template` + `.env`. Si todavía no hay dominio, en vez de
   esto copiá `Caddyfile.no-domain.example` a `Caddyfile` a mano y descomentá
   el puerto 8080 en `docker-compose.yml` (ver el comentario en ese archivo).

9. **Levantar los contenedores**:
   ```
   docker compose up -d db
   # esperar a que "db" esté healthy (docker compose ps)
   docker compose up -d odoo odoo-staging caddy
   ```

10. **Inicializar las bases**:
    ```
    ./scripts/init-databases.sh
    ```

11. **DNS**: crear dos registros A (uno para `PROD_DOMAIN`, otro para
                                        `STAGING_DOMAIN`) apuntando a la IP del droplet, donde sea que el cliente
    tenga su DNS. Apenas resuelvan, Caddy emite solo los certificados HTTPS
    (Let's Encrypt) para los dos - no hace falta hacer nada más para eso.

12. **Cambiar el login `admin`/contraseña por defecto** en las dos bases antes
    de considerar el entorno listo para el cliente - Odoo inicializa el
    usuario admin con una contraseña por defecto que no es apta para dejar
    expuesta públicamente.

## Uso día a día

- **Refrescar staging con una copia de producción**: `./scripts/refresh-staging.sh`
  - Pisa la base y el filestore de staging con una copia fresca de
    producción, y neutraliza la copia (desactiva mails salientes, cron jobs y
    proveedores de pago, y fija el `web.base.url` de staging) para que no
    termine mandando mails reales o cobrando de verdad con datos copiados.
- **Backups**: `./scripts/backup.sh "$PROD_DB"` (agregar a cron, ver el
  comentario dentro del script). Restaurar con `./scripts/restore.sh`.
- **Cambiar la cantidad de workers de producción** (por ejemplo si se suman
  usuarios concurrentes y empieza a sentirse lento): ajustar
  `ODOO_WORKERS_PROD` en `.env`, correr `render-config.sh` de nuevo, y
  `docker compose restart odoo`.

## Notas de sizing (referencia de Comercial Nevada)

- 1-3 usuarios concurrentes, etapa de desarrollo: droplet de 2GB RAM alcanza
  con `ODOO_WORKERS_PROD=0` + un swapfile de 2GB como colchón.
- Uso real con varios usuarios simultáneos: subir a `ODOO_WORKERS_PROD=2` (o
  más) y a un droplet con más RAM - cada worker reserva memoria fija aunque no
  haya nadie conectado en ese momento.

## Qué NO incluye esta plantilla

- Facturación electrónica / localización específica del país del cliente.
- Activación de la suscripción Enterprise (se hace desde Settings → General
  Settings → Register en Odoo, una vez que el cliente la paga).
- Subida de backups a almacenamiento externo (queda como comentario pendiente
  en `scripts/backup.sh` - agregar `s3cmd`/`rclone` contra DigitalOcean Spaces
  u otro bucket cuando haga falta).
