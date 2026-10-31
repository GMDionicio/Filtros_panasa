import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'local_data_source.dart';

abstract class RemoteDataSource {
  String get baseUrl;
  Future<void> initBaseUrl();
  Future<void> updateBaseUrl(String newUrl);
  Future<Map<String, String>> getAuthHeaders();
  Future<Map<String, dynamic>?> checkSystemStatus({required String deviceId});
  Future<Map<String, dynamic>?> activateProduct({
    required String licenseKey,
    required String adminPin,
    required String deviceId,
    String? deviceName,
  });
  Future<Map<String, dynamic>?> initialSetup({
    required String adminPin,
    required String employeeCode,
    required String employeeName,
  });
  Future<Map<String, dynamic>?> loginOperator({
    required String payrollCode,
    required String deviceId,
    String? deviceName,
  });
  Future<Map<String, dynamic>?> checkOperatorSession({required String deviceId});
  Future<void> logoutOperator({required String deviceId, String? token});
  Future<bool> validateAdminPin(String pin);
  Future<bool> checkHealth();
  Future<bool> seedBackendDatabase(String adminPin);
  Future<bool> syncPendingEvent(Map<String, dynamic> item);
  Future<Map<String, dynamic>?> fetchGrillesAndEvents();
  /// Descarga incremental de eventos + grilles_status vía POST /api/sync/download.
  /// [since] es un ISO-8601 opcional; si se omite el backend usa last_download.
  /// Retorna Map con claves: events, grilles_status, cutoff_used, downloaded_at.
  Future<Map<String, dynamic>?> downloadSync({String? since});
  Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  });
  Future<List<Employee>?> getEmployees();
  Future<bool> addEmployee(String payrollCode, String name);
  Future<bool> deleteEmployee(String payrollCode);
  Future<Map<String, dynamic>?> restoreDataFromBackend({String? deviceId, String? licenseKey});
}

class RemoteDataSourceImpl implements RemoteDataSource {
  final LocalDataSource localDataSource;

  static String get defaultBaseUrl {
    if (kIsWeb &&
        Uri.base.origin.startsWith('http') &&
        !Uri.base.origin.contains('localhost')) {
      return Uri.base.origin;
    }
    return 'https://panasa.gmnodo.com';
  }
  String _baseUrl = defaultBaseUrl;
  bool _initialized = false;

  RemoteDataSourceImpl({required this.localDataSource});

  static String sanitizeUrl(String raw) {
    String clean = raw.trim();
    if (clean.isEmpty) return defaultBaseUrl;

    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }

    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }

    return clean;
  }

  @override
  String get baseUrl => _baseUrl;

  @override
  Future<void> initBaseUrl() async {
    if (_initialized) return;
    final savedUrl = await localDataSource.getSetting('base_url');
    if (savedUrl != null &&
        savedUrl.trim().isNotEmpty &&
        !savedUrl.contains('localhost:3010')) {
      _baseUrl = sanitizeUrl(savedUrl);
    } else {
      _baseUrl = defaultBaseUrl;
    }
    _initialized = true;
  }

  @override
  Future<void> updateBaseUrl(String newUrl) async {
    _baseUrl = sanitizeUrl(newUrl);
    await localDataSource.saveSetting('base_url', _baseUrl);
  }

  @override
  Future<Map<String, String>> getAuthHeaders() async {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    final activeOp = await localDataSource.getActiveOperator();
    if (activeOp != null && activeOp['token'] != null && activeOp['token']!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${activeOp['token']}';
    }

    final deviceId = await localDataSource.getOrCreateDeviceId();
    headers['X-Device-ID'] = deviceId;

    final licenseKey = await localDataSource.getSetting('license_key');
    if (licenseKey != null && licenseKey.isNotEmpty) {
      headers['X-License-Key'] = licenseKey;
    }

    return headers;
  }

  @override
  Future<Map<String, dynamic>?> checkSystemStatus({required String deviceId}) async {
    await initBaseUrl();
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/system/status/$deviceId'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error verificando estado del sistema en RemoteDataSource: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> activateProduct({
    required String licenseKey,
    required String adminPin,
    required String deviceId,
    String? deviceName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/license/activate'),
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
        return data;
      }
      return {'success': false, 'message': data['message'] ?? 'Error activando producto'};
    } catch (e) {
      debugPrint('Error al activar producto: $e');
    }
    return {'success': false, 'message': 'Error de conexión con el servidor de licencias'};
  }

  @override
  Future<Map<String, dynamic>?> initialSetup({
    required String adminPin,
    required String employeeCode,
    required String employeeName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/system/setup'),
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
        return data;
      }
      return {'success': false, 'message': data['message'] ?? 'Error en configuración inicial'};
    } catch (e) {
      debugPrint('Error en la configuración inicial del sistema: $e');
    }
    return {'success': false, 'message': 'Error de conexión con el servidor'};
  }

  @override
  Future<Map<String, dynamic>?> loginOperator({
    required String payrollCode,
    required String deviceId,
    String? deviceName,
  }) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/operator/login'),
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
      debugPrint('Error autenticando operario en servidor: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> checkOperatorSession({required String deviceId}) async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/operator/session/$deviceId'),
            headers: headers,
          )
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

  @override
  Future<void> logoutOperator({required String deviceId, String? token}) async {
    await initBaseUrl();
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/operator/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId, 'token': token}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  @override
  Future<bool> validateAdminPin(String pin) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/admin/validate-pin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authorized'] == true;
      }
    } catch (e) {
      debugPrint('Error al validar PIN de administrador: $e');
    }
    return false;
  }

  @override
  Future<bool> checkHealth() async {
    await initBaseUrl();
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (_) {}

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (_) {}

    return false;
  }

  @override
  Future<bool> seedBackendDatabase(String adminPin) async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/seed'),
            headers: headers,
            body: jsonEncode({'adminPin': adminPin.trim()}),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error ejecutando seed en servidor: $e');
      return false;
    }
  }

  @override
  Future<bool> syncPendingEvent(Map<String, dynamic> item) async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      final deviceId = await localDataSource.getOrCreateDeviceId();
      final body = jsonEncode({
        'eventId': item['event_id'],
        'grilleCode': item['grille_code'],
        'filterNumber': item['filter_number'],
        'payrollCode': item['payroll_code'],
        'occurredAt': item['occurred_at'],
        'deviceInstallationId': deviceId,
        'notes': item['notes'],
      });

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/events'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error syncing pending event: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchGrillesAndEvents() async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/api/grilles'), headers: headers).timeout(const Duration(seconds: 8)),
        http.get(Uri.parse('$_baseUrl/api/events'), headers: headers).timeout(const Duration(seconds: 8)),
      ]);

      final grillesResponse = results[0];
      final eventsResponse = results[1];

      // Si cualquiera de las dos peticiones falla o da 401, retornamos null para conservar la caché local intacta
      if (grillesResponse.statusCode != 200 || eventsResponse.statusCode != 200) {
        return null;
      }

      final grillesData = jsonDecode(grillesResponse.body);
      final eventsData = jsonDecode(eventsResponse.body);

      return {
        'grilles': grillesData['grilles'] ?? [],
        'events': eventsData['events'] ?? [],
      };
    } catch (e) {
      debugPrint('Error de comunicación con servidor online: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> downloadSync({String? since}) async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final body = <String, dynamic>{};
      if (since != null && since.isNotEmpty) {
        body['since'] = since;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/sync/download'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint('sync/download error: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        debugPrint('sync/download response success=false: ${data['message']}');
        return null;
      }

      return {
        'events': data['events'] ?? [],
        'grilles_status': data['grilles_status'] ?? [],
        'cutoff_used': data['cutoff_used'],
        'downloaded_at': data['downloaded_at'],
      };
    } catch (e) {
      debugPrint('Error en sync/download: $e');
      return null;
    }
  }

  @override
  Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  }) async {
    await initBaseUrl();
    final now = DateTime.now().toUtc();
    try {
      final headers = await getAuthHeaders();
      final deviceId = await localDataSource.getOrCreateDeviceId();
      final eventId = 'EVT-${now.millisecondsSinceEpoch}-$filterNumber';
      final body = jsonEncode({
        'eventId': eventId,
        'grilleCode': grilleCode,
        'filterNumber': filterNumber,
        'payrollCode': payrollCode,
        'occurredAt': now.toIso8601String(),
        'deviceInstallationId': deviceId,
        'notes': notes ??
            (kIsWeb
                ? 'Mantenimiento registrado desde Web'
                : 'Mantenimiento registrado desde App Android'),
      });

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/events'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error enviando evento al servidor online: $e');
      return false;
    }
  }

  @override
  Future<List<Employee>?> getEmployees() async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/employees'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['employees'] ?? [];
        return list.map((e) => Employee.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error obteniendo empleados del servidor online: $e');
    }
    return null;
  }

  @override
  Future<bool> addEmployee(String payrollCode, String name) async {
    await initBaseUrl();
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/employees'),
            headers: headers,
            body: jsonEncode({'payrollCode': payrollCode, 'name': name}),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error agregando empleado en servidor online: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteEmployee(String payrollCode) async {
    await initBaseUrl();
    final cleanCode = payrollCode.trim();
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .delete(
            Uri.parse('$_baseUrl/api/employees/${Uri.encodeComponent(cleanCode)}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error eliminando empleado en servidor: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> restoreDataFromBackend({String? deviceId, String? licenseKey}) async {
    await initBaseUrl();
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/sync/restore'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId ?? await localDataSource.getOrCreateDeviceId(),
              'licenseKey': licenseKey ?? '',
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error restaurando datos desde el servidor: $e');
    }
    return null;
  }
}
