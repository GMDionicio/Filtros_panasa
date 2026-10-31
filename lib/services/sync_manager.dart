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

  /// Descarga incremental de eventos + grilles_status usando el cursor last_download.
  /// Usa FP-SYNC-04 endpoint POST /api/sync/download con since=last_download.
  Future<void> downloadSync({bool force = false}) async {
    if (kIsWeb) return;
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      // Determinar el cutoff: last_download guardado localmente o hace 7 días por defecto
      String? since;
      if (!force) {
        final lastDownload = await localDataSource.getSetting('last_sync_download');
        if (lastDownload != null && lastDownload.isNotEmpty) {
          since = lastDownload;
        } else {
          // Primer sync: bajar 7 días de eventos
          since = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
        }
      }

      debugPrint('SyncManager: Iniciando downloadSync (force=$force, since=$since)');

      final result = await remoteDataSource.downloadSync(since: since);
      if (result != null) {
        final downloadedAt = result['downloaded_at'] as String?;
        if (downloadedAt != null && downloadedAt.isNotEmpty) {
          await localDataSource.saveSetting('last_sync_download', downloadedAt);
        }
        final cutoff = result['cutoff_used'];
        final eventCount = (result['events'] as List).length;
        final grilleCount = (result['grilles_status'] as List).length;
        debugPrint('SyncManager: downloadSync completado — events=$eventCount, grilles_status=$grilleCount, cutoff=$cutoff');
      } else {
        debugPrint('SyncManager: downloadSync devolvió null (sin cambios o error)');
      }
    } catch (e) {
      debugPrint('SyncManager error en downloadSync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _syncStreamController.close();
  }
}
