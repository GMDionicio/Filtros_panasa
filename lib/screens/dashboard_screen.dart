import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/grille_cubit.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/initial_setup_dialog.dart';
import '../widgets/operator_login_dialog.dart';
import '../widgets/product_activation_dialog.dart';
import 'grille_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _searchQuery = '';
  GrilleStatus? _selectedStatusFilter;
  Timer? _debounceTimer;
  Map<String, String>? _activeOperator;

  // Cache para memoización de filtrado de rejillas
  List<Grille>? _lastInput;
  String? _lastQuery;
  GrilleStatus? _lastFilter;
  List<Grille> _cachedFilteredList = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOperatorLogin();
    });
  }

  Future<void> _checkOperatorLogin() async {
    const deviceId = 'WEB-DEVICE-001';

    // 1. Consultar estado general del sistema
    final status = await ApiService.checkSystemStatus(deviceId: deviceId);
    if (!mounted) return;

    // 2. Si el producto NO está activado, exigir activación por Licencia + PIN Admin
    bool isActivated = status?['isActivated'] == true;
    while (!isActivated && mounted) {
      isActivated = await ProductActivationDialog.show(context, deviceId: deviceId);
    }
    if (!mounted) return;

    // 3. Si no existen operarios creados en el sistema, ejecutar Onboarding / Configuración Inicial
    bool hasEmployees = status?['hasEmployees'] == true;
    if (!hasEmployees && mounted) {
      final setupResult = await InitialSetupDialog.show(context);
      if (setupResult != null && mounted) {
        setState(() => _activeOperator = setupResult);
        context.read<GrilleCubit>().loadGrilles();
        return;
      }
    }
    if (!mounted) return;

    // 4. Verificar si existe sesión de operario activa en servidor online
    final onlineSession = await ApiService.checkOperatorSession(deviceId: deviceId);
    if (onlineSession != null && onlineSession['active'] == true && mounted) {
      final code = onlineSession['payrollCode'] as String;
      final name = onlineSession['name'] as String;
      await LocalDbService.saveActiveOperator(code, name);
      setState(() => _activeOperator = {'code': code, 'name': name});
      return;
    }

    // 5. Verificar sesión guardada localmente o pedir Login de Operario
    final active = await LocalDbService.getActiveOperator();
    if (mounted) {
      if (active != null) {
        setState(() => _activeOperator = active);
      } else {
        Map<String, String>? result;
        while (result == null && mounted) {
          result = await OperatorLoginDialog.show(context, canDismiss: false);
        }
        if (result != null && mounted) {
          setState(() => _activeOperator = result);
        }
      }
    }
  }

  Future<void> _openOperatorLogin() async {
    final canDismiss = _activeOperator != null;
    final result = await OperatorLoginDialog.show(context, canDismiss: canDismiss);
    if (result != null && mounted) {
      setState(() => _activeOperator = result);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Color _getStatusColor(GrilleStatus status) {
    switch (status) {
      case GrilleStatus.ok:
        return const Color(0xFF00E676); // Vivid Green
      case GrilleStatus.warning:
        return const Color(0xFFFFD600); // Vivid Yellow
      case GrilleStatus.urgent:
        return const Color(0xFFFF1744); // Vivid Red
    }
  }

  List<Grille> _filterList(List<Grille> input) {
    if (identical(input, _lastInput) &&
        _searchQuery == _lastQuery &&
        _selectedStatusFilter == _lastFilter) {
      return _cachedFilteredList;
    }

    _lastInput = input;
    _lastQuery = _searchQuery;
    _lastFilter = _selectedStatusFilter;

    List<Grille> list = List.from(input);
    if (_selectedStatusFilter != null) {
      list = list.where((g) => g.status == _selectedStatusFilter).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list
          .where((g) =>
              g.code.toLowerCase().contains(q) ||
              g.name.toLowerCase().contains(q))
          .toList();
    }

    _cachedFilteredList = list;
    return _cachedFilteredList;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return BlocBuilder<GrilleCubit, GrilleState>(
      builder: (context, state) {
        final isLoading = state is GrilleLoading || state is GrilleInitial;
        final allGrilles = state is GrilleLoaded ? state.grilles : <Grille>[];
        final isConnected = state is GrilleLoaded ? state.isConnected : false;
        final pendingCount = state is GrilleLoaded ? state.pendingCount : 0;

        final countOk =
            allGrilles.where((g) => g.status == GrilleStatus.ok).length;
        final countWarning =
            allGrilles.where((g) => g.status == GrilleStatus.warning).length;
        final countUrgent =
            allGrilles.where((g) => g.status == GrilleStatus.urgent).length;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: const Color(0xFF12161A),
            appBar: AppBar(
              title: const Text(
                'Filtros Panasa — Elevación 2D',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              backgroundColor: const Color(0xFF1B2228),
              foregroundColor: Colors.white,
              actions: [
                InkWell(
                  onTap: _openOperatorLogin,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _activeOperator != null ? Colors.cyan.shade900 : Colors.blueGrey.shade900,
                      border: Border.all(color: _activeOperator != null ? Colors.cyanAccent : Colors.white24),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Text(
                          _activeOperator != null ? _activeOperator!['code']! : 'Ingresar',
                          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? (pendingCount > 0
                            ? Colors.amber.shade900
                            : Colors.green.shade800)
                        : (pendingCount > 0
                            ? Colors.orange.shade900
                            : Colors.blueGrey.shade800),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isConnected ? Icons.wifi : Icons.sd_storage,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConnected
                            ? (pendingCount > 0
                                ? 'Sincronizando ($pendingCount)'
                                : 'API Local')
                            : (pendingCount > 0
                                ? 'Modo Local ($pendingCount pend.)'
                                : 'Modo Local'),
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<GrilleCubit>().loadGrilles(),
                  tooltip: 'Actualizar',
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                indicatorColor: Colors.cyanAccent,
                indicatorWeight: 3,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white70,
                labelStyle:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(text: '🏢 Vista Fachada Real'),
                  Tab(text: '◀️ MG-01 (Izquierdo)'),
                  Tab(text: '⏺️ MG-02 (Centro)'),
                  Tab(text: '▶️ MG-03 (Derecho)'),
                ],
              ),
            ),
            drawer: const AppDrawer(currentRoute: '2d'),
            body: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Responsive Banner
                      if (!isLandscape) ...[
                        Container(
                          color: const Color(0xFF1B2228),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _buildSummaryCard(
                                      'Al Día (<15d)',
                                      countOk,
                                      const Color(0xFF00E676),
                                      GrilleStatus.ok),
                                  const SizedBox(width: 8),
                                  _buildSummaryCard(
                                      'Atención (≥15d)',
                                      countWarning,
                                      const Color(0xFFFFD600),
                                      GrilleStatus.warning),
                                  const SizedBox(width: 8),
                                  _buildSummaryCard(
                                      'Urgente (≥20d)',
                                      countUrgent,
                                      const Color(0xFFFF1744),
                                      GrilleStatus.urgent),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildSearchField(),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Ultra Compact Horizontal Banner in Landscape
                        Container(
                          color: const Color(0xFF1B2228),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              _buildMiniBadge('Al Día (<15d)', countOk,
                                  const Color(0xFF00E676)),
                              const SizedBox(width: 6),
                              _buildMiniBadge('Atención (≥15d)', countWarning,
                                  const Color(0xFFFFD600)),
                              const SizedBox(width: 6),
                              _buildMiniBadge('Urgente (≥20d)', countUrgent,
                                  const Color(0xFFFF1744)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildSearchField()),
                            ],
                          ),
                        ),
                      ],

                      // Tab Views
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildFacadeViewAll(allGrilles),
                            _buildSingleBlockView('MG-01', allGrilles),
                            _buildSingleBlockView('MG-02', allGrilles),
                            _buildSingleBlockView('MG-03', allGrilles),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Buscar por código (ej. R01, R15)...',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon:
            const Icon(Icons.search, color: Colors.cyanAccent, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                onPressed: () {
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
      ),
      onChanged: (val) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() => _searchQuery = val);
          }
        });
      },
    );
  }

  Widget _buildMiniBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count ',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: color),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  // Full Facade View representing the 3 Blocks (MG-01, MG-02, MG-03)
  Widget _buildFacadeViewAll(List<Grille> allGrilles) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildBlockCard('MG-01', 'Bloque Izquierdo (MG-01)',
            'R01 a R08 (8 Rejillas)', allGrilles),
        _buildBlockCard('MG-02', 'Bloque Centro (MG-02)',
            'R09 a R14 (6 Rejillas)', allGrilles),
        _buildBlockCard('MG-03', 'Bloque Derecho (MG-03)',
            'R15 a R22 (8 Rejillas)', allGrilles),
      ],
    );
  }

  // Single Block View for tabs
  Widget _buildSingleBlockView(String blockCode, List<Grille> allGrilles) {
    String title = blockCode == 'MG-01'
        ? 'Bloque Izquierdo (MG-01)'
        : blockCode == 'MG-02'
            ? 'Bloque Centro (MG-02)'
            : 'Bloque Derecho (MG-03)';
    String subtitle = blockCode == 'MG-01'
        ? 'R01 a R08'
        : blockCode == 'MG-02'
            ? 'R09 a R14'
            : 'R15 a R22';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildBlockCard(blockCode, title, subtitle, allGrilles),
      ],
    );
  }

  // Physical Facade Block Card with Upper and Lower Rows matching field photo
  Widget _buildBlockCard(
      String blockCode, String title, String subtitle, List<Grille> allGrilles) {
    final grillesInBlock =
        _filterList(allGrilles.where((g) => g.blockCode == blockCode).toList());

    if (grillesInBlock.isEmpty) {
      return Card(
        color: const Color(0xFF1B2228),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No hay rejillas que coincidan en $blockCode.',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final upperRow = grillesInBlock.where((g) => g.isUpperRow).toList();
    final lowerRow = grillesInBlock.where((g) => !g.isUpperRow).toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;
    final isWide = screenWidth >= 600;

    double calcAspectRatio(int count) {
      if (isWide) return 1.25;
      if (isCompact) return count > 3 ? 0.85 : 0.92;
      return count > 3 ? 0.90 : 1.0;
    }

    return Card(
      elevation: 4,
      color: const Color(0xFF1B2228),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white24, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Block Title Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0077C8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Upper Row Header
            if (upperRow.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.arrow_upward, size: 16, color: Colors.cyanAccent),
                  SizedBox(width: 4),
                  Text(
                    'FILA SUPERIOR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: upperRow.length > 3 ? 4 : 3,
                  childAspectRatio: calcAspectRatio(upperRow.length),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: upperRow.length,
                itemBuilder: (context, idx) {
                  return _buildGrilleTile(upperRow[idx]);
                },
              ),
              const SizedBox(height: 16),
            ],

            // Lower Row Header
            if (lowerRow.isNotEmpty) ...[
              const Row(
                children: [
                  Icon(Icons.arrow_downward,
                      size: 16, color: Colors.cyanAccent),
                  SizedBox(width: 4),
                  Text(
                    'FILA INFERIOR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: lowerRow.length > 3 ? 4 : 3,
                  childAspectRatio: calcAspectRatio(lowerRow.length),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: lowerRow.length,
                itemBuilder: (context, idx) {
                  return _buildGrilleTile(lowerRow[idx]);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // High Contrast Visual Tile representing a single physical grille
  Widget _buildGrilleTile(Grille grille) {
    final statusColor = _getStatusColor(grille.status);
    final maxDays = grille.maxDaysWithoutMaintenance;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GrilleDetailScreen(
              grille: grille,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF232B32),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    grille.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$maxDays d',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: grille.filters.map((f) {
                return Container(
                  width: 5.5,
                  height: 5.5,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusColor(f.status),
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, int count, Color color, GrilleStatus status) {
    final isSelected = _selectedStatusFilter == status;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedStatusFilter = isSelected ? null : status;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: isSelected ? 2 : 1),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.black : color,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.black : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
