import '../datasources/remote_data_source.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/grille_repository.dart';
import 'sync_manager.dart';

/// Fachada de compatibilidad para ApiService delegando a la arquitectura de Repositorios y Data Sources
class ApiService {
  static String get defaultBaseUrl => RemoteDataSourceImpl.defaultBaseUrl;

  static String sanitizeUrl(String raw) => RemoteDataSourceImpl.sanitizeUrl(raw);

  static String get baseUrl => getIt<RemoteDataSource>().baseUrl;

  static Future<void> initBaseUrl() async {
    await getIt<RemoteDataSource>().initBaseUrl();
  }

  static Future<void> updateBaseUrl(String newUrl) async {
    await getIt<IAuthRepository>().updateBaseUrl(newUrl);
  }

  static Future<Map<String, dynamic>?> checkSystemStatus({required String deviceId}) async {
    return await getIt<IAuthRepository>().checkSystemStatus(deviceId: deviceId);
  }

  static Future<Map<String, dynamic>?> activateProduct({
    required String licenseKey,
    required String adminPin,
    required String deviceId,
    String? deviceName,
  }) async {
    return await getIt<IAuthRepository>().activateProduct(
      licenseKey: licenseKey,
      adminPin: adminPin,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  static Future<Map<String, dynamic>?> initialSetup({
    required String adminPin,
    required String employeeCode,
    required String employeeName,
  }) async {
    return await getIt<IAuthRepository>().initialSetup(
      adminPin: adminPin,
      employeeCode: employeeCode,
      employeeName: employeeName,
    );
  }

  static Future<Map<String, dynamic>?> loginOperator({
    required String payrollCode,
    required String deviceId,
    String? deviceName,
  }) async {
    return await getIt<IAuthRepository>().loginOperator(
      payrollCode: payrollCode,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  static Future<Map<String, dynamic>?> checkOperatorSession({required String deviceId}) async {
    return await getIt<IAuthRepository>().checkOperatorSession(deviceId: deviceId);
  }

  static Future<void> logoutOperator({required String deviceId, String? token}) async {
    await getIt<IAuthRepository>().logoutOperator(deviceId: deviceId, token: token);
  }

  static Future<bool> validateAdminPin(String pin) async {
    return await getIt<IAuthRepository>().validateAdminPin(pin);
  }

  static Future<bool> checkHealth() async {
    return await getIt<IAuthRepository>().checkHealth();
  }

  static Future<bool> seedDatabase(String adminPin) async {
    return await getIt<IGrilleRepository>().seedDatabase(adminPin);
  }

  static Future<void> syncPendingEvents() async {
    await getIt<SyncManager>().syncPendingEvents();
  }

  static Future<List<Grille>> getGrilles() async {
    return await getIt<IGrilleRepository>().getGrilles();
  }

  static Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  }) async {
    return await getIt<IGrilleRepository>().registerEvent(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      notes: notes,
    );
  }

  static Future<List<Employee>> getEmployees() async {
    return await getIt<IEmployeeRepository>().getEmployees();
  }

  static Future<bool> addEmployee(String payrollCode, String name) async {
    return await getIt<IEmployeeRepository>().addEmployee(payrollCode, name);
  }

  static Future<bool> deleteEmployee(String payrollCode) async {
    return await getIt<IEmployeeRepository>().deleteEmployee(payrollCode);
  }

  static Future<bool> restoreDataFromBackend({String? deviceId, String? licenseKey}) async {
    return await getIt<IGrilleRepository>().restoreDataFromBackend(
      deviceId: deviceId,
      licenseKey: licenseKey,
    );
  }
}
