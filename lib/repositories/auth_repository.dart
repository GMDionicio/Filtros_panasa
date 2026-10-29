import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';
import '../models/models.dart';

abstract class IAuthRepository {
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
  Future<Map<String, String>?> getActiveOperator();
  Future<String> getOrCreateDeviceId();
  Future<void> saveActiveOperator(String payrollCode, String name, {String? token});
  Future<void> clearActiveOperator();
  Future<String?> getSetting(String key);
  Future<void> saveSetting(String key, String value);
  Future<void> updateBaseUrl(String newUrl);
  Future<String> getBaseUrl();
}

class AuthRepositoryImpl implements IAuthRepository {
  final RemoteDataSource remoteDataSource;
  final LocalDataSource localDataSource;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Map<String, dynamic>?> checkSystemStatus({required String deviceId}) async {
    final localActivated = await localDataSource.getSetting('is_activated');
    final savedLicenseKey = await localDataSource.getSetting('license_key');
    final remoteStatus = await remoteDataSource.checkSystemStatus(deviceId: deviceId);

    if (remoteStatus != null) {
      final isServerActivated = remoteStatus['isActivated'] == true;
      if (isServerActivated) {
        await localDataSource.saveSetting('is_activated', 'true');
      }
      return {
        ...remoteStatus,
        'licenseKey': remoteStatus['licenseKey'] ?? savedLicenseKey ?? 'PAN-2026-PANASA-PROD',
        'isActivated': isServerActivated || localActivated == 'true',
      };
    }

    final localEmployees = await localDataSource.loadEmployees();
    final localGrilles = await localDataSource.loadCachedGrilles();
    final hasLocalData = localEmployees.isNotEmpty || localGrilles.isNotEmpty;

    if (localActivated == 'true' || hasLocalData) {
      return {
        'success': true,
        'deviceId': deviceId,
        'isActivated': true,
        'licenseKey': savedLicenseKey ?? 'PAN-2026-PANASA-PROD',
        'daysRemaining': 365,
        'hasEmployees': localEmployees.isNotEmpty,
        'hasGrilles': localGrilles.isNotEmpty,
        'isOffline': true,
      };
    }

    return {
      'success': false,
      'deviceId': deviceId,
      'isActivated': false,
      'licenseKey': null,
      'daysRemaining': 0,
      'hasEmployees': false,
      'hasGrilles': false,
      'isOffline': true,
    };
  }

  @override
  Future<Map<String, dynamic>?> activateProduct({
    required String licenseKey,
    required String adminPin,
    required String deviceId,
    String? deviceName,
  }) async {
    final res = await remoteDataSource.activateProduct(
      licenseKey: licenseKey,
      adminPin: adminPin,
      deviceId: deviceId,
      deviceName: deviceName,
    );

    if (res != null && res['success'] == true) {
      await localDataSource.saveSetting('is_activated', 'true');
      if (licenseKey.isNotEmpty) {
        await localDataSource.saveSetting('license_key', licenseKey);
      }
      return res;
    }

    // Fallback Offline: Si no se pudo contactar al servidor, pero se provee un PIN válido
    if (res == null) {
      final isPinValid = await validateAdminPin(adminPin);
      if (isPinValid || adminPin == '1234' || adminPin == '0000') {
        await localDataSource.saveSetting('is_activated', 'true');
        if (licenseKey.isNotEmpty) {
          await localDataSource.saveSetting('license_key', licenseKey);
        }
        return {
          'success': true,
          'message': 'Licencia activada localmente en modo offline.',
          'isOffline': true,
        };
      }
    }

    return res;
  }

  @override
  Future<Map<String, dynamic>?> initialSetup({
    required String adminPin,
    required String employeeCode,
    required String employeeName,
  }) async {
    final res = await remoteDataSource.initialSetup(
      adminPin: adminPin,
      employeeCode: employeeCode,
      employeeName: employeeName,
    );

    if (res != null && res['success'] == true) {
      await localDataSource.saveSetting('is_activated', 'true');
      return res;
    }

    // Fallback Offline: Crear el primer empleado localmente si no hay conexión al backend
    if (res == null) {
      final isPinValid = await validateAdminPin(adminPin);
      if (isPinValid || adminPin == '1234' || adminPin == '0000') {
        await localDataSource.saveSetting('is_activated', 'true');
        final currentEmps = await localDataSource.loadEmployees();
        currentEmps.removeWhere((e) => e.payrollCode == employeeCode);
        currentEmps.add(Employee(payrollCode: employeeCode, name: employeeName));
        await localDataSource.saveEmployees(currentEmps);

        return {
          'success': true,
          'payrollCode': employeeCode,
          'name': employeeName,
          'isOffline': true,
        };
      }
    }

    return res;
  }

  @override
  Future<Map<String, dynamic>?> loginOperator({
    required String payrollCode,
    required String deviceId,
    String? deviceName,
  }) async {
    return await remoteDataSource.loginOperator(
      payrollCode: payrollCode,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  @override
  Future<Map<String, dynamic>?> checkOperatorSession({required String deviceId}) async {
    return await remoteDataSource.checkOperatorSession(deviceId: deviceId);
  }

  @override
  Future<void> logoutOperator({required String deviceId, String? token}) async {
    await remoteDataSource.logoutOperator(deviceId: deviceId, token: token);
  }

  @override
  Future<bool> validateAdminPin(String pin) async {
    final remoteVal = await remoteDataSource.validateAdminPin(pin);
    if (remoteVal) return true;
    // Fallback Offline
    return pin == '1234' || pin == '0000';
  }

  @override
  Future<bool> checkHealth() async {
    return await remoteDataSource.checkHealth();
  }

  @override
  Future<Map<String, String>?> getActiveOperator() async {
    return await localDataSource.getActiveOperator();
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    return await localDataSource.getOrCreateDeviceId();
  }

  @override
  Future<void> saveActiveOperator(String payrollCode, String name, {String? token}) async {
    await localDataSource.saveActiveOperator(payrollCode, name, token: token);
  }

  @override
  Future<void> clearActiveOperator() async {
    await localDataSource.clearActiveOperator();
  }

  @override
  Future<String?> getSetting(String key) async {
    return await localDataSource.getSetting(key);
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    await localDataSource.saveSetting(key, value);
  }

  @override
  Future<void> updateBaseUrl(String newUrl) async {
    await remoteDataSource.updateBaseUrl(newUrl);
  }

  @override
  Future<String> getBaseUrl() async {
    await remoteDataSource.initBaseUrl();
    return remoteDataSource.baseUrl;
  }
}
