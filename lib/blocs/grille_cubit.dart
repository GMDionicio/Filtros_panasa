import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';

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
  GrilleCubit() : super(GrilleInitial());

  Future<void> loadGrilles() async {
    if (state is! GrilleLoaded) {
      emit(GrilleLoading());
    }
    
    try {
      final isHealthOk = await ApiService.checkHealth();
      final grilles = await ApiService.getGrilles();
      final pendingList = await LocalDbService.getPendingEvents();
      emit(GrilleLoaded(
        grilles: grilles,
        isConnected: isHealthOk,
        pendingCount: pendingList.length,
      ));
    } catch (e) {
      final cached = await LocalDbService.loadCachedGrilles();
      final pendingList = await LocalDbService.getPendingEvents();
      emit(GrilleLoaded(
        grilles: cached,
        isConnected: false,
        pendingCount: pendingList.length,
      ));
    }
  }

  Future<void> syncPendingBatch() async {
    await ApiService.syncPendingEvents();
    await loadGrilles();
  }

  Future<bool> seedDatabase() async {
    emit(GrilleLoading());
    final ok = await ApiService.seedDatabase();
    await loadGrilles();
    return ok;
  }
}
