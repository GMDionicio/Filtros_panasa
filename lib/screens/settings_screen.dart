import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onRefreshNeeded;

  const SettingsScreen({super.key, required this.onRefreshNeeded});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isTesting = false;
  String _connectionStatus = '';

  @override
  void initState() {
    super.initState();
    _urlController.text = ApiService.baseUrl;
    _testConnection();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = 'Verificando...';
    });

    ApiService.updateBaseUrl(_urlController.text.trim());
    final isOk = await ApiService.checkHealth();

    setState(() {
      _isTesting = false;
      _connectionStatus = isOk
          ? 'Conectado a la API backend local (OK)'
          : 'Sin conexión a la API backend';
    });
  }

  Future<void> _runSeed() async {
    setState(() => _isTesting = true);
    final ok = await ApiService.seedDatabase();
    setState(() => _isTesting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Seed completado: 22 rejillas y 88 filtros creados en SQLite.'
              : 'Error al ejecutar Seed.'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
      if (ok) widget.onRefreshNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración & Servidor'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conexión al Backend API',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL Base API',
                      hintText: 'http://10.0.2.2:3010',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isTesting ? null : _testConnection,
                        icon: const Icon(Icons.sync),
                        label: const Text('Probar Conexión'),
                      ),
                      const SizedBox(width: 12),
                      if (_isTesting)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _connectionStatus,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _connectionStatus.contains('OK')
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulación / Base de Datos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Reiniciar datos de prueba en la base de datos SQLite (R01–R22 y sus 88 filtros).',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isTesting ? null : _runSeed,
                    icon: const Icon(Icons.dataset_linked),
                    label: const Text('Ejecutar Seed (22 Rejillas / 88 Filtros)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Licencia del Dispositivo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified, color: Colors.green, size: 32),
                    title: const Text('Licencia Anual Activa'),
                    subtitle: const Text('Clave: PAN-PANASA-2026-DEV\nVigencia: 365 días'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
