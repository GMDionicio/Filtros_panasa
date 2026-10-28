import 'package:flutter/foundation.dart';
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
  Future<bool> seedDatabase();
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

    if (!kIsWeb) {
      await localDataSource.updateLocalFilterReplacement(
        grilleCode: grilleCode,
        filterNumber: filterNumber,
        payrollCode: payrollCode,
        replacedAt: now,
      );
      await localDataSource.savePendingEvent(
        grilleCode: grilleCode,
        filterNumber: filterNumber,
        payrollCode: payrollCode,
        occurredAt: now,
        notes: notes,
      );
      return true;
    }

    return false;
  }

  @override
  Future<bool> seedDatabase() async {
    await localDataSource.clearLocalGrillesAndEvents();
    final cleanMock = _generateMockGrilles();
    await localDataSource.saveGrilles(cleanMock);

    await remoteDataSource.seedBackendDatabase();
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
