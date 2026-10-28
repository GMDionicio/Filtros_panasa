import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'local_db_service.dart';

class ApiService {
  static String get defaultBaseUrl {
    return 'https://panasa.gmnodo.com';
  }

  static String sanitizeUrl(String raw) {
    String clean = raw.trim();
    if (clean.isEmpty) return defaultBaseUrl;

    // Remover barras diagonales finales para evitar URL con doble diagonal
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }

    // Anteponer https:// si el usuario omitió el esquema (ej: panasa.gmnodo.com)
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }

    return clean;
  }

  static String baseUrl = defaultBaseUrl;
  static bool _initialized = false;

  /// Carga la URL del Servidor guardada
  static Future<void> initBaseUrl() async {
    if (_initialized) return;
    final savedUrl = await LocalDbService.getSetting('base_url');
    if (savedUrl != null &&
        savedUrl.trim().isNotEmpty &&
        !savedUrl.contains('localhost:3010')) {
      baseUrl = sanitizeUrl(savedUrl);
    } else {
      baseUrl = defaultBaseUrl;
    }
    _initialized = true;
  }

  /// Actualiza y persiste la URL del servidor
  static Future<void> updateBaseUrl(String newUrl) async {
    baseUrl = sanitizeUrl(newUrl);
    await LocalDbService.saveSetting('base_url', baseUrl);
  }

  /// Construye cabeceras HTTP de autenticación y licencia requeridas por el backend
  static Future<Map<String, String>> _getAuthHeaders() async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    final activeOp = await LocalDbService.getActiveOperator();
    if (activeOp != null && activeOp['token'] != null && activeOp['token']!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${activeOp['token']}';
    }

    final deviceId = await LocalDbService.getSetting('device_id') ?? (kIsWeb ? 'WEB-BROWSER' : 'EMULATOR-001');
    headers['X-Device-ID'] = deviceId;

    final licenseKey = await LocalDbService.getSetting('license_key') ?? 'PAN-PRODUCTION-2026';
    headers['X-License-Key'] = licenseKey;

    return headers;
  }

  /// Consulta el estado general del sistema (licencia activa, si existen operarios creados y si existen rejillas)
  static Future<Map<String, dynamic>?> checkSystemStatus({required String deviceId}) async {
    await initBaseUrl();

    final localActivated = await LocalDbService.getSetting('is_activated');

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/system/status/$deviceId'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isServerActivated = data['isActivated'] == true;

        if (isServerActivated) {
          await LocalDbService.saveSetting('is_activated', 'true');
        }

        return {
          ...data,
          'isActivated': isServerActivated || localActivated == 'true',
        };
      }
    } catch (e) {
      debugPrint('Error verificando estado del sistema: $e');
    }

    if (localActivated == 'true') {
      return {
        'success': true,
        'deviceId': deviceId,
        'isActivated': true,
        'hasEmployees': true,
        'hasGrilles': true,
      };
    }

    return null;
  }

  /// Activa el producto con Clave de Licencia y PIN de Administrador
  static Future<Map<String, dynamic>?> activateProduct({
    required String licenseKey,
    required String adminPin,
    required String deviceId,
    String? deviceName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/license/activate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'licenseKey': licenseKey,
              'adminPin': adminPin,
              'deviceId': deviceId,
              'deviceName': deviceName ?? (kIsWeb ? 'Navegador Web' : 'Dispositivo Android'),
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await LocalDbService.saveSetting('is_activated', 'true');
        return data;
      }
      return {'success': false, 'message': data['message'] ?? 'Error activando producto'};
    } catch (e) {
      debugPrint('Error al activar producto: $e');
    }
    return {'success': false, 'message': 'Error de conexión con el servidor de licencias'};
  }

  /// Ejecuta la configuración e inicialización de planta y primer operario
  static Future<Map<String, dynamic>?> initialSetup({
    required String adminPin,
    required String employeeCode,
    required String employeeName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/system/setup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'adminPin': adminPin,
              'initialEmployeeCode': employeeCode,
              'initialEmployeeName': employeeName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await LocalDbService.saveSetting('is_activated', 'true');
        return data;
      }
      return {'success': false, 'message': data['message'] ?? 'Error en configuración inicial'};
    } catch (e) {
      debugPrint('Error en la configuración inicial del sistema: $e');
    }
    return {'success': false, 'message': 'Error de conexión con el servidor'};
  }

  /// Autentica al operario en el servidor online y genera una sesión activa vinculada a este dispositivo
  static Future<Map<String, dynamic>?> loginOperator({
    required String payrollCode,
    required String deviceId,
    String? deviceName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/operator/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'payrollCode': payrollCode,
              'deviceId': deviceId,
              'deviceName': deviceName ?? (kIsWeb ? 'Navegador Web' : 'App Android'),
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['authenticated'] == true) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('Error autenticando operario en el servidor: $e');
    }
    return null;
  }

  /// Verifica si el dispositivo cuenta con una sesión activa en el servidor online
  static Future<Map<String, dynamic>?> checkOperatorSession({required String deviceId}) async {
    await initBaseUrl();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/operator/session/$deviceId'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['active'] == true) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('Error verificando sesión de operario en servidor: $e');
    }
    return null;
  }

  /// Cierra la sesión activa en el servidor
  static Future<void> logoutOperator({required String deviceId, String? token}) async {
    await initBaseUrl();
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/operator/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId, 'token': token}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Valida la clave de usuario administrador (1513) desde el servidor online
  static Future<bool> validateAdminPin(String pin) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/validate-pin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authorized'] == true;
      }
    } catch (e) {
      debugPrint('Error al validar PIN de administrador en servidor online: $e');
    }
    return false;
  }

  // Health check con el servidor online
  static Future<bool> checkHealth() async {
    await initBaseUrl();
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (_) {}
    return false;
  }

  // Resiembra la base de datos central y reinicia la base local
  static Future<bool> seedDatabase() async {
    await initBaseUrl();

    // 1. Limpiar base de datos local y caché (SQLite / SharedPreferences)
    await LocalDbService.clearLocalGrillesAndEvents();

    // 2. Establecer localmente el catálogo limpio (22 rejillas, 88 filtros en estado urgente/rojo)
    final cleanMock = _generateMockGrilles();
    await LocalDbService.saveGrilles(cleanMock);

    // 3. Ejecutar seed en servidor backend para purgar eventos remotos
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/seed'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await getGrilles();
      }
    } catch (e) {
      debugPrint('Error ejecutando seed en servidor: $e');
    }

    return true;
  }

  // Batch Sync (Solo aplica para Android/Móvil)
  static Future<void> syncPendingEvents() async {
    if (kIsWeb) return; // En Web los datos se leen/escriben directamente en el servidor
    await initBaseUrl();
    final pending = await LocalDbService.getPendingEvents();
    if (pending.isEmpty) return;

    for (var item in pending) {
      try {
        final headers = await _getAuthHeaders();
        final body = jsonEncode({
          'eventId': item['event_id'],
          'grilleCode': item['grille_code'],
          'filterNumber': item['filter_number'],
          'payrollCode': item['payroll_code'],
          'occurredAt': item['occurred_at'],
          'deviceInstallationId': 'EMULATOR-001',
          'notes': item['notes'],
        });

        final response = await http
            .post(
              Uri.parse('$baseUrl/api/events'),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          await LocalDbService.deletePendingEvent(item['id']);
          debugPrint('Synced offline event ${item['id']} to backend.');
        }
      } catch (e) {
        debugPrint('Failed to sync offline event ${item['id']}: $e');
      }
    }
  }

  // Obtener Rejillas + Filtros + Últimos Eventos
  // En Web: Lee DIRECTAMENTE del servidor online
  // En Android: Usa estrategia Local-First con SQLite
  static Future<List<Grille>> getGrilles() async {
    await initBaseUrl();
    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/api/grilles'), headers: headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        if (!kIsWeb) {
          await syncPendingEvents();
        }

        final data = jsonDecode(response.body);
        final List rawGrilles = data['grilles'] ?? [];

        Map<String, FilterEvent> latestEvents = {};
        try {
          final eventsResponse = await http
              .get(Uri.parse('$baseUrl/api/events'), headers: headers)
              .timeout(const Duration(seconds: 8));
          if (eventsResponse.statusCode == 200) {
            final eventsData = jsonDecode(eventsResponse.body);
            final List rawEvents = eventsData['events'] ?? [];
            for (var e in rawEvents) {
              final event = FilterEvent.fromJson(e);
              final key = '${event.grilleCode}_${event.filterNumber}';
              if (!latestEvents.containsKey(key) ||
                  event.occurredAt.isAfter(latestEvents[key]!.occurredAt)) {
                latestEvents[key] = event;
              }
            }
          }
        } catch (_) {}

        List<Grille> grilles = [];
        final positions = [
          '1-arriba-izquierda',
          '2-arriba-derecha',
          '3-abajo-derecha',
          '4-abajo-izquierda'
        ];

        for (var g in rawGrilles) {
          final code = g['grille_code'] ?? '';
          List<FilterItem> filterItems = [];

          for (int j = 1; j <= 4; j++) {
            final key = '${code}_$j';
            final lastEv = latestEvents[key];
            filterItems.add(FilterItem(
              id: key,
              grilleCode: code,
              filterNumber: j,
              positionLabel: positions[j - 1],
              lastReplacedAt: lastEv?.occurredAt,
              lastEmployeeCode: lastEv?.payrollCode,
            ));
          }

          grilles.add(Grille(
            code: code,
            name: g['name'] ?? 'Rejilla $code',
            position: g['position'] ?? 0,
            filters: filterItems,
          ));
        }

        if (grilles.isNotEmpty) {
          await LocalDbService.saveGrilles(grilles);
          return grilles;
        }
      }
    } catch (e) {
      debugPrint('Error de comunicación con servidor online: $e');
    }

    // Si está en Web y falló la conexión con el servidor online, cargar caché web
    final cached = await LocalDbService.loadCachedGrilles();
    if (cached.isNotEmpty) {
      return cached;
    }

    final mock = _generateMockGrilles();
    await LocalDbService.saveGrilles(mock);
    return mock;
  }

  // Registrar Reemplazo de Filtro
  // En Web: Envía DIRECTAMENTE al servidor online
  // En Android: Escritura Local SQLite + envío diferido
  static Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  }) async {
    await initBaseUrl();
    final now = DateTime.now();

    // 1. Envío directo al Servidor Online
    try {
      final headers = await _getAuthHeaders();
      final eventId = 'EVT-${now.millisecondsSinceEpoch}-$filterNumber';
      final body = jsonEncode({
        'eventId': eventId,
        'grilleCode': grilleCode,
        'filterNumber': filterNumber,
        'payrollCode': payrollCode,
        'occurredAt': now.toIso8601String(),
        'deviceInstallationId': kIsWeb ? 'WEB-BROWSER' : 'ANDROID-APP',
        'notes': notes ?? (kIsWeb ? 'Mantenimiento registrado desde Web' : 'Mantenimiento registrado desde App Android'),
      });

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/events'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await LocalDbService.updateLocalFilterReplacement(
          grilleCode: grilleCode,
          filterNumber: filterNumber,
          payrollCode: payrollCode,
          replacedAt: now,
        );
        return true;
      }
    } catch (e) {
      debugPrint('Error enviando evento al servidor online: $e');
    }

    // Si estamos en móvil, encolar offline
    if (!kIsWeb) {
      await LocalDbService.updateLocalFilterReplacement(
        grilleCode: grilleCode,
        filterNumber: filterNumber,
        payrollCode: payrollCode,
        replacedAt: now,
      );
      await LocalDbService.savePendingEvent(
        grilleCode: grilleCode,
        filterNumber: filterNumber,
        payrollCode: payrollCode,
        occurredAt: now,
        notes: notes,
      );
      return true;
    }

    return false;
  }

  // Obtener Empleados directamente del servidor online
  static Future<List<Employee>> getEmployees() async {
    await initBaseUrl();
    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/employees'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['employees'] ?? [];
        final employees = list.map((e) => Employee.fromJson(e)).toList();
        await LocalDbService.saveEmployees(employees);
        return employees;
      } else {
        debugPrint('getEmployees HTTP error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error obteniendo empleados del servidor online: $e');
    }

    return await LocalDbService.loadEmployees();
  }

  // Agregar Empleado directamente en el servidor online
  static Future<bool> addEmployee(String payrollCode, String name) async {
    await initBaseUrl();
    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/employees'),
            headers: headers,
            body: jsonEncode({'payrollCode': payrollCode, 'name': name}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final newEmp = Employee(payrollCode: payrollCode, name: name);
        final current = await LocalDbService.loadEmployees();
        current.removeWhere((e) => e.payrollCode == payrollCode);
        current.add(newEmp);
        await LocalDbService.saveEmployees(current);
        return true;
      }
    } catch (e) {
      debugPrint('Error agregando empleado en servidor online: $e');
    }

    if (!kIsWeb) {
      final newEmp = Employee(payrollCode: payrollCode, name: name);
      final current = await LocalDbService.loadEmployees();
      current.removeWhere((e) => e.payrollCode == payrollCode);
      current.add(newEmp);
      await LocalDbService.saveEmployees(current);
      return true;
    }

    return false;
  }

  // Eliminar Empleado/Operario directamente en el servidor online y localmente
  static Future<bool> deleteEmployee(String payrollCode) async {
    await initBaseUrl();
    final cleanCode = payrollCode.trim();
    try {
      final headers = await _getAuthHeaders();
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/employees/${Uri.encodeComponent(cleanCode)}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await LocalDbService.deleteEmployee(cleanCode);
        return true;
      }
    } catch (e) {
      debugPrint('Error eliminando empleado en servidor: $e');
    }

    if (!kIsWeb) {
      await LocalDbService.deleteEmployee(cleanCode);
      return true;
    }

    return false;
  }

  /// Restauración desde Servidor Online
  static Future<bool> restoreDataFromBackend({String? deviceId, String? licenseKey}) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/sync/restore'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId ?? (kIsWeb ? 'WEB-BROWSER' : 'EMULATOR-001'),
              'licenseKey': licenseKey ?? 'PAN-PRODUCTION-2026',
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];
          if (data['employees'] != null) {
            final List empList = data['employees'];
            final employees = empList.map((e) => Employee.fromJson(e)).toList();
            await LocalDbService.saveEmployees(employees);
          }
          await getGrilles();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error restaurando datos desde el servidor: $e');
    }
    return false;
  }

  // Generador de datos de catálogo inicial limpio (22 rejillas y 88 filtros)
  static List<Grille> _generateMockGrilles() {
    List<Grille> list = [];
    final positions = [
      '1-arriba-izquierda',
      '2-arriba-derecha',
      '3-abajo-derecha',
      '4-abajo-izquierda'
    ];

    for (int i = 1; i <= 22; i++) {
      final code = 'R${i.toString().padLeft(2, '0')}';
      list.add(Grille(
        code: code,
        name: 'Rejilla $code',
        position: i,
        filters: List.generate(4, (j) => FilterItem(
          id: '${code}_${j + 1}',
          grilleCode: code,
          filterNumber: j + 1,
          positionLabel: positions[j],
          lastReplacedAt: null,
          lastEmployeeCode: null,
        )),
      ));
    }
    return list;
  }
}
