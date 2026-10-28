import 'package:get_it/get_it.dart';
import '../blocs/grille_cubit.dart';
import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';
import '../repositories/auth_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/grille_repository.dart';
import '../services/sync_manager.dart';

final GetIt getIt = GetIt.instance;

void setupServiceLocator() {
  // Data Sources
  getIt.registerLazySingleton<LocalDataSource>(() => LocalDataSourceImpl());
  getIt.registerLazySingleton<RemoteDataSource>(
    () => RemoteDataSourceImpl(localDataSource: getIt<LocalDataSource>()),
  );

  // Services
  getIt.registerLazySingleton<SyncManager>(
    () => SyncManager(
      localDataSource: getIt<LocalDataSource>(),
      remoteDataSource: getIt<RemoteDataSource>(),
    ),
  );

  // Repositories
  getIt.registerLazySingleton<IGrilleRepository>(
    () => GrilleRepositoryImpl(
      remoteDataSource: getIt<RemoteDataSource>(),
      localDataSource: getIt<LocalDataSource>(),
    ),
  );

  getIt.registerLazySingleton<IEmployeeRepository>(
    () => EmployeeRepositoryImpl(
      remoteDataSource: getIt<RemoteDataSource>(),
      localDataSource: getIt<LocalDataSource>(),
    ),
  );

  getIt.registerLazySingleton<IAuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: getIt<RemoteDataSource>(),
      localDataSource: getIt<LocalDataSource>(),
    ),
  );

  // Cubits
  getIt.registerFactory<GrilleCubit>(
    () => GrilleCubit(
      grilleRepository: getIt<IGrilleRepository>(),
      authRepository: getIt<IAuthRepository>(),
      syncManager: getIt<SyncManager>(),
      localDataSource: getIt<LocalDataSource>(),
    ),
  );
}
