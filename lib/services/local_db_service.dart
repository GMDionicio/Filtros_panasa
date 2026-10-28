import '../datasources/local_data_source.dart';
import '../di/service_locator.dart';
import '../models/models.dart';

/// Fachada de compatibilidad para LocalDbService delegando al LocalDataSource
class LocalDbService {
  static Future<void> saveSetting(String key, String value) async {
    await getIt<LocalDataSource>().saveSetting(key, value);
  }

  static Future<String?> getSetting(String key) async {
    return await getIt<LocalDataSource>().getSetting(key);
  }

  static Future<String> getOrCreateDeviceId() async {
    return await getIt<LocalDataSource>().getOrCreateDeviceId();
  }

  static Future<void> saveActiveOperator(String payrollCode, String name, {String? token}) async {
    await getIt<LocalDataSource>().saveActiveOperator(payrollCode, name, token: token);
  }

  static Future<Map<String, String>?> getActiveOperator() async {
    return await getIt<LocalDataSource>().getActiveOperator();
  }

  static Future<void> clearActiveOperator() async {
    await getIt<LocalDataSource>().clearActiveOperator();
  }

  static Future<void> saveEmployees(List<Employee> employees) async {
    await getIt<LocalDataSource>().saveEmployees(employees);
  }

  static Future<List<Employee>> loadEmployees() async {
    return await getIt<LocalDataSource>().loadEmployees();
  }

  static Future<void> deleteEmployee(String payrollCode) async {
    await getIt<LocalDataSource>().deleteEmployee(payrollCode);
  }

  static Future<void> saveGrilles(List<Grille> grilles) async {
    await getIt<LocalDataSource>().saveGrilles(grilles);
  }

  static Future<List<Grille>> loadCachedGrilles() async {
    return await getIt<LocalDataSource>().loadCachedGrilles();
  }

  static Future<void> savePendingEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime occurredAt,
    String? notes,
  }) async {
    await getIt<LocalDataSource>().savePendingEvent(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      occurredAt: occurredAt,
      notes: notes,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingEvents() async {
    return await getIt<LocalDataSource>().getPendingEvents();
  }

  static Future<void> deletePendingEvent(String id) async {
    await getIt<LocalDataSource>().deletePendingEvent(id);
  }

  static Future<void> updateLocalFilterReplacement({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    required DateTime replacedAt,
  }) async {
    await getIt<LocalDataSource>().updateLocalFilterReplacement(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      replacedAt: replacedAt,
    );
  }

  static Future<void> clearLocalGrillesAndEvents() async {
    await getIt<LocalDataSource>().clearLocalGrillesAndEvents();
  }
}
