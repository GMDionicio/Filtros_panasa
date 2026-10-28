import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';

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
  Future<void> saveActiveOperator(String payrollCode, String name);
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
    final remoteStatus = await remoteDataSource.checkSystemStatus(deviceId: deviceId);

    if (remoteStatus != null) {
      final isServerActivated = remoteStatus['isActivated'] == true;
      if (isServerActivated) {
        await localDataSource.saveSetting('is_activated', 'true');
      }
      return {
        ...remoteStatus,
        'isActivated': isServerActivated || localActivated == 'true',
      };
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
    return await remoteDataSource.validateAdminPin(pin);
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
  Future<void> saveActiveOperator(String payrollCode, String name) async {
    await localDataSource.saveActiveOperator(payrollCode, name);
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
