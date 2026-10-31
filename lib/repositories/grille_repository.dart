import '../config/business_rules.dart';
import '../datasources/local_data_source.dart';
import '../datasources/remote_data_source.dart';
import '../models/models.dart';

abstract class IGrilleRepository {
  Future<List<Grille>> getGrilles();
  Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  });
  Future<bool> seedDatabase(String adminPin);
  Future<bool> restoreDataFromBackend({String? deviceId, String? licenseKey});
}

class GrilleRepositoryImpl implements IGrilleRepository {
  final RemoteDataSource remoteDataSource;
  final LocalDataSource localDataSource;

  GrilleRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<List<Grille>> getGrilles() async {
    // Intentar sync/download (endpoint unificado FP-SYNC-04)
    final syncData = await remoteDataSource.downloadSync();

    if (syncData != null) {
      final List rawEvents = syncData['events'] ?? [];
      final List rawGrillesStatus = syncData['grilles_status'] ?? [];

      // Construir mapa grille_code -> lista de filtros con su estado
      Map<String, List<Map<String, dynamic>>> grilleFiltersMap = {};
      for (var gs in rawGrillesStatus) {
        final gCode = gs['grille_code'] as String? ?? '';
        grilleFiltersMap.putIfAbsent(gCode, () => []);
        grilleFiltersMap[gCode]!.add(gs);
      }

      List<Grille> grilles = [];
      for (var gCode in grilleFiltersMap.keys) {
        final filtersList = grilleFiltersMap[gCode]!;
        if (filtersList.isEmpty) continue;

        final firstFilter = filtersList.first;
        final name = firstFilter['name'] ?? 'Rejilla $gCode';
        final position = (firstFilter['position'] ?? 0) as int;

        List<FilterItem> filterItems = [];
        for (var f in filtersList) {
          final fNum = (f['filter_number'] ?? 1) as int;
          final positionLabel = f['position_label'] as String? ?? '';
          final lastReplacement = f['last_replacement'];
          final daysSince = (f['days_since_replacement'] ?? 30) as int;

          // Buscar evento más reciente para este grille+filter
          FilterEvent? latestEvent;
          for (var e in rawEvents) {
            if ((e['grille_code'] ?? e['grilleCode']) == gCode &&
                (e['filter_number'] ?? e['filterNumber']) == fNum) {
              final ev = FilterEvent.fromJson(e);
              if (latestEvent == null || ev.occurredAt.isAfter(latestEvent.occurredAt)) {
                latestEvent = ev;
              }
            }
          }

          filterItems.add(FilterItem(
            id: '${gCode}_$fNum',
            grilleCode: gCode,
            filterNumber: fNum,
            positionLabel: positionLabel.isNotEmpty ? positionLabel : BusinessRules.filterPositions[fNum - 1],
            lastReplacedAt: latestEvent?.occurredAt,
            lastEmployeeCode: latestEvent?.payrollCode,
          ));
        }

        grilles.add(Grille(
          code: gCode,
          name: name,
          position: position,
          filters: filterItems,
        ));
      }

      // Ordenar por posición
      grilles.sort((a, b) => a.position.compareTo(b.position));

      // Fusionar eventos pendientes locales
      final pendingList = await localDataSource.getPendingEvents();
      if (pendingList.isNotEmpty) {
        for (var p in pendingList) {
          final gCode = p['grille_code'] as String?;
          final fNum = p['filter_number'] as int?;
          final empCode = p['payroll_code'] as String?;
          final occAtStr = p['occurred_at'] as String?;

          if (gCode != null && fNum != null && occAtStr != null) {
            final occAt = DateTime.tryParse(occAtStr);
            final gIndex = grilles.indexWhere((g) => g.code == gCode);
            if (gIndex != -1) {
              final fIndex = grilles[gIndex].filters.indexWhere((f) => f.filterNumber == fNum);
              if (fIndex != -1) {
                final currentFilter = grilles[gIndex].filters[fIndex];
                if (occAt != null &&
                    (currentFilter.lastReplacedAt == null ||
                        occAt.isAfter(currentFilter.lastReplacedAt!))) {
                  grilles[gIndex].filters[fIndex] = FilterItem(
                    id: currentFilter.id,
                    grilleCode: currentFilter.grilleCode,
                    filterNumber: currentFilter.filterNumber,
                    positionLabel: currentFilter.positionLabel,
                    lastReplacedAt: occAt,
                    lastEmployeeCode: empCode,
                    lastEmployeeName: currentFilter.lastEmployeeName,
                  );
                }
              }
            }
          }
        }
      }

      if (grilles.isNotEmpty) {
        await localDataSource.saveGrilles(grilles);
        return grilles;
      }
    }

    // Fallback: fetchGrillesAndEvents (vías antiguas GET /api/grilles + /api/events)
    final remoteData = await remoteDataSource.fetchGrillesAndEvents();

    if (remoteData != null) {
      final List rawGrilles = remoteData['grilles'] ?? [];
      final List rawEvents = remoteData['events'] ?? [];

      Map<String, FilterEvent> latestEvents = {};
      for (var e in rawEvents) {
        final event = FilterEvent.fromJson(e);
        final key = '${event.grilleCode}_${event.filterNumber}';
        if (!latestEvents.containsKey(key) ||
            event.occurredAt.isAfter(latestEvents[key]!.occurredAt)) {
          latestEvents[key] = event;
        }
      }

      List<Grille> grilles = [];

      for (var g in rawGrilles) {
        final code = g['grille_code'] ?? '';
        List<FilterItem> filterItems = [];

        for (int j = 1; j <= BusinessRules.filtersPerGrille; j++) {
          final key = '${code}_$j';
          final lastEv = latestEvents[key];
          filterItems.add(FilterItem(
            id: key,
            grilleCode: code,
            filterNumber: j,
            positionLabel: BusinessRules.filterPositions[j - 1],
            lastReplacedAt: lastEv?.occurredAt,
            lastEmployeeCode: lastEv?.payrollCode,
          ));
        }

        grilles.add(Grille(
          code: code,
          name: g['name'] ?? 'Rejilla $code',
          position: g['position'] ?? 0,
          filters: filterItems,
        ));
      }

      // Fusionar eventos pendientes locales que aún no se han enviado al servidor
      final pendingList = await localDataSource.getPendingEvents();
      if (pendingList.isNotEmpty) {
        for (var p in pendingList) {
          final gCode = p['grille_code'] as String?;
          final fNum = p['filter_number'] as int?;
          final empCode = p['payroll_code'] as String?;
          final occAtStr = p['occurred_at'] as String?;

          if (gCode != null && fNum != null && occAtStr != null) {
            final occAt = DateTime.tryParse(occAtStr);
            final gIndex = grilles.indexWhere((g) => g.code == gCode);
            if (gIndex != -1) {
              final fIndex = grilles[gIndex].filters.indexWhere((f) => f.filterNumber == fNum);
              if (fIndex != -1) {
                final currentFilter = grilles[gIndex].filters[fIndex];
                if (occAt != null &&
                    (currentFilter.lastReplacedAt == null ||
                        occAt.isAfter(currentFilter.lastReplacedAt!))) {
                  grilles[gIndex].filters[fIndex] = FilterItem(
                    id: currentFilter.id,
                    grilleCode: currentFilter.grilleCode,
                    filterNumber: currentFilter.filterNumber,
                    positionLabel: currentFilter.positionLabel,
                    lastReplacedAt: occAt,
                    lastEmployeeCode: empCode,
                    lastEmployeeName: currentFilter.lastEmployeeName,
                  );
                }
              }
            }
          }
        }
      }

      if (grilles.isNotEmpty) {
        await localDataSource.saveGrilles(grilles);
        return grilles;
      }
    }

    // Fallback: local cache
    final cached = await localDataSource.loadCachedGrilles();
    if (cached.isNotEmpty) {
      return cached;
    }

    final mock = _generateMockGrilles();
    await localDataSource.saveGrilles(mock);
    return mock;
  }

  @override
  Future<bool> registerEvent({
    required String grilleCode,
    required int filterNumber,
    required String payrollCode,
    String? notes,
  }) async {
    final now = DateTime.now();
    final remoteSuccess = await remoteDataSource.registerEvent(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      notes: notes,
    );

    if (remoteSuccess) {
      await localDataSource.updateLocalFilterReplacement(
        grilleCode: grilleCode,
        filterNumber: filterNumber,
        payrollCode: payrollCode,
        replacedAt: now,
      );
      return true;
    }

    // Outbox persistente en web: SharedPreferences funciona en todos los targets.
    // savePendingEvent ya maneja el fallback SQLite→SharedPreferences internamente.
    await localDataSource.savePendingEvent(
      grilleCode: grilleCode,
      filterNumber: filterNumber,
      payrollCode: payrollCode,
      occurredAt: now,
      notes: notes,
    );
    return true;
  }

  @override
  Future<bool> seedDatabase(String adminPin) async {
    final okRemote = await remoteDataSource.seedBackendDatabase(adminPin);
    if (!okRemote) {
      return false;
    }

    await localDataSource.clearLocalGrillesAndEvents();
    final cleanMock = _generateMockGrilles();
    await localDataSource.saveGrilles(cleanMock);

    await getGrilles();
    return true;
  }

  @override
  Future<bool> restoreDataFromBackend({String? deviceId, String? licenseKey}) async {
    final body = await remoteDataSource.restoreDataFromBackend(
      deviceId: deviceId,
      licenseKey: licenseKey,
    );

    if (body != null && body['success'] == true && body['data'] != null) {
      final data = body['data'];
      if (data['employees'] != null) {
        final List empList = data['employees'];
        final employees = empList.map((e) => Employee.fromJson(e)).toList();
        await localDataSource.saveEmployees(employees);
      }
      await getGrilles();
      return true;
    }
    return false;
  }

  List<Grille> _generateMockGrilles() {
    List<Grille> list = [];
    for (int i = 1; i <= BusinessRules.totalGrillesCount; i++) {
      final code = 'R${i.toString().padLeft(2, '0')}';
      list.add(Grille(
        code: code,
        name: 'Rejilla $code',
        position: i,
        filters: List.generate(
          BusinessRules.filtersPerGrille,
          (j) => FilterItem(
            id: '${code}_${j + 1}',
            grilleCode: code,
            filterNumber: j + 1,
            positionLabel: BusinessRules.filterPositions[j],
            lastReplacedAt: null,
            lastEmployeeCode: null,
          ),
        ),
      ));
    }
    return list;
  }
}
