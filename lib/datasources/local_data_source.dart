import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

abstract class LocalDataSource {
  Future<void> saveSetting(String key, String value);
  Future<String?> getSetting(String key);
  Future<String> getOrCreateDeviceId();
  Future<void> saveActiveOperator(String payrollCode, String name, {String? token});
  Future<Map<String, String>?> getActiveOperator();
  Future<void> clearActiveOperator();
  Future<void> saveEmployees(List<Employee> employees);
  Future<List<Employee>> loadEmployees();
  Future<void> deleteEmployee(String payrollCode);
  Future<void> saveGrilles(List<Grille> grilles);
  Future<List<Grille>> loadCachedGrilles();
  Future<void> savePendingEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime occurredAt,
    String? notes,
  });
  Future<List<Map<String, dynamic>>> getPendingEvents();
  Future<void> deletePendingEvent(String id);
  Future<void> updateLocalFilterReplacement({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime replacedAt,
  });
  Future<void> clearLocalGrillesAndEvents();
}

class LocalDataSourceImpl implements LocalDataSource {
  static Database? _db;

  Future<Database?> get _database async {
    if (kIsWeb) return null;
    if (_db != null) return _db;
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'filtros_panasa_local.db');
      _db = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE grilles (
              code TEXT PRIMARY KEY,
              name TEXT,
              position INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE filters (
              id TEXT PRIMARY KEY,
              grille_code TEXT,
              filter_number INTEGER,
              position_label TEXT,
              last_replaced_at TEXT,
              last_employee_code TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE pending_events (
              id TEXT PRIMARY KEY,
              event_id TEXT,
              grille_code TEXT,
              filter_number INTEGER,
              payroll_code TEXT,
              occurred_at TEXT,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE employees (
              payroll_code TEXT PRIMARY KEY,
              name TEXT,
              active INTEGER
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS employees (
                payroll_code TEXT PRIMARY KEY,
                name TEXT,
                active INTEGER
              )
            ''');
          }
        },
      );
      return _db;
    } catch (e) {
      debugPrint('Sqflite init error, fallback to SharedPreferences: $e');
      return null;
    }
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          await db.insert(
            'settings',
            {'key': key, 'value': value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return;
        } catch (e) {
          debugPrint('Error saving setting to sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('setting_$key', value);
    } catch (e) {
      debugPrint('Error saving setting to SharedPreferences: $e');
    }
  }

  @override
  Future<String?> getSetting(String key) async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final res = await db.query('settings', where: 'key = ?', whereArgs: [key]);
          if (res.isNotEmpty) {
            return res.first['value'] as String?;
          }
        } catch (e) {
          debugPrint('Error reading setting from sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('setting_$key');
    } catch (_) {}

    return null;
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    var id = await getSetting('device_id');
    if (id == null || id.isEmpty) {
      final rng = Random();
      id = 'DEV-${DateTime.now().millisecondsSinceEpoch}-${rng.nextInt(0x7FFFFFFF).toRadixString(16)}';
      await saveSetting('device_id', id);
    }
    return id;
  }

  @override
  Future<void> saveActiveOperator(String payrollCode, String name, {String? token}) async {
    await saveSetting('active_operator_code', payrollCode);
    await saveSetting('active_operator_name', name);
    await saveSetting('active_operator_token', token ?? '');
  }

  @override
  Future<Map<String, String>?> getActiveOperator() async {
    final code = await getSetting('active_operator_code');
    final name = await getSetting('active_operator_name');
    final token = await getSetting('active_operator_token');
    if (code != null && code.isNotEmpty) {
      return {
        'code': code,
        'name': name ?? code,
        if (token != null && token.isNotEmpty) 'token': token,
      };
    }
    return null;
  }

  @override
  Future<void> clearActiveOperator() async {
    await saveSetting('active_operator_code', '');
    await saveSetting('active_operator_name', '');
    await saveSetting('active_operator_token', '');
  }

  @override
  Future<void> saveEmployees(List<Employee> employees) async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final batch = db.batch();
          for (var e in employees) {
            batch.insert(
              'employees',
              {'payroll_code': e.payrollCode, 'name': e.name, 'active': e.active ? 1 : 0},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
          return;
        } catch (e) {
          debugPrint('Error saving employees to sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = employees.map((e) => {
        'payrollCode': e.payrollCode,
        'name': e.name,
        'active': e.active,
      }).toList();
      await prefs.setString('employees_data', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving employees to SharedPreferences: $e');
    }
  }

  @override
  Future<List<Employee>> loadEmployees() async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final raw = await db.query('employees');
          if (raw.isNotEmpty) {
            return raw.map((e) => Employee(
              payrollCode: e['payroll_code'] as String,
              name: e['name'] as String,
              active: (e['active'] as int? ?? 1) == 1,
            )).toList();
          }
        } catch (e) {
          debugPrint('Error reading employees from sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString('employees_data');
      if (content != null && content.isNotEmpty) {
        final List raw = jsonDecode(content);
        return raw.map((e) => Employee(
          payrollCode: e['payrollCode'] ?? '',
          name: e['name'] ?? '',
          active: e['active'] ?? true,
        )).toList();
      }
    } catch (e) {
      debugPrint('Error reading employees from SharedPreferences: $e');
    }

    return defaultEmployees;
  }

  @override
  Future<void> deleteEmployee(String payrollCode) async {
    final cleanCode = payrollCode.trim().toUpperCase();
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          await db.delete('employees', where: 'UPPER(payroll_code) = ?', whereArgs: [cleanCode]);
        } catch (e) {
          debugPrint('Error deleting employee from sqflite: $e');
        }
      }
    }

    try {
      final employees = await loadEmployees();
      employees.removeWhere((e) => e.payrollCode.trim().toUpperCase() == cleanCode);
      await saveEmployees(employees);
    } catch (e) {
      debugPrint('Error deleting employee from SharedPreferences: $e');
    }
  }

  @override
  Future<void> saveGrilles(List<Grille> grilles) async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final batch = db.batch();
          for (var g in grilles) {
            batch.insert(
              'grilles',
              {'code': g.code, 'name': g.name, 'position': g.position},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            for (var f in g.filters) {
              batch.insert(
                'filters',
                {
                  'id': f.id,
                  'grille_code': f.grilleCode,
                  'filter_number': f.filterNumber,
                  'position_label': f.positionLabel,
                  'last_replaced_at': f.lastReplacedAt?.toIso8601String(),
                  'last_employee_code': f.lastEmployeeCode,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
          await batch.commit(noResult: true);
          return;
        } catch (e) {
          debugPrint('Error saving grilles to sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = grilles.map((g) => {
        'code': g.code,
        'name': g.name,
        'position': g.position,
        'filters': g.filters.map((f) => {
          'id': f.id,
          'grille_code': f.grilleCode,
          'filter_number': f.filterNumber,
          'position_label': f.positionLabel,
          'last_replaced_at': f.lastReplacedAt?.toIso8601String(),
          'last_employee_code': f.lastEmployeeCode,
        }).toList(),
      }).toList();
      await prefs.setString('grilles_data', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving grilles to SharedPreferences: $e');
    }
  }

  @override
  Future<List<Grille>> loadCachedGrilles() async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final rawGrilles = await db.query('grilles');
          final rawFilters = await db.query('filters');

          if (rawGrilles.isNotEmpty) {
            Map<String, List<FilterItem>> filtersMap = {};
            for (var f in rawFilters) {
              final gCode = f['grille_code'] as String;
              filtersMap.putIfAbsent(gCode, () => []);
              filtersMap[gCode]!.add(FilterItem(
                id: f['id'] as String,
                grilleCode: gCode,
                filterNumber: f['filter_number'] as int,
                positionLabel: f['position_label'] as String,
                lastReplacedAt: f['last_replaced_at'] != null
                    ? DateTime.tryParse(f['last_replaced_at'] as String)
                    : null,
                lastEmployeeCode: f['last_employee_code'] as String?,
              ));
            }

            List<Grille> list = [];
            for (var g in rawGrilles) {
              final code = g['code'] as String;
              list.add(Grille(
                code: code,
                name: g['name'] as String,
                position: g['position'] as int,
                filters: filtersMap[code] ?? [],
              ));
            }
            if (list.isNotEmpty) return list;
          }
        } catch (e) {
          debugPrint('Error reading grilles from sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString('grilles_data');
      if (content != null && content.isNotEmpty) {
        final List raw = jsonDecode(content);
        return raw.map((g) {
          final List fList = g['filters'] ?? [];
          return Grille(
            code: g['code'] ?? '',
            name: g['name'] ?? '',
            position: g['position'] ?? 0,
            filters: fList.map((f) => FilterItem(
              id: f['id'] ?? '',
              grilleCode: f['grille_code'] ?? '',
              filterNumber: f['filter_number'] ?? 1,
              positionLabel: f['position_label'] ?? '',
              lastReplacedAt: f['last_replaced_at'] != null
                  ? DateTime.tryParse(f['last_replaced_at'])
                  : null,
              lastEmployeeCode: f['last_employee_code'],
            )).toList(),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error reading grilles from SharedPreferences: $e');
    }

    return [];
  }

  @override
  Future<void> savePendingEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime occurredAt,
    String? notes,
  }) async {
    final id = '${grilleCode}_${filterNumber}_${occurredAt.millisecondsSinceEpoch}';
    final eventMap = {
      'id': id,
      'event_id': 'EVT-OFFLINE-${DateTime.now().millisecondsSinceEpoch}-$filterNumber',
      'grille_code': grilleCode,
      'filter_number': filterNumber,
      'payroll_code': payrollCode,
      'occurred_at': occurredAt.toIso8601String(),
      'notes': notes ?? 'Mantenimiento registrado offline',
    };

    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          await db.insert('pending_events', eventMap,
              conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (e) {
          debugPrint('Error inserting pending event in sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getPendingEvents();
      currentList.removeWhere((item) => item['id'] == id);
      currentList.add(eventMap);
      await prefs.setString('pending_events_data', jsonEncode(currentList));
    } catch (e) {
      debugPrint('Error saving pending event to SharedPreferences: $e');
    }

    await updateLocalFilterReplacement(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      replacedAt: occurredAt,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingEvents() async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          final res = await db.query('pending_events');
          if (res.isNotEmpty) return res;
        } catch (e) {
          debugPrint('Error reading pending events from sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString('pending_events_data');
      if (content != null && content.isNotEmpty) {
        final List raw = jsonDecode(content);
        return raw.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error reading pending events from SharedPreferences: $e');
    }

    return [];
  }

  @override
  Future<void> deletePendingEvent(String id) async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          await db.delete('pending_events', where: 'id = ?', whereArgs: [id]);
        } catch (e) {
          debugPrint('Error deleting pending event in sqflite: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getPendingEvents();
      currentList.removeWhere((item) => item['id'] == id);
      await prefs.setString('pending_events_data', jsonEncode(currentList));
    } catch (e) {
      debugPrint('Error deleting pending event in SharedPreferences: $e');
    }
  }

  @override
  Future<void> updateLocalFilterReplacement({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime replacedAt,
  }) async {
    final cached = await loadCachedGrilles();
    if (cached.isEmpty) return;

    for (var g in cached) {
      if (g.code == grilleCode) {
        for (var i = 0; i < g.filters.length; i++) {
          final f = g.filters[i];
          if (f.filterNumber == filterNumber) {
            g.filters[i] = FilterItem(
              id: f.id,
              grilleCode: f.grilleCode,
              filterNumber: f.filterNumber,
              positionLabel: f.positionLabel,
              lastReplacedAt: replacedAt,
              lastEmployeeCode: payrollCode,
            );
          }
        }
      }
    }
    await saveGrilles(cached);
  }

  @override
  Future<void> clearLocalGrillesAndEvents() async {
    if (!kIsWeb) {
      final db = await _database;
      if (db != null) {
        try {
          await db.delete('filters');
          await db.delete('pending_events');
          await db.delete('grilles');
        } catch (e) {
          debugPrint('Error clearing sqflite grilles/events: $e');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('grilles_data');
      await prefs.remove('pending_events_data');
    } catch (e) {
      debugPrint('Error clearing SharedPreferences grilles/events: $e');
    }
  }
}
