# Filtros Panasa — App Flutter Android & Gemelo Digital 3D

Aplicación móvil industrial en **Flutter (Android)** y servidor de respaldo **Node.js Express + SQLite** para la gestión, monitoreo y mantenimiento de los 88 filtros de aire distribuibles en las 22 rejillas de la planta industrial de **Tiroforzados Cogeneración 13.200 VAC**.

---

## 🏛️ Arquitectura "Local-First" & Respaldo en Producción

La solución está construida bajo un patrón **Local-First con Respaldo Centralizado Criptográfico**, optimizada para operar en **entornos de planta industrial con conectividad inestable o inexistente**:

1. **Fuente Única de Verdad (SSOT) en el Dispositivo Móvil**:
   - La base de datos SQLite del dispositivo (`LocalDbService`) procesa y almacena **todas las acciones de mantenimiento de forma instantánea (< 10 ms)** con cero bloqueo de interfaz.
2. **Sincronización por Lotes y Cola Offline (`pending_events`)**:
   - Si no hay señal con el servidor central, los eventos se conservan localmente. Al recuperar conectividad, la aplicación ejecuta una **sincronización en lote (*batch sync*)** contra la API del servidor.
3. **Restauración y Recuperación por Licencia (`/api/sync/restore`)**:
   - Si el técnico elimina el caché de la app, reinstala o cambia de teléfono, la app consulta el backend enviando la **licencia activa o ID de dispositivo**. El backend reescribe el snapshot completo (rejillas, filtros, empleados e historial) para restaurar la operación en segundos.
4. **Reinicio y Sembrado de Datos de Simulación (`/api/seed`)**:
   - La función "Ejecutar Seed / Reinicio" ejecuta una purga atómica y transaccional en el servidor (`filter_events`, `sync_outbox`, `filters`, `grilles`) y en el almacenamiento SQLite local del dispositivo. Todas las 22 rejillas (R01 a R22) y sus 88 filtros retornan al estado inicial urgente (30 días sin mantenimiento / **Color Rojo**).
5. **Timeouts Tolerantes a Redes Industriales (5-10s)**:
   - Configurados para evitar caídas falsas a modo offline por interferencia electromagnética o variaciones de cobertura 3G/4G/WiFi industrial.

---

## 🔒 Seguridad y Autenticación de Alto Nivel

1. **Protección de Datos e Ingreso Confidencial**:
   - Se eliminó la visualización pública de usuarios en la pantalla de acceso de operario (`OperatorLoginDialog`) para prevenir la divulgación no autorizada de nombres y códigos de nómina. El usuario debe ingresar su código directamente.
2. **Middleware `requireAuth`**:
   - Endpoints sensibles (`/api/events`, `/api/employees`, `/api/grilles`, `/api/sync`) verifican la validez de tokens de sesión activos (`Authorization: Bearer <token>`) o la existencia de licencias activas vinculadas.
3. **Validación Estricta de Entorno en Producción (`validateEnvironment`)**:
   - En `NODE_ENV=production`, el servidor aborta el inicio inmediatamente si `LICENSE_SECRET_KEY` o `ADMIN_PIN` mantienen valores predeterminados o vacíos en el archivo `.env`.
4. **Política CORS Restringida**:
   - Restringido en producción a los dominios autorizados (`https://panasa.gmnodo.com` y subdominios de `gmnodo.com`), permitiendo conexiones nativas sin encabezado `Origin` para apps móviles Android.
5. **Limitación de Tasa y Reverse Proxy (`trust proxy`)**:
   - `Helmet` y `express-rate-limit` con `app.set('trust proxy', 1)` para capturar la IP real del cliente detrás de Nginx y mitigar ataques de fuerza bruta (máximo 30 intentos / 15 min en endpoints administrativos).

---

## 🛠️ Stack Tecnológico

- **Frontend Móvil & Web**: Flutter 3.47 / Dart 3.13 / BLoC (`flutter_bloc`) / Web (HTML5/Canvas)
- **Base de Datos Local Móvil & Web**: SQLite (`sqflite` en Android/iOS) + `SharedPreferences` (en Web) mediante `LocalDbService`
- **Backend Servidor**: Node.js 18+ / Express / SQLite (`backend/server.js`)
- **Seguridad Backend**: Bcrypt, Helmet, Express Rate Limit, HMAC-SHA256, CORS
- **Gestor de Procesos & Contenedores**: PM2 / Docker / Docker Compose / Nginx Reverse Proxy
- **Dominio de Producción**: `https://panasa.gmnodo.com` (Puerto interno `3010`)

---

## 📐 Estructura de Rejillas y Planta Física

Las **22 rejillas (R01 a R22)** y sus **88 filtros** corresponden a la fachada física dividida en 3 bloques y 2 niveles de altura:

- ◀️ **Bloque MG-01 (Izquierdo)**: 8 rejillas
  - Fila Superior: R01, R02, R03, R04
  - Fila Inferior: R05, R06, R07, R08
- ⏺️ **Bloque MG-02 (Centro)**: 6 rejillas
  - Fila Superior: R09, R10, R11
  - Fila Inferior: R12, R13, R14
- ▶️ **Bloque MG-03 (Derecho)**: 8 rejillas
  - Fila Superior: R15, R16, R17, R18
  - Fila Inferior: R19, R20, R21, R22

Cada rejilla contiene **4 filtros** distribuidos físicamente en matriz 2x2:
`1-arriba-izquierda`, `2-arriba-derecha`, `3-abajo-derecha`, `4-abajo-izquierda`.

---

## ✨ Funcionalidades Principales

1. **Gemelo Digital 3D Fotorrealista (`lib/interfaz.dart`)**:
   - Renderizado dinámico 3D de la fachada industrial con balizas LED e indicadores de estado en vivo.
   - Control de órbita, zoom y selección táctil directa de rejillas.
2. **Elevación 2D por Bloques (`lib/screens/dashboard_screen.dart`)**:
   - Navegación por bloques MG-01, MG-02 y MG-03 de alto contraste para visibilidad bajo luz solar directa.
3. **Semaforización Automática de Mantenimiento**:
   - 🟢 **Verde**: Al día (<15 días desde el último reemplazo).
   - 🟡 **Amarillo**: Atención preventiva necesaria (≥15 días).
   - 🔴 **Rojo**: Mantenimiento urgente (≥20 días o sin registro).
4. **Activación de Licencia y Onboarding de Planta**:
   - **Estado 1 (Activación)**: Exige Clave de Licencia y PIN Admin al ingresar desde nuevos navegadores o dispositivos.
   - **Estado 2 (Configuración Inicial)**: Si la base de datos no tiene personal registrado, el Asistente de Configuración inicializa automáticamente el catálogo de rejillas/filtros y registra al primer operario.
   - **Estado 3 (Operación Diaria)**: Autenticación por Código de Nómina para los técnicos con sesión activa por dispositivo.

---

## 📂 Estructura Completa del Proyecto

```
Filtros_panasa/
├── backend/                        # API REST Express + SQLite (Servidor de Respaldo)
│   ├── server.js                   # Servidor de Producción (Seguridad, WAL, Transacciones, Endpoints)
│   ├── package.json                # Dependencias (Express, Helmet, Bcrypt, Rate-Limit, SQLite3)
│   ├── .env                        # Variables de Entorno de Producción
│   ├── .env.example                # Plantilla de Entorno
│   ├── ecosystem.config.js         # Configuración para PM2 Process Manager
│   ├── Dockerfile                  # Imagen Docker Multi-stage
│   ├── docker-compose.yml          # Despliegue orquestado con Docker
│   ├── DEPLOYMENT.md               # Manual detallado de despliegue en servidor VPS/Nginx
│   └── filtros_panasa.db           # Base de Datos SQLite Servidor
├── lib/                            # Aplicación Móvil Flutter
│   ├── main.dart                   # Punto de entrada y proveedor de BLoC
│   ├── interfaz.dart               # Gemelo Digital 3D en CustomPainter
│   ├── blocs/
│   │   └── grille_cubit.dart       # Gestión de Estado Reactivo de Rejillas
│   ├── models/
│   │   └── models.dart             # Clases de Dominio (Grille, FilterItem, Employee, FilterEvent)
│   ├── services/
│   │   ├── api_service.dart        # Cliente HTTP con soporte de restauración y timeouts
│   │   └── local_db_service.dart   # Persistencia SQLite Local (Local-First SSOT)
│   ├── screens/
│   │   ├── dashboard_screen.dart   # Dashboard 2D Fachada por Bloques
│   │   ├── grille_detail_screen.dart # Detalle Rejilla 2x2
│   │   ├── maintenance_dialog.dart # Diálogo de Registro de Mantenimiento
│   │   ├── employees_screen.dart   # Registro y Gestión de Personal de Nómina
│   │   └── settings_screen.dart    # Configuración de Servidor, Licencia y Resiembra
│   └── widgets/
│       ├── admin_auth_dialog.dart        # Diálogo de Autenticación de Administrador (PIN Admin)
│       ├── initial_setup_dialog.dart     # Asistente de Configuración Inicial (Primer Uso)
│       ├── operator_login_dialog.dart    # Diálogo de Autenticación de Operarios (Código de Nómina Confidencial)
│       ├── product_activation_dialog.dart# Diálogo de Activación de Producto (Licencia + PIN)
│       └── app_drawer.dart               # Menú Lateral de Navegación con Sesión Activa
└── pubspec.yaml                    # Dependencias Flutter
```

---

## 🚀 Despliegue Rápido y Compilación

### Compilación y Ejecución de la App Flutter (Android & Web)

#### Ejecutar en Web (Navegador):
```bash
flutter run -d chrome --web-port 8080
```

#### Compilar Build Web de Producción:
```bash
flutter build web --release
```

#### Compilar APK Android de Producción:
```bash
flutter build apk --release
```

---

### Despliegue Rápido del Backend (Node.js)

#### Con PM2 (Recomendado):
```bash
cd backend
npm ci --only=production
cp .env.example .env
# Configurar LICENSE_SECRET_KEY y ADMIN_PIN en .env
pm2 start ecosystem.config.js --env production
pm2 save
```

#### Con Docker Compose:
```bash
cd backend
docker-compose up -d --build
```

---

## 📄 Licencia y Derechos
Propiedad Privada — **GMDionicio / Filtros Panasa** (Todos los derechos reservados).
