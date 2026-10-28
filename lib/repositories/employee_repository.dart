import 'package:flutter/foundation.dart';
import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';
import '../models/models.dart';

abstract class IEmployeeRepository {
  Future<List<Employee>> getEmployees();
  Future<bool> addEmployee(String payrollCode, String name);
  Future<bool> deleteEmployee(String payrollCode);
}

class EmployeeRepositoryImpl implements IEmployeeRepository {
  final RemoteDataSource remoteDataSource;
  final LocalDataSource localDataSource;

  EmployeeRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<List<Employee>> getEmployees() async {
    final employees = await remoteDataSource.getEmployees();
    if (employees != null) {
      await localDataSource.saveEmployees(employees);
      return employees;
    }
    return await localDataSource.loadEmployees();
  }

  @override
  Future<bool> addEmployee(String payrollCode, String name) async {
    final remoteSuccess = await remoteDataSource.addEmployee(payrollCode, name);

    // Si la API remota responde con éxito o si falla (ej. error de servidor/CORS/offline),
    // se guarda localmente (SQLite en móvil/escritorio o SharedPreferences en Web)
    final newEmp = Employee(payrollCode: payrollCode, name: name);
    final current = await localDataSource.loadEmployees();
    current.removeWhere((e) => e.payrollCode == payrollCode);
    current.add(newEmp);
    await localDataSource.saveEmployees(current);
    return true;
  }

  @override
  Future<bool> deleteEmployee(String payrollCode) async {
    final cleanCode = payrollCode.trim();
    await remoteDataSource.deleteEmployee(cleanCode);

    // Se elimina de la persistencia local (SQLite o SharedPreferences)
    await localDataSource.deleteEmployee(cleanCode);
    return true;
  }
}
