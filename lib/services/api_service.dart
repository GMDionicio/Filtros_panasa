import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static String baseUrl = 'http://10.0.2.2:3010';

  static void updateBaseUrl(String newUrl) {
    baseUrl = newUrl;
  }

  // Health check
  static Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
    } catch (_) {}
    return false;
  }

  // Seed DB with initial 22 grilles and 88 filters
  static Future<bool> seedDatabase() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/seed'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Get all Grilles + Filters + Last Events
  static Future<List<Grille>> getGrilles() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/grilles'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return _generateMockGrilles();

      final data = jsonDecode(response.body);
      final List rawGrilles = data['grilles'] ?? [];

      Map<String, FilterEvent> latestEvents = {};
      try {
        final eventsResponse = await http
            .get(Uri.parse('$baseUrl/api/events'))
            .timeout(const Duration(seconds: 2));
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

      return grilles.isNotEmpty ? grilles : _generateMockGrilles();
    } catch (e) {
      debugPrint('Error loading grilles from API: $e');
      return _generateMockGrilles();
    }
  }

  // Register a filter replacement event
  static Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  }) async {
    try {
      final eventId = 'EVT-${DateTime.now().millisecondsSinceEpoch}-$filterNumber';
      final body = jsonEncode({
        'eventId': eventId,
        'grilleCode': grilleCode,
        'filterNumber': filterNumber,
        'payrollCode': payrollCode,
        'occurredAt': DateTime.now().toIso8601String(),
        'deviceInstallationId': 'EMULATOR-001',
        'notes': notes ?? 'Mantenimiento registrado desde App Flutter',
      });

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/events'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error registering event: $e');
      return false;
    }
  }

  // Get Employees list
  static Future<List<Employee>> getEmployees() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/employees'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List list = data['employees'] ?? [];
        if (list.isNotEmpty) {
          return list.map((e) => Employee.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return [
      Employee(payrollCode: 'EMP-001', name: 'Juan Pérez'),
      Employee(payrollCode: 'EMP-002', name: 'Carlos López'),
      Employee(payrollCode: 'EMP-003', name: 'María Gómez'),
      Employee(payrollCode: 'EMP-004', name: 'Dionicio Gómez'),
    ];
  }

  // Add Employee
  static Future<bool> addEmployee(String payrollCode, String name) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/employees'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'payrollCode': payrollCode, 'name': name}),
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Fallback mock grilles if offline
  static List<Grille> _generateMockGrilles() {
    List<Grille> list = [];
    final now = DateTime.now();
    for (int i = 1; i <= 22; i++) {
      final code = 'R${i.toString().padLeft(2, '0')}';
      int daysAgo = (i * 3) % 25;
      final date = now.subtract(Duration(days: daysAgo));

      list.add(Grille(
        code: code,
        name: 'Rejilla $code',
        position: i,
        filters: [
          FilterItem(id: '${code}_1', grilleCode: code, filterNumber: 1, positionLabel: '1-arriba-izquierda', lastReplacedAt: date, lastEmployeeCode: 'EMP-001'),
          FilterItem(id: '${code}_2', grilleCode: code, filterNumber: 2, positionLabel: '2-arriba-derecha', lastReplacedAt: date.subtract(const Duration(days: 2)), lastEmployeeCode: 'EMP-002'),
          FilterItem(id: '${code}_3', grilleCode: code, filterNumber: 3, positionLabel: '3-abajo-derecha', lastReplacedAt: date, lastEmployeeCode: 'EMP-001'),
          FilterItem(id: '${code}_4', grilleCode: code, filterNumber: 4, positionLabel: '4-abajo-izquierda', lastReplacedAt: date, lastEmployeeCode: 'EMP-003'),
        ],
      ));
    }
    return list;
  }
}
