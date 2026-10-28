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

    if (pos >= 1 && pos <= 8) return 'MG-01';
    if (pos >= 9 && pos <= 14) return 'MG-02';
    if (pos >= 15 && pos <= 22) return 'MG-03';
    return 'MG-01';
  }

  String get blockName {
    switch (blockCode) {
      case 'MG-01':
        return 'Bloque Izquierdo (MG-01)';
      case 'MG-02':
        return 'Bloque Centro (MG-02)';
      case 'MG-03':
        return 'Bloque Derecho (MG-03)';
      default:
        return blockCode;
    }
  }

  /// Determina si la rejilla está en la fila superior o inferior basado en la posición (1-22)
  bool get isUpperRow {
    int pos = position > 0
        ? position
        : (int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);

    if (pos >= 1 && pos <= 4) return true; // MG-01 Superior
    if (pos >= 5 && pos <= 8) return false; // MG-01 Inferior
    if (pos >= 9 && pos <= 11) return true; // MG-02 Superior
    if (pos >= 12 && pos <= 14) return false; // MG-02 Inferior
    if (pos >= 15 && pos <= 18) return true; // MG-03 Superior
    if (pos >= 19 && pos <= 22) return false; // MG-03 Inferior
    return true;
  }

  GrilleStatus get status {
    if (filters.isEmpty) return GrilleStatus.ok;
    bool hasRed = false;
    bool hasYellow = false;

    for (var filter in filters) {
      final days = filter.daysSinceReplacement;
      if (days >= 20) {
        hasRed = true;
      } else if (days >= 15) {
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
    if (lastReplacedAt == null) return 30; // Default if never replaced
    final diff = DateTime.now().difference(lastReplacedAt!);
    return diff.inDays;
  }

  GrilleStatus get status {
    final days = daysSinceReplacement;
    if (days >= 20) return GrilleStatus.urgent;
    if (days >= 15) return GrilleStatus.warning;
    return GrilleStatus.ok;
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
