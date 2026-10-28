# Guía de Despliegue en Producción — Filtros_Panasa Backend

Este documento detalla los pasos para desplegar el backend en el servidor de producción con dominio `panasa.gmnodo.com` e HTTPS SSL activo.

---

## Requisitos de Seguridad Previos

En entorno de producción (`NODE_ENV=production`), el servidor ejecuta una validación de seguridad automática al iniciar (`validateEnvironment()`).

Es obligatorio definir en el archivo `.env`:
- `LICENSE_SECRET_KEY`: Clave secreta única y segura para la firma criptográfica de licencias.
- `ADMIN_PIN` o `ADMIN_PIN_HASH`: PIN o Hash Bcrypt del administrador.

---

## Opción 1: Despliegue Directo con PM2 y Nginx (Recomendado)

### 1. Clonar o copiar el repositorio en el servidor
```bash
mkdir -p /srv/glowmy/api-filtros-panasa
cd /srv/glowmy/api-filtros-panasa
# Copiar los archivos de backend/
```

### 2. Instalar dependencias
```bash
npm ci --only=production
```

### 3. Configurar variables de entorno `.env`
```bash
cp .env.example .env
nano .env
```
Asegurarse de configurar:
```env
PORT=3010
NODE_ENV=production
DB_PATH=/srv/glowmy/api-filtros-panasa/filtros_panasa.db
CORS_ORIGIN=https://panasa.gmnodo.com

# Seguridad
ADMIN_PIN=1513
LICENSE_SECRET_KEY=clave-secreta-larga-y-segura-panasa-prod-2026
```

### 4. Iniciar servicio con PM2
```bash
npm install -g pm2
pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
```

---

## Opción 2: Despliegue con Docker Compose

```bash
docker-compose up -d --build
```

---

## Configuración de Nginx Reverse Proxy + SSL Let's Encrypt

En `/etc/nginx/sites-available/panasa.gmnodo.com`:

```nginx
server {
    server_name panasa.gmnodo.com;

    location / {
        proxy_pass http://127.0.0.1:3010;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Activar y solicitar certificado SSL gratuito:
```bash
ln -s /etc/nginx/sites-available/panasa.gmnodo.com /etc/nginx/sites-enabled/
certbot --nginx -d panasa.gmnodo.com
systemctl reload nginx
```

---

## Verificación de Salud del Servidor
```bash
curl -i https://panasa.gmnodo.com/health
```
Debe retornar:
```json
{
  "status": "ok",
  "service": "filtros-panasa-api",
  "env": "production",
  "port": 3010,
  "db": "connected"
}
```

---

## Endpoint de Reinicio / Seed de Pruebas
```bash
curl -X POST https://panasa.gmnodo.com/api/seed
```
Respuesta esperada:
```json
{
  "success": true,
  "grilles": 22,
  "filters": 88,
  "message": "Seed y reinicio de estado de rejillas completado exitosamente"
}
```
