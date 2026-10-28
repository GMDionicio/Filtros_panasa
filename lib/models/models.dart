import '../config/business_rules.dart';

class Grille {
  final String code;
  final String name;
  final int position;
  final DateTime? lastMaintenance;
  final List<FilterItem> filters;

  Grille({
    required this.code,
    required this.name,
    required this.position,
    this.lastMaintenance,
    required this.filters,
  });

  /// Determina el bloque (MG-01, MG-02, MG-03) basado en la posición numérica fija (1-22) en SQLite
  String get blockCode {
    int pos = position > 0
        ? position
        : (int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);

    return BusinessRules.getBlockCode(pos);
  }

  String get blockName {
    return BusinessRules.getBlockName(blockCode);
  }

  /// Determina si la rejilla está en la fila superior o inferior basado en la posición (1-22)
  bool get isUpperRow {
    int pos = position > 0
        ? position
        : (int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);

    return BusinessRules.isUpperRow(pos);
  }

  GrilleStatus get status {
    if (filters.isEmpty) return GrilleStatus.ok;
    bool hasRed = false;
    bool hasYellow = false;

    for (var filter in filters) {
      final days = filter.daysSinceReplacement;
      if (days >= BusinessRules.urgentThresholdDays) {
        hasRed = true;
      } else if (days >= BusinessRules.warningThresholdDays) {
        hasYellow = true;
      }
    }

    if (hasRed) return GrilleStatus.urgent;
    if (hasYellow) return GrilleStatus.warning;
    return GrilleStatus.ok;
  }

  int get maxDaysWithoutMaintenance {
    if (filters.isEmpty) return 0;
    int maxDays = 0;
    for (var f in filters) {
      if (f.daysSinceReplacement > maxDays) {
        maxDays = f.daysSinceReplacement;
      }
    }
    return maxDays;
  }

  factory Grille.fromJson(Map<String, dynamic> json) {
    return Grille(
      code: json['grille_code'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? 0,
      filters: [],
    );
  }
}

enum GrilleStatus { ok, warning, urgent }

class FilterItem {
  final String id;
  final String grilleCode;
  final int filterNumber;
  final String positionLabel; // e.g., 'Arriba-Izquierda'
  final DateTime? lastReplacedAt;
  final String? lastEmployeeCode;
  final String? lastEmployeeName;

  FilterItem({
    required this.id,
    required this.grilleCode,
    required this.filterNumber,
    required this.positionLabel,
    this.lastReplacedAt,
    this.lastEmployeeCode,
    this.lastEmployeeName,
  });

  int get daysSinceReplacement {
    if (lastReplacedAt == null) return BusinessRules.defaultDaysIfNeverReplaced; // Default if never replaced
    final diff = DateTime.now().difference(lastReplacedAt!);
    return diff.inDays;
  }

  GrilleStatus get status {
    return BusinessRules.calculateStatusFromDays(daysSinceReplacement);
  }

  factory FilterItem.fromJson(Map<String, dynamic> json) {
    return FilterItem(
      id: json['id'] ?? '',
      grilleCode: json['grille_code'] ?? '',
      filterNumber: json['filter_number'] ?? 1,
      positionLabel: json['position'] ?? '',
    );
  }
}

class Employee {
  final String payrollCode;
  final String name;
  final bool active;

  Employee({
    required this.payrollCode,
    required this.name,
    this.active = true,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      payrollCode: json['payroll_code'] ?? '',
      name: json['name'] ?? '',
      active: (json['active'] ?? 1) == 1,
    );
  }
}

/// Lista por defecto de empleados (vacía en instalaciones limpias hasta registrar personal)
final List<Employee> defaultEmployees = [];

class FilterEvent {
  final String eventId;
  final String grilleCode;
  final int filterNumber;
  final String payrollCode;
  final DateTime occurredAt;
  final String? notes;

  FilterEvent({
    required this.eventId,
    required this.grilleCode,
    required this.filterNumber,
    required this.payrollCode,
    required this.occurredAt,
    this.notes,
  });

  factory FilterEvent.fromJson(Map<String, dynamic> json) {
    return FilterEvent(
      eventId: json['event_id'] ?? '',
      grilleCode: json['grille_code'] ?? '',
      filterNumber: json['filter_number'] ?? 1,
      payrollCode: json['payroll_code'] ?? '',
      occurredAt: DateTime.tryParse(json['occurred_at_ts'] ?? '') ?? DateTime.now(),
      notes: json['notes'],
    );
  }
}

enum EstadoRejilla { operativa, alerta, mantenimiento, apagada }

class CameraState {
  final double camX;
  final double camY;
  final double camZ;
  final double yaw;
  final double pitch;

  const CameraState({
    required this.camX,
    required this.camY,
    required this.camZ,
    required this.yaw,
    required this.pitch,
  });

  CameraState copyWith({
    double? camX,
    double? camY,
    double? camZ,
    double? yaw,
    double? pitch,
  }) {
    return CameraState(
      camX: camX ?? this.camX,
      camY: camY ?? this.camY,
      camZ: camZ ?? this.camZ,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
    );
  }
}

class RejillaModel {
  final int id; // 1 a 22
  final String codigo; // R01 a R22
  final int fila; // 0 = Superior, 1 = Inferior
  final int bloque; // 0 = MG-01 (Izq), 1 = MG-02 (Centro), 2 = MG-03 (Der)
  final int indiceEnFila; // 0 a 10
  final double worldX; // Posición X en el muro 3D
  final double worldY; // Posición Y en el muro 3D
  double temperaturaC;
  double caudalPorcentaje;
  Grille? liveGrille;

  RejillaModel({
    required this.id,
    required this.codigo,
    required this.fila,
    required this.bloque,
    required this.indiceEnFila,
    required this.worldX,
    required this.worldY,
    this.temperaturaC = 38.5,
    this.caudalPorcentaje = 85.0,
    this.liveGrille,
  });

  /// Deriva dinámicamente el estado del modelo inmutable de dominio Grille (SSOT)
  EstadoRejilla get estado {
    if (liveGrille == null) return EstadoRejilla.operativa;
    switch (liveGrille!.status) {
      case GrilleStatus.ok:
        return EstadoRejilla.operativa;
      case GrilleStatus.warning:
        return EstadoRejilla.alerta;
      case GrilleStatus.urgent:
        return EstadoRejilla.mantenimiento;
    }
  }
}

