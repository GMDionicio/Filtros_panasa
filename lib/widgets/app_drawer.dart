import 'package:flutter/material.dart';
import '../interfaz.dart';
import '../screens/dashboard_screen.dart';
import '../screens/employees_screen.dart';
import '../services/local_db_service.dart';
import 'admin_auth_dialog.dart';
import 'operator_login_dialog.dart';

class AppDrawer extends StatefulWidget {
  final String currentRoute;

  const AppDrawer({super.key, this.currentRoute = ''});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, String>? _activeOperator;

  @override
  void initState() {
    super.initState();
    _loadActiveOperator();
  }

  Future<void> _loadActiveOperator() async {
    final op = await LocalDbService.getActiveOperator();
    if (mounted) {
      setState(() => _activeOperator = op);
    }
  }

  Future<void> _switchOperator() async {
    final result = await OperatorLoginDialog.show(context, canDismiss: true);
    if (result != null && mounted) {
      setState(() => _activeOperator = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sesión iniciada como: ${result['name']} (${result['code']})'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  Future<void> _logout() async {
    await LocalDbService.clearActiveOperator();
    if (mounted) {
      setState(() => _activeOperator = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF12161A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1B2228)),
            accountName: Text(
              _activeOperator != null
                  ? '👤 ${_activeOperator!['name']}'
                  : 'Filtros Panasa App',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(
              _activeOperator != null
                  ? 'Nómina: ${_activeOperator!['code']}'
                  : 'Sin Sesión de Operario Activa',
              style: TextStyle(
                color: _activeOperator != null ? Colors.cyanAccent : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: _activeOperator != null ? Colors.cyanAccent : Colors.blueGrey,
              child: Icon(
                _activeOperator != null ? Icons.person : Icons.threed_rotation,
                size: 36,
                color: Colors.black,
              ),
            ),
          ),
          
          // Operator session controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1B2228),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _activeOperator != null
                        ? 'Operario: ${_activeOperator!['code']}'
                        : 'Acceso no autenticado',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _switchOperator,
                  style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
                  icon: Icon(_activeOperator != null ? Icons.sync : Icons.login, size: 16),
                  label: Text(_activeOperator != null ? 'Cambiar' : 'Ingresar'),
                ),
                if (_activeOperator != null)
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                    onPressed: _logout,
                    tooltip: 'Cerrar Sesión',
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),

          ListTile(
            leading: const Icon(Icons.threed_rotation, color: Colors.cyanAccent),
            title: const Text('Gemelo Digital 3D', style: TextStyle(color: Colors.white)),
            selected: widget.currentRoute == '3d',
            selectedTileColor: Colors.cyanAccent.withValues(alpha: 0.15),
            onTap: () {
              Navigator.pop(context);
              if (widget.currentRoute != '3d') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const FachadaRejillas3DScreen()),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_quilt, color: Colors.cyanAccent),
            title: const Text('Elevación Fachada 2D (Por Bloques)', style: TextStyle(color: Colors.white)),
            selected: widget.currentRoute == '2d',
            selectedTileColor: Colors.cyanAccent.withValues(alpha: 0.15),
            onTap: () {
              Navigator.pop(context);
              if (widget.currentRoute != '2d') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.cyanAccent),
            title: const Text('Gestión de Operarios', style: TextStyle(color: Colors.white)),
            selected: widget.currentRoute == 'employees',
            selectedTileColor: Colors.cyanAccent.withValues(alpha: 0.15),
            onTap: () {
              Navigator.pop(context);
              if (widget.currentRoute != 'employees') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EmployeesScreen()),
                );
              }
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.cyanAccent),
            title: const Text('Configuración & Servidor API', style: TextStyle(color: Colors.white)),
            selected: widget.currentRoute == 'settings',
            selectedTileColor: Colors.cyanAccent.withValues(alpha: 0.15),
            onTap: () {
              Navigator.pop(context);
              if (widget.currentRoute != 'settings') {
                showDialog(
                  context: context,
                  builder: (context) => const AdminAuthDialog(),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
