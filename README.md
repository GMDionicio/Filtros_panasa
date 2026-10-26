# Filtros Panasa — Frontend

Aplicación Flutter para gestión de filtros de aire acondicionado de Filtros Panasa.

## Stack

- **Framework**: Flutter 3.x
- **SDK**: Dart 3.13
- **Plataforma**: Android (inicial)
- **Backend**: Express API en `192.168.101.80:3010`

## Configuración

| Parámetro | Valor |
|-----------|-------|
| Host API | `192.168.101.80` |
| Puerto | `3010` |
| Dominio | `panasa.gmnodo.com` |
| BD local | SQLite (prioridad) |

## Funcionalidades

- Visualización de rejillas (R01–R22)
- Gestión de filtros por rejilla (4 filtros cada una)
- Registro y seguimiento de eventos de mantenimiento
- Sincronización con backend Express
- Activación de licencia de dispositivo
- Gestión de empleados

## Backend

API Express + SQLite — [Código fuente](https://github.com/GMDionicio/Panasa)

## Instalación

```bash
git clone https://github.com/GMDionicio/Filtros_panasa.git
cd Filtros_panasa
flutter pub get
flutter run
```

## Backend

Incluye backend Express embebido para desarrollo local — [Código fuente](https://github.com/GMDionicio/Panasa)

## Licencia

Privado — GMDionicio
