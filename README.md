# Filtros Panasa — App Flutter Android & Gemelo Digital 3D

Aplicación móvil en **Flutter (Android)** para la gestión y seguimiento del mantenimiento de filtros de aire acondicionado en las 22 rejillas de la planta industrial de **Tiroforzados Cogeneración 13.200 VAC**.

---

## 🛠️ Stack Tecnológico

- **Frontend**: Flutter 3.47.3 / Dart 3.13
- **Plataformas**: Android (Móvil/Tablet) / Windows
- **Backend Embebido**: Node.js + Express (`backend/server.js`)
- **Base de Datos**: SQLite (`backend/filtros_panasa.db`)
- **Puerto API Local**: `3010` (Acceso Android Emulator vía `10.0.2.2:3010`)

---

## 📐 Estructura de Rejillas y Planta Física

Las **22 rejillas (R01 a R22)** corresponden exactamente a la fachada física de la planta dividida en 3 bloques y 2 niveles de altura:

- ◀️ **Bloque MG-01 (Izquierdo)**: 8 rejillas
  - Fila Superior: R01, R02, R03, R04
  - Fila Inferior: R05, R06, R07, R08
- ⏺️ **Bloque MG-02 (Centro)**: 6 rejillas
  - Fila Superior: R09, R10, R11
  - Fila Inferior: R12, R13, R14
- ▶️ **Bloque MG-03 (Derecho)**: 8 rejillas
  - Fila Superior: R15, R16, R17, R18
  - Fila Inferior: R19, R20, R21, R22

---

## ✨ Funcionalidades Principales

1. **Gemelo Digital 3D Fotorrealista (`lib/interfaz.dart`)**:
   - Proyección e interacción 3D de la fachada industrial completa.
   - Rotación/órbita panorámica y zoom.
   - Balizas LED en 3D e identificadores con semáforo SCADA en vivo.
   - Selección e inspección táctil en 3D de cualquiera de las 22 rejillas.

2. **Elevación 2D por Bloques (`lib/screens/dashboard_screen.dart`)**:
   - Vista en tiempo real por secciones físicas (MG-01, MG-02, MG-03) en filas superior e inferior.
   - Diseño optimizado y de alto contraste para lectura clara bajo luz solar en campo.
   - Adaptación inteligente a orientación Horizontal (Landscape) y Vertical (Portrait).

3. **Gestión e Inspección de Filtros (`lib/screens/grille_detail_screen.dart`)**:
   - Distribución física 2x2 de los 4 filtros por rejilla (`1-arriba-izquierda`, `2-arriba-derecha`, `3-abajo-derecha`, `4-abajo-izquierda`).
   - Cálculo automático de días transcurridos y semáforo de alerta:
     - 🟢 **Verde**: Al día (<15 días)
     - 🟡 **Amarillo**: Atención necesaria (≥15 días)
     - 🔴 **Rojo**: Mantenimiento urgente (≥20 días)

4. **Registro de Eventos de Mantenimiento (`lib/screens/maintenance_dialog.dart`)**:
   - Selección de filtros individuales o completos.
   - Asignación de técnico/empleado por código de nómina (`EMP-001`, `EMP-004`, etc.).
   - Sincronización instantánea con SQLite y actualización en vivo del modelo 3D.

5. **Servidor API Backend Embebido (`backend/`)**:
   - API Express local en el puerto `3010`.
   - Inicializador de datos de prueba (`/api/seed`) para crear las 22 rejillas y 88 filtros.

---

## 🚀 Ejecución en Desarrollo

### 1. Iniciar Backend Express (Node.js)
```bash
cd backend
npm install
npm start
```

### 2. Ejecutar la Aplicación Flutter
```bash
flutter pub get
flutter run -d emulator-5554
```

---

## 📁 Estructura del Código Source

```
Filtros_panasa/
├── backend/                  # Servidor Express + SQLite API
│   ├── server.js             # Endpoints /api/grilles, /api/events, /api/employees
│   └── package.json
├── lib/
│   ├── main.dart             # Punto de entrada principal de Flutter
│   ├── interfaz.dart         # Gemelo Digital 3D (CustomPainter)
│   ├── models/               # Modelos de datos (Grille, FilterItem, Employee)
│   ├── services/             # Servicio API HTTP (ApiService)
│   └── screens/
│       ├── dashboard_screen.dart    # Elevación 2D Fachada por Bloques
│       ├── grille_detail_screen.dart# Vista 2x2 de los 4 filtros
│       ├── maintenance_dialog.dart  # Diálogo de registro de mantenimiento
│       ├── employees_screen.dart    # Gestión de empleados y nómina
│       └── settings_screen.dart     # Configuración y estado de API
└── pubspec.yaml              # Configuración de dependencias Flutter
```

---

## 📄 Licencia

Propiedad privada — GMDionicio / Filtros Panasa
