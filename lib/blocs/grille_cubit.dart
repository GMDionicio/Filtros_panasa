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

  GrilleCubit({
    required this.grilleRepository,
    required this.authRepository,
    required this.syncManager,
    required this.localDataSource,
  }) : super(GrilleInitial());

  Future<void> loadGrilles() async {
    if (state is! GrilleLoaded) {
      emit(GrilleLoading());
    }

    try {
      final isHealthOk = await authRepository.checkHealth();
      final grilles = await grilleRepository.getGrilles();
      final pendingList = await localDataSource.getPendingEvents();
      emit(GrilleLoaded(
        grilles: grilles,
        isConnected: isHealthOk,
        pendingCount: pendingList.length,
      ));
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
    await loadGrilles();
  }

  Future<bool> seedDatabase() async {
    emit(GrilleLoading());
    final ok = await grilleRepository.seedDatabase();
    await loadGrilles();
    return ok;
  }
}
