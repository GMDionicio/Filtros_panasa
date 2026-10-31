import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';

class SyncManager {
  final LocalDataSource localDataSource;
  final RemoteDataSource remoteDataSource;
  final Connectivity _connectivity;

  final StreamController<void> _syncStreamController = StreamController<void>.broadcast();
  Stream<void> get onSyncCompleted => _syncStreamController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;

  SyncManager({
    required this.localDataSource,
    required this.remoteDataSource,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  /// Inicializa la escucha de cambios de conectividad para sincronización automática offline -> online
  void initConnectivityListener() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

      if (hasConnection) {
        syncPendingEvents();
      }
    });
  }

  /// Ejecuta la sincronización de eventos pendientes en Android y Web
  Future<void> syncPendingEvents() async {
    if (_isSyncing) return;

    _isSyncing = true;
    int syncedCount = 0;
    try {
      final pending = await localDataSource.getPendingEvents();
      if (pending.isEmpty) {
        return;
      }

      for (var item in pending) {
        final success = await remoteDataSource.syncPendingEvent(item);
        if (success) {
          await localDataSource.deletePendingEvent(item['id']);
          syncedCount++;
          debugPrint('SyncManager: Evento offline ${item['id']} sincronizado con éxito.');
        }
      }
    } catch (e) {
      debugPrint('SyncManager error al sincronizar eventos offline: $e');
    } finally {
      _isSyncing = false;
      if (syncedCount > 0 && !_syncStreamController.isClosed) {
        _syncStreamController.add(null);
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _syncStreamController.close();
  }
}
