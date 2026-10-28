#!/usr/bin/env node
/**
 * Filtros_Panasa — API Backend para Producción
 * Puerto: 3010
 * Base de datos: SQLite (WAL Mode, Transaccional)
 * Dominio: panasa.gmnodo.com
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// Cargar variables de entorno desde .env
try { require('dotenv').config(); } catch (e) {}

const app = express();
const PORT = process.env.PORT || 3010;
const NODE_ENV = process.env.NODE_ENV || 'production';
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'filtros_panasa.db');
const LICENSE_SECRET = process.env.LICENSE_SECRET_KEY || 'panasa-production-secret-key-2026';
const ADMIN_PIN_PLAIN = process.env.ADMIN_PIN || '1513';
const ADMIN_PIN_HASH = process.env.ADMIN_PIN_HASH || bcrypt.hashSync(ADMIN_PIN_PLAIN, 10);

// ==================== VALIDACIÓN DE ENTORNOS Y SEGURIDAD ====================

function validateEnvironment() {
  if (NODE_ENV === 'production') {
    const defaultSecrets = [
      'panasa-production-secret-key-2026',
      'cambiar-por-secreto-seguro-en-produccion',
      'secret',
      '123456'
    ];

    const secretKey = (process.env.LICENSE_SECRET_KEY || '').trim();
    if (!process.env.LICENSE_SECRET_KEY || defaultSecrets.includes(secretKey)) {
      console.error('❌ [ERROR DE SEGURIDAD CRÍTICO] En entorno de Producción (NODE_ENV=production), DEBES definir LICENSE_SECRET_KEY con una clave secreta segura en el archivo .env.');
      process.exit(1);
    }

    const pin = (process.env.ADMIN_PIN || '').trim();
    if (!process.env.ADMIN_PIN && !process.env.ADMIN_PIN_HASH) {
      console.error('❌ [ERROR DE SEGURIDAD CRÍTICO] En entorno de Producción (NODE_ENV=production), DEBES definir ADMIN_PIN o ADMIN_PIN_HASH en el archivo .env.');
      process.exit(1);
    }

    if (pin === '1513' && !process.env.ADMIN_PIN_HASH) {
      console.warn('⚠️ [ADVERTENCIA DE SEGURIDAD] Estás utilizando el PIN por defecto "1513" en Producción. Se recomienda cambiar ADMIN_PIN o definir ADMIN_PIN_HASH en .env.');
    }
  }
}

// ==================== MIDDLEWARES DE SEGURIDAD ====================

// Habilitar trust proxy si está detrás de Nginx / proxy inverso
app.set('trust proxy', parseInt(process.env.TRUST_PROXY || '1', 10));

app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginResourcePolicy: { policy: 'cross-origin' }
}));

// Configuración de CORS estricta en producción pero permisiva para aplicaciones móviles nativas y dominios autorizados
const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map(s => s.trim())
  : (NODE_ENV === 'production' ? ['https://panasa.gmnodo.com'] : '*');

app.use(cors({
  origin: (origin, callback) => {
    // Permitir peticiones sin encabezado Origin (dispositivos móviles Android/iOS nativos, cURL, Postman)
    if (!origin) return callback(null, true);

    if (allowedOrigins === '*' || allowedOrigins.includes('*')) {
      return callback(null, true);
    }

    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    // Permitir dominios de panasa / gmnodo en producción
    if (NODE_ENV === 'production' && /^https:\/\/(.*\.)?gmnodo\.com$/.test(origin)) {
      return callback(null, true);
    }

    return callback(new Error(`Origen ${origin} no permitido por política de CORS.`));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-ID', 'X-License-Key'],
  credentials: true
}));

app.use(express.json({ limit: '5mb' }));

// Limitador de tasa global para mitigar ataques DoS
// NOTA: Para despliegues en cluster PM2 multi-proceso de gran escala, configurar 'store' con Redis (rate-limit-redis).
// Para una sola instancia con SQLite WAL, el almacenamiento en memoria integrado es el comportamiento óptimo.
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 500, // Límite por IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Demasiadas solicitudes desde esta IP, intente más tarde.' }
});

// Limitador estricto para operaciones sensibles (autenticación, PINs y licencias)
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30, // 30 intentos por 15 min
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, authorized: false, error: 'Límite de intentos superado. Intente en 15 minutos.' }
});

app.use('/api/', globalLimiter);
app.use('/api/admin/', strictLimiter);
app.use('/api/operator/login', strictLimiter);
app.use('/api/license/activate', strictLimiter);
app.use('/api/system/setup', strictLimiter);
app.use('/api/system/reset', strictLimiter);

// Logger de solicitudes HTTP estructurado
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[HTTP] ${new Date().toISOString()} | ${req.method} ${req.originalUrl} | Status: ${res.statusCode} | ${duration}ms | IP: ${req.ip}`);
  });
  next();
});

// ==================== BASE DE DATOS SQLITE (Promisificada y Transaccional) ====================

let db;

function initDb() {
  return new Promise((resolve, reject) => {
    const dir = path.dirname(DB_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    db = new sqlite3.Database(DB_PATH, (err) => {
      if (err) return reject(err);

      // Habilitar modo WAL y claves foráneas
      db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`, (pragmaErr) => {
        if (pragmaErr) console.warn('[DB Warning] Pragma WAL:', pragmaErr.message);
        createTables()
          .then(() => resolve(db))
          .catch(reject);
      });
    });
  });
}

function dbQueryAll(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) return reject(err);
      resolve(rows || []);
    });
  });
}

function dbQueryGet(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) return reject(err);
      resolve(row || null);
    });
  });
}

function dbRun(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {
      if (err) return reject(err);
      resolve({ lastID: this.lastID, changes: this.changes });
    });
  });
}

async function dbExecTransaction(operations) {
  await dbRun('BEGIN IMMEDIATE TRANSACTION');
  try {
    const result = await operations();
    await dbRun('COMMIT');
    return result;
  } catch (err) {
    await dbRun('ROLLBACK');
    throw err;
  }
}

async function createTables() {
  const stmts = [
    `CREATE TABLE IF NOT EXISTS licenses (
      id TEXT PRIMARY KEY,
      device_id TEXT UNIQUE NOT NULL,
      license_key TEXT,
      status TEXT DEFAULT 'active',
      activated_at_ts TEXT,
      expires_at_ts TEXT,
      signature TEXT,
      public_key_hash TEXT,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      installation_id TEXT UNIQUE NOT NULL,
      name TEXT,
      last_seen_ts TEXT,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS employees (
      payroll_code TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      active INTEGER DEFAULT 1,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS grilles (
      grille_code TEXT PRIMARY KEY,
      name TEXT,
      position INTEGER,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS filters (
      id TEXT PRIMARY KEY,
      grille_code TEXT NOT NULL,
      filter_number INTEGER NOT NULL,
      position TEXT NOT NULL,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(grille_code) REFERENCES grilles(grille_code) ON DELETE CASCADE,
      UNIQUE(grille_code, filter_number),
      UNIQUE(grille_code, position)
    )`,
    `CREATE TABLE IF NOT EXISTS filter_events (
      id TEXT PRIMARY KEY,
      event_id TEXT UNIQUE NOT NULL,
      event_type TEXT DEFAULT 'filter_replacement',
      grille_code TEXT NOT NULL,
      filter_number INTEGER NOT NULL,
      payroll_code TEXT NOT NULL,
      occurred_at_ts TEXT NOT NULL,
      device_installation_id TEXT,
      server_received_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      notes TEXT,
      synced INTEGER DEFAULT 0,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(grille_code) REFERENCES grilles(grille_code)
    )`,
    `CREATE TABLE IF NOT EXISTS sync_outbox (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER DEFAULT 0,
      next_retry_at_ts TEXT,
      status TEXT DEFAULT 'pending',
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(event_id)
    )`,
    `CREATE TABLE IF NOT EXISTS sync_cursor (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS audit_events (
      id TEXT PRIMARY KEY,
      actor TEXT,
      action TEXT,
      target TEXT,
      details TEXT,
      created_at_ts TEXT DEFAULT CURRENT_TIMESTAMP
    )`,
    `CREATE TABLE IF NOT EXISTS operator_sessions (
      id TEXT PRIMARY KEY,
      payroll_code TEXT NOT NULL,
      device_id TEXT NOT NULL,
      device_name TEXT,
      token TEXT UNIQUE NOT NULL,
      active INTEGER DEFAULT 1,
      logged_in_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      last_active_at_ts TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(payroll_code) REFERENCES employees(payroll_code)
    )`
  ];

  for (const sql of stmts) {
    await dbRun(sql);
  }

  // Auto-seed de rejillas si la tabla grilles está vacía
  const grilleCount = await dbQueryGet(`SELECT COUNT(*) as count FROM grilles`);
  if (!grilleCount || grilleCount.count === 0) {
    await seedInitialData();
  }
}

function uuidv4() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return crypto.randomBytes(16).toString('hex');
}

async function seedInitialData() {
  console.log('[Database] Inicializando catálogo de 22 Rejillas y 88 Filtros...');
  const positions = ['1-arriba-izquierda', '2-arriba-derecha', '3-abajo-derecha', '4-abajo-izquierda'];

  for (let i = 1; i <= 22; i++) {
    const code = `R${String(i).padStart(2, '0')}`;
    await dbRun(
      `INSERT OR IGNORE INTO grilles (grille_code, name, position, created_at_ts) VALUES (?, ?, ?, CURRENT_TIMESTAMP)`,
      [code, `Rejilla ${code}`, i]
    );

    for (let j = 1; j <= 4; j++) {
      await dbRun(
        `INSERT OR IGNORE INTO filters (id, grille_code, filter_number, position, created_at_ts) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
        [uuidv4(), code, j, positions[j - 1]]
      );
    }
  }
  console.log('[Database] Catálogo de rejillas y filtros creado exitosamente.');
}

// ==================== WORKER DE SINCRONIZACIÓN EN SEGUNDO PLANO ====================

function initOutboxWorker() {
  const INTERVAL_MS = parseInt(process.env.SYNC_INTERVAL_MS || '15000', 10);
  const CENTRAL_URL = process.env.CENTRAL_SERVER_URL || null;

  setInterval(async () => {
    try {
      if (CENTRAL_URL) {
        await processOutboxQueue(CENTRAL_URL);
      }
    } catch (err) {
      console.error('[OutboxWorker] Error en barrido:', err.message);
    }
  }, INTERVAL_MS);

  console.log(`[OutboxWorker] Servicio de sincronización activo (Intervalo: ${INTERVAL_MS / 1000}s)`);
}

async function processOutboxQueue(centralUrl) {
  if (!centralUrl) return { processed: 0 };

  const nowIso = new Date().toISOString();
  const rows = await dbQueryAll(
    `SELECT * FROM sync_outbox
     WHERE status IN ('pending', 'retry')
       AND (next_retry_at_ts IS NULL OR next_retry_at_ts <= ?)
       AND attempts < 5
     ORDER BY created_at_ts ASC LIMIT 20`,
    [nowIso]
  );

  if (!rows || rows.length === 0) return { processed: 0 };

  let processedCount = 0;
  for (const item of rows) {
    try {
      const res = await fetch(`${centralUrl}/api/events`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: item.payload,
      });

      if (!res.ok) throw new Error(`HTTP Central ${res.status}`);

      await dbExecTransaction(async () => {
        await dbRun(
          `UPDATE sync_outbox SET status = 'synced', updated_at_ts = CURRENT_TIMESTAMP WHERE id = ?`,
          [item.id]
        );
        await dbRun(
          `UPDATE filter_events SET synced = 1 WHERE event_id = ?`,
          [item.event_id]
        );
      });

      processedCount++;
      console.log(`[OutboxWorker] Evento ${item.event_id} sincronizado con servidor central.`);
    } catch (retryErr) {
      const attempts = (item.attempts || 0) + 1;
      const nextRetry = new Date(Date.now() + Math.pow(2, attempts) * 5000).toISOString();
      const newStatus = attempts >= 5 ? 'failed' : 'retry';

      await dbRun(
        `UPDATE sync_outbox SET attempts = ?, next_retry_at_ts = ?, status = ?, updated_at_ts = CURRENT_TIMESTAMP WHERE id = ?`,
        [attempts, nextRetry, newStatus, item.id]
      );
    }
  }

  await dbRun(
    `INSERT OR REPLACE INTO sync_cursor (key, value, updated_at_ts) VALUES ('last_outbox_sweep', ?, CURRENT_TIMESTAMP)`,
    [new Date().toISOString()]
  );

  return { processed: processedCount };
}

// ==================== MIDDLEWARE DE AUTENTICACIÓN Y AUTORIZACIÓN ====================

async function requireAuth(req, res, next) {
  try {
    // 1. Verificar si viene el token de sesión en Authorization: Bearer <token>
    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7).trim();
      if (token) {
        const session = await dbQueryGet(
          `SELECT s.*, e.name FROM operator_sessions s
           LEFT JOIN employees e ON s.payroll_code = e.payroll_code
           WHERE s.token = ? AND s.active = 1`,
          [token]
        );
        if (session) {
          req.user = {
            payrollCode: session.payroll_code,
            name: session.name,
            deviceId: session.device_id,
            sessionId: session.id
          };
          // Actualizar timestamp de última actividad
          dbRun(`UPDATE operator_sessions SET last_active_at_ts = CURRENT_TIMESTAMP WHERE id = ?`, [session.id]).catch(() => {});
          return next();
        }
      }
    }

    // 2. Verificar si se envía X-Device-ID o X-License-Key válido
    const deviceId = req.headers['x-device-id'] || req.body?.deviceId || req.query?.deviceId;
    const licenseKey = req.headers['x-license-key'] || req.body?.licenseKey || req.query?.licenseKey;

    if (deviceId) {
      const lic = await dbQueryGet(`SELECT * FROM licenses WHERE device_id = ? AND status = 'active'`, [String(deviceId).trim()]);
      if (lic) {
        req.license = lic;
        return next();
      }
    }

    if (licenseKey) {
      const lic = await dbQueryGet(`SELECT * FROM licenses WHERE license_key = ? AND status = 'active'`, [String(licenseKey).trim()]);
      if (lic) {
        req.license = lic;
        return next();
      }
    }

    // 3. Verificación de Licencia Global Activa en la base de datos (para dispositivos o clientes sincronizados)
    const activeLicense = await dbQueryGet(`SELECT * FROM licenses WHERE status = 'active' ORDER BY created_at_ts DESC LIMIT 1`);
    if (activeLicense) {
      req.license = activeLicense;
      return next();
    }

    return res.status(401).json({
      success: false,
      error: 'Acceso no autorizado',
      message: 'Se requiere token de sesión activo (Authorization: Bearer <token>) o un producto con licencia activa para acceder a este recurso.'
    });
  } catch (err) {
    next(err);
  }
}

// ==================== RUTAS Y ENDPOINTS DE LA API ====================

// Health Check con verificación real de Base de Datos (Público)
app.get('/health', async (req, res) => {
  try {
    const dbTest = await dbQueryGet(`SELECT 1 as alive`);
    res.json({
      status: 'ok',
      service: 'filtros-panasa-api',
      env: NODE_ENV,
      port: PORT,
      db: dbTest && dbTest.alive === 1 ? 'connected' : 'degraded',
      timestamp: new Date().toISOString()
    });
  } catch (e) {
    res.status(500).json({ status: 'error', error: e.message });
  }
});

// ==================== ESTADO DEL SISTEMA Y CONFIGURACIÓN INICIAL ====================

app.get('/api/system/status/:deviceId', async (req, res, next) => {
  try {
    const { deviceId } = req.params;

    // 1. Verificar licencia
    let licRow = await dbQueryGet(`SELECT * FROM licenses WHERE device_id = ? AND status = 'active'`, [deviceId]);
    if (!licRow) {
      licRow = await dbQueryGet(`SELECT * FROM licenses WHERE status = 'active' ORDER BY created_at_ts DESC LIMIT 1`);
    }
    const isActivated = !!licRow;

    // 2. Verificar si existen empleados activos en la BD
    const empCount = await dbQueryGet(`SELECT COUNT(*) as count FROM employees WHERE active = 1`);
    const hasEmployees = empCount && empCount.count > 0;

    // 3. Verificar si existen rejillas
    const grCount = await dbQueryGet(`SELECT COUNT(*) as count FROM grilles`);
    const hasGrilles = grCount && grCount.count > 0;

    res.json({
      success: true,
      deviceId,
      isActivated,
      licenseKey: licRow ? (licRow.license_key || 'PAN-2026-PANASA-PROD') : null,
      hasEmployees,
      hasGrilles
    });
  } catch (err) {
    next(err);
  }
});

app.post('/api/system/setup', async (req, res, next) => {
  try {
    const { adminPin, initialEmployeeCode, initialEmployeeName } = req.body;

    // 1. Validar PIN de administrador
    if (!adminPin) {
      return res.status(400).json({ success: false, error: 'adminPin requerido' });
    }
    const pinStr = String(adminPin).trim();
    const pinValid = ADMIN_PIN_HASH ? bcrypt.compareSync(pinStr, ADMIN_PIN_HASH) : (pinStr === ADMIN_PIN_PLAIN);
    if (!pinValid) {
      return res.status(401).json({ success: false, message: 'PIN de Administrador incorrecto' });
    }

    // 2. Asegurar catálogo de rejillas
    const grCount = await dbQueryGet(`SELECT COUNT(*) as count FROM grilles`);
    if (!grCount || grCount.count === 0) {
      await seedInitialData();
    }

    // 3. Registrar primer empleado
    const code = String(initialEmployeeCode || 'EMP-001').trim().toUpperCase();
    const name = String(initialEmployeeName || 'Operario Principal').trim();

    await dbRun(
      `INSERT OR REPLACE INTO employees (payroll_code, name, active, created_at_ts) VALUES (?, ?, 1, CURRENT_TIMESTAMP)`,
      [code, name]
    );

    res.json({
      success: true,
      payrollCode: code,
      name,
      message: 'Configuración inicial completada exitosamente'
    });
  } catch (err) {
    next(err);
  }
});

app.post('/api/system/reset', async (req, res, next) => {
  try {
    const { adminPin } = req.body;
    if (!adminPin) return res.status(400).json({ success: false, error: 'adminPin requerido' });

    const pinStr = String(adminPin).trim();
    const pinValid = ADMIN_PIN_HASH ? bcrypt.compareSync(pinStr, ADMIN_PIN_HASH) : (pinStr === ADMIN_PIN_PLAIN);
    if (!pinValid) {
      return res.status(401).json({ success: false, message: 'PIN de Administrador incorrecto' });
    }

    await dbExecTransaction(async () => {
      await dbRun(`DELETE FROM licenses`);
      await dbRun(`DELETE FROM devices`);
      await dbRun(`DELETE FROM operator_sessions`);
      await dbRun(`DELETE FROM employees`);
      await dbRun(`DELETE FROM filter_events`);
      await dbRun(`DELETE FROM sync_outbox`);
    });

    res.json({ success: true, message: 'Base de datos y estado de licencias reiniciados a cero.' });
  } catch (err) {
    next(err);
  }
});

// ==================== AUTENTICACIÓN Y SESIONES DE OPERARIOS ====================

app.post('/api/operator/login', async (req, res, next) => {
  try {
    const { payrollCode, deviceId, deviceName } = req.body;
    if (!payrollCode) {
      return res.status(400).json({ success: false, authenticated: false, error: 'payrollCode requerido' });
    }

    const cleanCode = String(payrollCode).trim().toUpperCase();
    const cleanDeviceId = deviceId ? String(deviceId).trim() : 'WEB-BROWSER';

    // 1. Verificar si el operario existe en la tabla de empleados
    const emp = await dbQueryGet(`SELECT payroll_code, name, active FROM employees WHERE UPPER(payroll_code) = ? AND active = 1`, [cleanCode]);

    if (!emp) {
      return res.status(401).json({
        success: false,
        authenticated: false,
        message: `El código de nómina "${cleanCode}" no está registrado en el sistema.`
      });
    }

    const token = uuidv4();
    const sessionId = uuidv4();

    await dbExecTransaction(async () => {
      // Desactivar sesiones anteriores para este dispositivo
      await dbRun(`UPDATE operator_sessions SET active = 0 WHERE device_id = ?`, [cleanDeviceId]);

      // Guardar nueva sesión activa
      await dbRun(
        `INSERT INTO operator_sessions (id, payroll_code, device_id, device_name, token, active, logged_in_at_ts, last_active_at_ts)
         VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
        [sessionId, emp.payroll_code, cleanDeviceId, deviceName || 'Navegador Web / App', token]
      );

      // Registro de auditoría
      await dbRun(
        `INSERT INTO audit_events (id, actor, action, target, details, created_at_ts)
         VALUES (?, ?, 'operator_login', 'session', ?, CURRENT_TIMESTAMP)`,
        [uuidv4(), emp.payroll_code, JSON.stringify({ deviceId: cleanDeviceId, sessionId })]
      );
    });

    res.json({
      success: true,
      authenticated: true,
      token,
      sessionId,
      payrollCode: emp.payroll_code,
      name: emp.name,
      loggedInAt: new Date().toISOString(),
      message: 'Sesión de operario iniciada correctamente en el servidor'
    });
  } catch (err) {
    next(err);
  }
});

app.get('/api/operator/session/:deviceId', async (req, res, next) => {
  try {
    const { deviceId } = req.params;
    const session = await dbQueryGet(
      `SELECT s.*, e.name FROM operator_sessions s
       JOIN employees e ON s.payroll_code = e.payroll_code
       WHERE s.device_id = ? AND s.active = 1
       ORDER BY s.logged_in_at_ts DESC LIMIT 1`,
      [deviceId]
    );

    if (!session) {
      return res.json({ active: false, message: 'Sin sesión activa para este dispositivo' });
    }

    // Actualizar última actividad
    await dbRun(`UPDATE operator_sessions SET last_active_at_ts = CURRENT_TIMESTAMP WHERE id = ?`, [session.id]);

    res.json({
      active: true,
      payrollCode: session.payroll_code,
      name: session.name,
      token: session.token,
      deviceId: session.device_id,
      loggedInAt: session.logged_in_at_ts
    });
  } catch (err) {
    next(err);
  }
});

app.post('/api/operator/logout', async (req, res, next) => {
  try {
    const { deviceId, token } = req.body;
    await dbRun(
      `UPDATE operator_sessions SET active = 0 WHERE device_id = ? OR token = ?`,
      [deviceId || null, token || null]
    );
    res.json({ success: true, loggedOut: true, message: 'Sesión cerrada exitosamente' });
  } catch (err) {
    next(err);
  }
});

// ==================== AUTENTICACIÓN ADMINISTRADOR ====================

app.post('/api/admin/validate-pin', (req, res) => {
  const { pin } = req.body;
  if (!pin) {
    return res.status(400).json({ success: false, authorized: false, error: 'PIN de administrador requerido' });
  }

  const inputPinStr = String(pin).trim();
  let isValid = false;

  // Verificación mediante Bcrypt
  if (ADMIN_PIN_HASH) {
    isValid = bcrypt.compareSync(inputPinStr, ADMIN_PIN_HASH);
  } else {
    isValid = inputPinStr === ADMIN_PIN_PLAIN;
  }

  if (isValid) {
    return res.json({
      success: true,
      authorized: true,
      message: 'Acceso de Administrador autorizado'
    });
  }

  return res.status(401).json({
    success: false,
    authorized: false,
    message: 'Clave de administrador incorrecta'
  });
});

// ==================== GESTIÓN DE LICENCIAS ====================

app.post('/api/license/activate', async (req, res, next) => {
  try {
    const { licenseKey, adminPin, deviceId, deviceName } = req.body;
    if (!licenseKey || !deviceId) {
      return res.status(400).json({ success: false, error: 'Campos requeridos: licenseKey y deviceId' });
    }

    // Validar PIN de administrador si se envía
    if (adminPin) {
      const pinStr = String(adminPin).trim();
      const pinValid = ADMIN_PIN_HASH ? bcrypt.compareSync(pinStr, ADMIN_PIN_HASH) : (pinStr === ADMIN_PIN_PLAIN);
      if (!pinValid) {
        return res.status(401).json({ success: false, message: 'PIN de Administrador incorrecto' });
      }
    }

    const cleanKey = String(licenseKey).trim().toUpperCase();
    const cleanDeviceId = String(deviceId).trim();

    const isValid = cleanKey.startsWith('PAN-');
    if (!isValid) {
      return res.status(400).json({
        success: false,
        message: 'Clave de licencia inválida. Formato esperado: PAN-XXXX-XXXX'
      });
    }

    const activationId = uuidv4();
    const expiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
    const signature = crypto.createHmac('sha256', LICENSE_SECRET)
      .update(`${cleanDeviceId}:${activationId}:${expiresAt}`)
      .digest('hex');

    await dbExecTransaction(async () => {
      // Registrar licencia
      await dbRun(
        `INSERT OR REPLACE INTO licenses
         (id, device_id, license_key, status, activated_at_ts, expires_at_ts, signature, updated_at_ts)
         VALUES (?, ?, ?, 'active', CURRENT_TIMESTAMP, ?, ?, CURRENT_TIMESTAMP)`,
        [activationId, cleanDeviceId, cleanKey, expiresAt, signature]
      );

      // Registrar dispositivo
      await dbRun(
        `INSERT OR REPLACE INTO devices
         (id, installation_id, name, last_seen_ts, created_at_ts)
         VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
        [cleanDeviceId, cleanDeviceId, deviceName || 'Dispositivo Móvil']
      );

      // Auditoría
      await dbRun(
        `INSERT INTO audit_events (id, actor, action, target, details, created_at_ts)
         VALUES (?, 'system', 'license_activate', ?, ?, CURRENT_TIMESTAMP)`,
        [uuidv4(), 'license', JSON.stringify({ deviceId: cleanDeviceId, licenseKey: cleanKey })]
      );
    });

    res.json({
      success: true,
      activationId,
      deviceId: cleanDeviceId,
      licenseKey: cleanKey,
      expiresAt,
      signature,
      message: 'Producto activado y licenciado exitosamente para este dispositivo'
    });
  } catch (err) {
    next(err);
  }
});

app.get('/api/license/status/:deviceId', async (req, res, next) => {
  try {
    const { deviceId } = req.params;
    let row = await dbQueryGet(`SELECT * FROM licenses WHERE device_id = ?`, [deviceId]);

    if (!row) {
      row = await dbQueryGet(`SELECT * FROM licenses WHERE status = 'active' ORDER BY created_at_ts DESC LIMIT 1`);
    }

    if (!row) {
      return res.json({ active: false, message: 'Dispositivo sin activación registrada' });
    }

    const now = new Date();
    const expires = new Date(row.expires_at_ts);
    const days = Math.ceil((expires - now) / (1000 * 60 * 60 * 24));
    const isActive = row.status === 'active' && days > 0;

    res.json({
      active: isActive,
      deviceId: row.device_id,
      licenseKey: row.license_key || 'PAN-2026-PANASA-PROD',
      activatedAt: row.activated_at_ts,
      expiresAt: row.expires_at_ts,
      daysUntilExpiry: days > 0 ? days : 0,
      signature: row.signature
    });
  } catch (err) {
    next(err);
  }
});

// ==================== APLICACIÓN DE MIDDLEWARE DE AUTENTICACIÓN ====================

app.use('/api/employees', requireAuth);
app.use('/api/grilles', requireAuth);
app.use('/api/filters', requireAuth);
app.use('/api/events', requireAuth);
app.use('/api/sync', requireAuth);

// ==================== RESTAURACIÓN Y RECUPERACIÓN DE DATOS MÓVILES ====================

app.post('/api/sync/restore', async (req, res, next) => {
  try {
    const { deviceId, licenseKey } = req.body;

    let validLicense = null;
    if (deviceId) {
      validLicense = await dbQueryGet(`SELECT * FROM licenses WHERE device_id = ? AND status = 'active'`, [deviceId]);
    }

    if (!validLicense && licenseKey) {
      const cleanKey = String(licenseKey).trim().toUpperCase();
      if (cleanKey.startsWith('PAN-')) {
        validLicense = { status: 'active' };
      }
    }

    if (!validLicense) {
      return res.status(403).json({
        success: false,
        error: 'No se encontró una licencia activa o vinculada a este dispositivo para restaurar datos.'
      });
    }

    const [grilles, filters, employees, events] = await Promise.all([
      dbQueryAll(`SELECT * FROM grilles ORDER BY grille_code`),
      dbQueryAll(`SELECT * FROM filters ORDER BY grille_code, filter_number`),
      dbQueryAll(`SELECT payroll_code, name, active FROM employees WHERE active = 1`),
      dbQueryAll(`SELECT * FROM filter_events ORDER BY occurred_at_ts DESC`)
    ]);

    res.json({
      success: true,
      restoredAt: new Date().toISOString(),
      counts: {
        grilles: grilles.length,
        filters: filters.length,
        employees: employees.length,
        events: events.length
      },
      data: {
        grilles,
        filters,
        employees,
        events
      }
    });
  } catch (err) {
    next(err);
  }
});

// ==================== EMPLEADOS ====================

app.get('/api/employees', async (req, res, next) => {
  try {
    const rows = await dbQueryAll(`SELECT payroll_code, name, active FROM employees WHERE active = 1 ORDER BY name ASC`);
    res.json({ employees: rows });
  } catch (err) {
    next(err);
  }
});

app.post('/api/employees', async (req, res, next) => {
  try {
    const { payrollCode, name } = req.body;
    if (!payrollCode || !name) {
      return res.status(400).json({ error: 'Campos requeridos: payrollCode y name' });
    }

    const code = String(payrollCode).trim();
    const empName = String(name).trim();

    await dbRun(
      `INSERT OR REPLACE INTO employees (payroll_code, name, active, created_at_ts) VALUES (?, ?, 1, CURRENT_TIMESTAMP)`,
      [code, empName]
    );

    res.json({ success: true, payrollCode: code, name: empName });
  } catch (err) {
    next(err);
  }
});

app.delete('/api/employees/:payrollCode', async (req, res, next) => {
  try {
    const { payrollCode } = req.params;
    if (!payrollCode) {
      return res.status(400).json({ error: 'payrollCode requerido' });
    }

    const code = String(payrollCode).trim().toUpperCase();
    await dbExecTransaction(async () => {
      await dbRun(`DELETE FROM employees WHERE UPPER(payroll_code) = ?`, [code]);
      await dbRun(`UPDATE operator_sessions SET active = 0 WHERE UPPER(payroll_code) = ?`, [code]);
      await dbRun(
        `INSERT INTO audit_events (id, actor, action, target, details, created_at_ts)
         VALUES (?, 'system', 'employee_delete', 'employee', ?, CURRENT_TIMESTAMP)`,
        [uuidv4(), JSON.stringify({ payrollCode: code })]
      );
    });

    res.json({ success: true, payrollCode: code, message: 'Operario eliminado exitosamente' });
  } catch (err) {
    next(err);
  }
});

// ==================== REJILLAS Y FILTROS ====================

app.get('/api/grilles', async (req, res, next) => {
  try {
    const rows = await dbQueryAll(`SELECT * FROM grilles ORDER BY grille_code ASC`);
    res.json({ grilles: rows });
  } catch (err) {
    next(err);
  }
});

app.get('/api/filters/:grilleCode', async (req, res, next) => {
  try {
    const { grilleCode } = req.params;
    const rows = await dbQueryAll(
      `SELECT * FROM filters WHERE grille_code = ? ORDER BY filter_number ASC`,
      [grilleCode]
    );
    res.json({ filters: rows });
  } catch (err) {
    next(err);
  }
});

// ==================== EVENTOS DE REEMPLAZO DE FILTROS ====================

app.post('/api/events', async (req, res, next) => {
  try {
    const { eventId, grilleCode, filterNumber, payrollCode, occurredAt, deviceInstallationId, notes } = req.body;

    if (!eventId || !grilleCode || filterNumber == null || !payrollCode || !occurredAt) {
      return res.status(400).json({ error: 'Campos requeridos: eventId, grilleCode, filterNumber, payrollCode, occurredAt' });
    }

    const existing = await dbQueryGet(`SELECT id FROM filter_events WHERE event_id = ?`, [eventId]);
    if (existing) {
      return res.status(200).json({ success: true, duplicate: true, eventId, message: 'Evento ya registrado previamente.' });
    }

    const id = uuidv4();
    const serverReceivedAt = new Date().toISOString();
    const payload = JSON.stringify({ eventId, grilleCode, filterNumber, payrollCode, occurredAt, deviceInstallationId, notes, serverReceivedAt });
    const nextRetry = new Date(Date.now() + 5000).toISOString();

    await dbExecTransaction(async () => {
      await dbRun(
        `INSERT INTO filter_events
         (id, event_id, grille_code, filter_number, payroll_code, occurred_at_ts, device_installation_id, notes, server_received_at_ts, synced, created_at_ts)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP)`,
        [id, eventId, grilleCode, Number(filterNumber), payrollCode, occurredAt, deviceInstallationId || null, notes || null, serverReceivedAt]
      );

      await dbRun(
        `INSERT OR REPLACE INTO sync_outbox
         (id, event_id, payload, attempts, next_retry_at_ts, status, created_at_ts, updated_at_ts)
         VALUES (?, ?, ?, 0, ?, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
        [uuidv4(), eventId, payload, nextRetry]
      );

      await dbRun(
        `INSERT INTO audit_events (id, actor, action, target, details, created_at_ts)
         VALUES (?, 'system', 'event_register', ?, ?, CURRENT_TIMESTAMP)`,
        [uuidv4(), 'event', JSON.stringify({ eventId, grilleCode, filterNumber, payrollCode })]
      );
    });

    res.json({ success: true, eventId, id, serverReceivedAt, message: 'Evento registrado y respaldado exitosamente' });
  } catch (err) {
    next(err);
  }
});

app.get('/api/events', async (req, res, next) => {
  try {
    const { grilleCode, from, to, synced } = req.query;
    let sql = `SELECT * FROM filter_events WHERE 1=1`;
    const params = [];

    if (grilleCode) { sql += ` AND grille_code = ?`; params.push(grilleCode); }
    if (from) { sql += ` AND occurred_at_ts >= ?`; params.push(from); }
    if (to) { sql += ` AND occurred_at_ts <= ?`; params.push(to); }
    if (synced !== undefined) { sql += ` AND synced = ?`; params.push(synced === 'true' ? 1 : 0); }

    sql += ` ORDER BY occurred_at_ts DESC`;

    const rows = await dbQueryAll(sql, params);
    res.json({ events: rows, count: rows.length });
  } catch (err) {
    next(err);
  }
});

app.get('/api/events/pending', async (req, res, next) => {
  try {
    const rows = await dbQueryAll(`SELECT * FROM sync_outbox WHERE status = 'pending' ORDER BY next_retry_at_ts ASC`);
    res.json({ pending: rows, count: rows.length });
  } catch (err) {
    next(err);
  }
});

app.post('/api/events/ack', async (req, res, next) => {
  try {
    const { eventId, serverReceivedAt } = req.body;
    if (!eventId) return res.status(400).json({ error: 'eventId requerido' });

    await dbExecTransaction(async () => {
      await dbRun(`UPDATE filter_events SET synced = 1 WHERE event_id = ?`, [eventId]);
      await dbRun(`UPDATE sync_outbox SET status = 'synced', updated_at_ts = CURRENT_TIMESTAMP WHERE event_id = ?`, [eventId]);
    });

    res.json({ success: true, eventId, acknowledged: true, serverReceivedAt });
  } catch (err) {
    next(err);
  }
});

// ==================== SINCRONIZACIÓN ====================

app.get('/api/sync/cursor', async (req, res, next) => {
  try {
    const row = await dbQueryGet(`SELECT value FROM sync_cursor WHERE key = 'last_sync'`);
    res.json({ lastSync: row ? row.value : null });
  } catch (err) {
    next(err);
  }
});

app.post('/api/sync/cursor', async (req, res, next) => {
  try {
    const { value } = req.body;
    if (!value) return res.status(400).json({ error: 'value requerido' });

    await dbRun(
      `INSERT OR REPLACE INTO sync_cursor (key, value, updated_at_ts) VALUES ('last_sync', ?, CURRENT_TIMESTAMP)`,
      [value]
    );
    res.json({ success: true, lastSync: value });
  } catch (err) {
    next(err);
  }
});

app.post('/api/sync/outbox/process', async (req, res, next) => {
  try {
    const result = await processOutboxQueue(process.env.CENTRAL_SERVER_URL || null);
    res.json({ success: true, processed: result.processed, message: 'Barrido de outbox ejecutado' });
  } catch (err) {
    next(err);
  }
});

app.post('/api/sync/download', async (req, res, next) => {
  try {
    const { since } = req.body;
    const timestamp = since || new Date().toISOString();
    await dbRun(
      `INSERT OR REPLACE INTO sync_cursor (key, value, updated_at_ts) VALUES ('last_download', ?, CURRENT_TIMESTAMP)`,
      [timestamp]
    );
    res.json({ success: true, downloaded: 0, message: 'Sincronización completada' });
  } catch (err) {
    next(err);
  }
});

// Seed Manual y Reinicio de Estado de Rejillas
app.post('/api/seed', async (req, res, next) => {
  try {
    await dbExecTransaction(async () => {
      await dbRun(`DELETE FROM filter_events`);
      await dbRun(`DELETE FROM sync_outbox`);
      await dbRun(`DELETE FROM filters`);
      await dbRun(`DELETE FROM grilles`);
      await seedInitialData();
    });
    res.json({ success: true, grilles: 22, filters: 88, message: 'Seed y reinicio de estado de rejillas completado exitosamente' });
  } catch (err) {
    next(err);
  }
});

// ==================== MANEJADOR DE ERRORES GLOBAL ====================

app.use((err, req, res, next) => {
  console.error('[Unhandled Error]', err.stack || err.message);
  res.status(500).json({
    error: 'Error interno del servidor',
    message: NODE_ENV === 'development' ? err.message : 'Ocurrió un error inesperado al procesar la solicitud.'
  });
});

// Ruta no encontrada
app.use((req, res) => {
  res.status(404).json({ error: 'Ruta no encontrada' });
});

// ==================== INICIALIZACIÓN DEL SERVIDOR ====================

initDb().then(() => {
  validateEnvironment();
  initOutboxWorker();

  const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`====================================================`);
    console.log(`🚀 Filtros_Panasa API Backend en Producción`);
    console.log(`📡 Escuchando en: http://0.0.0.0:${PORT}`);
    console.log(`📂 DB SQLite Path: ${DB_PATH}`);
    console.log(`🔒 Entorno: ${NODE_ENV}`);
    console.log(`🌐 Dominio: panasa.gmnodo.com`);
    console.log(`====================================================`);
  });

  // Cierre limpio en interrupciones del sistema
  const gracefulShutdown = (signal) => {
    console.log(`\n[Server] Señal ${signal} recibida. Cerrando servidor y conexiones DB...`);
    server.close(() => {
      if (db) {
        db.close((err) => {
          if (err) console.error('[DB Close Error]', err.message);
          else console.log('[DB] Conexión SQLite cerrada correctamente.');
          process.exit(0);
        });
      } else {
        process.exit(0);
      }
    });
  };

  process.on('SIGINT', () => gracefulShutdown('SIGINT'));
  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

}).catch((err) => {
  console.error('❌ Error fatal al iniciar la base de datos:', err.message);
  process.exit(1);
});
