import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/grille_cubit.dart';
import '../models/models.dart';
import 'maintenance_dialog.dart';

class GrilleDetailScreen extends StatefulWidget {
  final Grille grille;

  const GrilleDetailScreen({
    super.key,
    required this.grille,
  });

  @override
  State<GrilleDetailScreen> createState() => _GrilleDetailScreenState();
}

class _GrilleDetailScreenState extends State<GrilleDetailScreen> {
  late Grille _grille;

  @override
  void initState() {
    super.initState();
    _grille = widget.grille;
  }

  Color _getStatusColor(GrilleStatus status) {
    switch (status) {
      case GrilleStatus.ok:
        return const Color(0xFF00E676);
      case GrilleStatus.warning:
        return const Color(0xFFFFD600);
      case GrilleStatus.urgent:
        return const Color(0xFFFF1744);
    }
  }

  String _getStatusText(GrilleStatus status) {
    switch (status) {
      case GrilleStatus.ok:
        return 'Al Día (<15 días)';
      case GrilleStatus.warning:
        return 'Atención Necesaria (≥15 días)';
      case GrilleStatus.urgent:
        return 'Mantenimiento Urgente (≥20 días)';
    }
  }

  Future<void> _openMaintenanceDialog([FilterItem? filter]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MaintenanceDialog(
        grille: _grille,
        selectedFilter: filter,
      ),
    );

    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Mantenimiento registrado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
        context.read<GrilleCubit>().loadGrilles();
        Navigator.of(context).pop(); // Volver al dashboard
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_grille.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Rejilla ${_grille.code}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Banner
            Card(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: statusColor.withValues(alpha: 0.1),
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: Row(
                  children: [
                    Icon(
                      _grille.status == GrilleStatus.ok
                          ? Icons.check_circle
                          : _grille.status == GrilleStatus.warning
                              ? Icons.warning
                              : Icons.error,
                      color: statusColor,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _grille.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getStatusText(_grille.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header for Filter positions
            const Text(
              'Distribución Física de Filtros (4 Secciones)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toca cualquier filtro individual o usa el botón inferior para cambiar todos.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // 2x2 Physical Grid of 4 Filters
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _grille.filters.length,
              itemBuilder: (context, index) {
                final filter = _grille.filters[index];
                final fColor = _getStatusColor(filter.status);
                final days = filter.daysSinceReplacement;

                return InkWell(
                  onTap: () => _openMaintenanceDialog(filter),
                  borderRadius: BorderRadius.circular(12),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: fColor, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: fColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Filtro #${filter.filterNumber}',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.touch_app,
                                size: 16,
                                color: Colors.cyanAccent,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            filter.positionLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$days días transcurridos',
                            style: TextStyle(
                              color: fColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            filter.lastEmployeeCode != null
                                ? 'Por: ${filter.lastEmployeeCode}'
                                : 'Sin registro',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Action Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _openMaintenanceDialog(),
              icon: const Icon(Icons.cleaning_services),
              label: const Text(
                'Registrar Mantenimiento Completo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
