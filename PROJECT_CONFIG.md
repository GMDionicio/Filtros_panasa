name: Filtros_Panasa
description: App Android de mantenimiento de filtros (Flutter) + API backend en Lenovo M73 :3010
created: 2026-10-25
workspace: /Volumes/DEV_DATA/proyectos/Filtros_Panasa
backend_host: 192.168.101.80
backend_port: 3010
api_domain: panasa.gmnodo.com
database: sqlite (archivo local en M73 y SQLite Local-First en dispositivo Android)
license_validation: una sola vez, comprobante firmado local, vigencia anual
security: middleware requireAuth, confacialidad de operarios en login, validacion estricta de variables de entorno .env en produccion
semaphore: amarillo 15d, rojo 20d (y sin registros iniciales)
version: 1.0.0
