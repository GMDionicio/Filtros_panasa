import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../datasources/local_data_source.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/grille_repository.dart';
import '../services/sync_manager.dart';

abstract class GrilleState extends Equatable {
  const GrilleState();

  @override
  List<Object?> get props => [];
}

class GrilleInitial extends GrilleState {}

class GrilleLoading extends GrilleState {}

class GrilleLoaded extends GrilleState {
  final List<Grille> grilles;
  final bool isConnected;
  final int pendingCount;

  const GrilleLoaded({
    required this.grilles,
    required this.isConnected,
    this.pendingCount = 0,
  });

  @override
  List<Object?> get props => [grilles, isConnected, pendingCount];
}

class GrilleError extends GrilleState {
  final String message;

  const GrilleError(this.message);

  @override
  List<Object?> get props => [message];
}

class GrilleCubit extends Cubit<GrilleState> {
  final IGrilleRepository grilleRepository;
  final IAuthRepository authRepository;
  final SyncManager syncManager;
  final LocalDataSource localDataSource;

  StreamSubscription<void>? _syncSubscription;

  GrilleCubit({
    required this.grilleRepository,
    required this.authRepository,
    required this.syncManager,
    required this.localDataSource,
  }) : super(GrilleInitial()) {
    _syncSubscription = syncManager.onSyncCompleted.listen((_) {
      loadGrilles();
    });
  }

  Future<void> loadGrilles() async {
    if (state is! GrilleLoaded) {
      emit(GrilleLoading());
    }

    try {
      final isHealthOk = await authRepository.checkHealth();
      if (isHealthOk) {
        await syncManager.syncPendingEvents();
      }
      final grilles = await grilleRepository.getGrilles();
      final pendingList = await localDataSource.getPendingEvents();
      emit(GrilleLoaded(
        grilles: grilles,
        isConnected: isHealthOk,
        pendingCount: pendingList.length,
      ));

      // FP-SYNC-05: descargar eventos incrementales en background cuando hay conexión
      if (isHealthOk) {
        syncManager.downloadSync();
      }
    } catch (e) {
      final cached = await localDataSource.loadCachedGrilles();
      final pendingList = await localDataSource.getPendingEvents();
      emit(GrilleLoaded(
        grilles: cached,
        isConnected: false,
        pendingCount: pendingList.length,
      ));
    }
  }

  Future<void> syncPendingBatch() async {
    await syncManager.syncPendingEvents();
  }

  /// Descarga forzada de eventos + grilles_status (FP-SYNC-05)
  Future<void> downloadSync({bool force = false}) async {
    await syncManager.downloadSync(force: force);
  }

  Future<bool> seedDatabase(String adminPin) async {
    emit(GrilleLoading());
    final ok = await grilleRepository.seedDatabase(adminPin);
    await loadGrilles();
    return ok;
  }

  @override
  Future<void> close() {
    _syncSubscription?.cancel();
    return super.close();
  }
}
