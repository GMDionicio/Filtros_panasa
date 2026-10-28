import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../interfaz.dart';
import 'grille_detail_screen.dart';
import 'employees_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Grille> _allGrilles = [];
  bool _isLoading = true;
  bool _isConnected = false;
  String _searchQuery = '';
  GrilleStatus? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final isHealthOk = await ApiService.checkHealth();
    final grilles = await ApiService.getGrilles();

    if (mounted) {
      setState(() {
        _isConnected = isHealthOk;
        _allGrilles = grilles;
        _isLoading = false;
      });
    }
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

  int get _countOk =>
      _allGrilles.where((g) => g.status == GrilleStatus.ok).length;
  int get _countWarning =>
      _allGrilles.where((g) => g.status == GrilleStatus.warning).length;
  int get _countUrgent =>
      _allGrilles.where((g) => g.status == GrilleStatus.urgent).length;

  List<Grille> _filterList(List<Grille> input) {
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
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.shade800
                    : Colors.orange.shade800,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _isConnected ? Icons.wifi : Icons.wifi_off,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isConnected ? 'API Local' : 'Offline',
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
              onPressed: _loadData,
              tooltip: 'Actualizar',
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.cyanAccent,
            indicatorWeight: 3,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: '🏢 Vista Fachada Real'),
              Tab(text: '◀️ MG-01 (Izquierdo)'),
              Tab(text: '⏺️ MG-02 (Centro)'),
              Tab(text: '▶️ MG-03 (Derecho)'),
            ],
          ),
        ),
        drawer: Drawer(
          backgroundColor: const Color(0xFF12161A),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF1B2228)),
                accountName: const Text('Filtros Panasa App',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                accountEmail: const Text('Gestión de Aire Acondicionado'),
                currentAccountPicture: const CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: Icon(Icons.air, size: 38, color: Colors.black),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.threed_rotation, color: Colors.cyanAccent),
                title: const Text('Gemelo Digital 3D (Modelo 3D)',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FachadaRejillas3DScreen()),
                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.view_quilt, color: Colors.cyanAccent),
                title: const Text('Elevación Fachada 2D (Por Bloques)',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.people, color: Colors.cyanAccent),
                title: const Text('Gestión de Empleados / Nómina',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EmployeesScreen()),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.cyanAccent),
                title: const Text('Configuración & Servidor API',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsScreen(onRefreshNeeded: _loadData),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        body: _isLoading
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
                              _buildSummaryCard('Al Día (<15d)', _countOk,
                                  const Color(0xFF00E676), GrilleStatus.ok),
                              const SizedBox(width: 8),
                              _buildSummaryCard(
                                  'Atención (≥15d)',
                                  _countWarning,
                                  const Color(0xFFFFD600),
                                  GrilleStatus.warning),
                              const SizedBox(width: 8),
                              _buildSummaryCard(
                                  'Urgente (≥20d)',
                                  _countUrgent,
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
                          _buildMiniBadge(
                              'Al Día (<15d)', _countOk, const Color(0xFF00E676)),
                          const SizedBox(width: 6),
                          _buildMiniBadge('Atención (≥15d)', _countWarning,
                              const Color(0xFFFFD600)),
                          const SizedBox(width: 6),
                          _buildMiniBadge('Urgente (≥20d)', _countUrgent,
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
                        _buildFacadeViewAll(),
                        _buildSingleBlockView('MG-01'),
                        _buildSingleBlockView('MG-02'),
                        _buildSingleBlockView('MG-03'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        setState(() => _searchQuery = val);
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
  Widget _buildFacadeViewAll() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildBlockCard(
            'MG-01', 'Bloque Izquierdo (MG-01)', 'R01 a R08 (8 Rejillas)'),
        _buildBlockCard(
            'MG-02', 'Bloque Centro (MG-02)', 'R09 a R14 (6 Rejillas)'),
        _buildBlockCard(
            'MG-03', 'Bloque Derecho (MG-03)', 'R15 a R22 (8 Rejillas)'),
      ],
    );
  }

  // Single Block View for tabs
  Widget _buildSingleBlockView(String blockCode) {
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
        _buildBlockCard(blockCode, title, subtitle),
      ],
    );
  }

  // Physical Facade Block Card with Upper and Lower Rows matching field photo
  Widget _buildBlockCard(String blockCode, String title, String subtitle) {
    final grillesInBlock = _filterList(
        _allGrilles.where((g) => g.blockCode == blockCode).toList());

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
                  childAspectRatio: 0.95,
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
                  childAspectRatio: 0.95,
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
              onRefreshNeeded: _loadData,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
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
                Text(
                  grille.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.cyanAccent,
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
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
            Text(
              '$maxDays d',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: grille.filters.map((f) {
                return Container(
                  width: 6,
                  height: 6,
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
