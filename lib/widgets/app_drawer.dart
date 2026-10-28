import 'package:flutter/material.dart';
import '../services/local_db_service.dart';
import 'admin_auth_dialog.dart';

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
          
          ListTile(
            leading: const Icon(Icons.threed_rotation, color: Colors.cyanAccent),
            title: const Text('Gemelo Digital 3D', style: TextStyle(color: Colors.white)),
            selected: widget.currentRoute == '3d',
            selectedTileColor: Colors.cyanAccent.withValues(alpha: 0.15),
            onTap: () {
              Navigator.pop(context);
              if (widget.currentRoute != '3d') {
                Navigator.pushReplacementNamed(context, '/3d');
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
                Navigator.pushReplacementNamed(context, '/2d');
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
                Navigator.pushNamed(context, '/employees');
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
          if (_activeOperator != null) ...[
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Cerrar Sesión de Operario', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await LocalDbService.clearActiveOperator();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
