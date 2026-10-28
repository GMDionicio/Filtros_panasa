import '../models/models.dart';

/// Reglas de Negocio centralizadas para la gestión de rejillas, filtros y bloques
class BusinessRules {
  // Umbrales de mantenimiento en días
  static const int warningThresholdDays = 15;
  static const int urgentThresholdDays = 20;
  static const int defaultDaysIfNeverReplaced = 30;

  // Configuración de catálogo de planta
  static const int totalGrillesCount = 22;
  static const int filtersPerGrille = 4;

  // Mapeo de Posiciones de Filtros por Rejilla
  static const List<String> filterPositions = [
    '1-arriba-izquierda',
    '2-arriba-derecha',
    '3-abajo-derecha',
    '4-abajo-izquierda',
  ];

  /// Determina el código de bloque (MG-01, MG-02, MG-03) basado en la posición (1-22)
  static String getBlockCode(int pos) {
    if (pos >= 1 && pos <= 8) return 'MG-01';
    if (pos >= 9 && pos <= 14) return 'MG-02';
    if (pos >= 15 && pos <= 22) return 'MG-03';
    return 'MG-01';
  }

  /// Retorna la descripción legible del bloque
  static String getBlockName(String blockCode) {
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

  /// Determina si la rejilla se ubica en la fila superior (true) o inferior (false)
  static bool isUpperRow(int pos) {
    if (pos >= 1 && pos <= 4) return true; // MG-01 Superior
    if (pos >= 5 && pos <= 8) return false; // MG-01 Inferior
    if (pos >= 9 && pos <= 11) return true; // MG-02 Superior
    if (pos >= 12 && pos <= 14) return false; // MG-02 Inferior
    if (pos >= 15 && pos <= 18) return true; // MG-03 Superior
    if (pos >= 19 && pos <= 22) return false; // MG-03 Inferior
    return true;
  }

  /// Determina el estado de filtro según días sin reemplazo
  static GrilleStatus calculateStatusFromDays(int days) {
    if (days >= urgentThresholdDays) return GrilleStatus.urgent;
    if (days >= warningThresholdDays) return GrilleStatus.warning;
    return GrilleStatus.ok;
  }
}
