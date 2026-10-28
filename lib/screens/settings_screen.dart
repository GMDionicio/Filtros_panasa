import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/grille_cubit.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/employee_repository.dart';

class SettingsScreen extends StatefulWidget {
  final IEmployeeRepository? employeeRepository;
  final IAuthRepository? authRepository;

  const SettingsScreen({
    super.key,
    this.employeeRepository,
    this.authRepository,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final IEmployeeRepository _employeeRepository;
  late final IAuthRepository _authRepository;

  final TextEditingController _urlController = TextEditingController();
  bool _isTesting = false;
  String _connectionStatus = '';

  bool _isLicenseActive = false;
  String _activeLicenseKey = 'Cargando...';
  int _licenseDaysRem = 0;

  List<Employee> _employees = [];
  bool _isLoadingEmployees = false;

  @override
  void initState() {
    super.initState();
    _employeeRepository = widget.employeeRepository ?? getIt<IEmployeeRepository>();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();

    _loadSavedUrl();
    _loadLicenseInfo();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    setState(() => _isLoadingEmployees = true);
    final list = await _employeeRepository.getEmployees();
    if (mounted) {
      setState(() {
        _employees = list;
        _isLoadingEmployees = false;
      });
    }
  }

  Future<void> _deleteEmployee(Employee emp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2228),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Eliminar Usuario', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '¿Está seguro de eliminar al operario "${emp.name}" (Código: ${emp.payrollCode})?\nYa no podrá iniciar sesión.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _employeeRepository.deleteEmployee(emp.payrollCode);
      if (ok) {
        _fetchEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Usuario ${emp.payrollCode} eliminado correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadSavedUrl() async {
    final url = await _authRepository.getBaseUrl();
    if (mounted) {
      setState(() {
        _urlController.text = url;
      });
      _testConnection();
    }
  }

  Future<void> _loadLicenseInfo() async {
    final status = await _authRepository.checkSystemStatus(deviceId: 'WEB-DEVICE-001');
    if (mounted && status != null) {
      setState(() {
        _isLicenseActive = status['isActivated'] == true;
        _activeLicenseKey = status['licenseKey'] ?? 'No Activada';
        _licenseDaysRem = 365;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = 'Verificando...';
    });

    await _authRepository.updateBaseUrl(_urlController.text.trim());
    final isOk = await _authRepository.checkHealth();

    setState(() {
      _isTesting = false;
      _connectionStatus = isOk
          ? 'Conectado a la API backend local (OK)'
          : 'Sin conexión a la API backend';
    });

    if (mounted && isOk) {
      context.read<GrilleCubit>().loadGrilles();
      _loadLicenseInfo();
      _fetchEmployees();
    }
  }

  Future<void> _runSeed() async {
    setState(() => _isTesting = true);
    final ok = await context.read<GrilleCubit>().seedDatabase();
    setState(() => _isTesting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Seed completado: 22 rejillas y 88 filtros creados en la base de datos.'
              : 'Error al ejecutar Seed.'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración & Servidor'),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white),
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
                          backgroundColor: const Color(0xFF0077C8),
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
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF1744),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Usuarios / Operarios Registrados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 20),
                        onPressed: _fetchEmployees,
                        tooltip: 'Actualizar lista',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingEmployees)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_employees.isEmpty)
                    const Text(
                      'No hay operarios registrados en el sistema.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    )
                  else
                    Column(
                      children: _employees.map((emp) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12161A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.badge, color: Colors.cyanAccent, size: 20),
                            title: Text(
                              emp.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              'Nómina: ${emp.payrollCode}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              tooltip: 'Eliminar usuario',
                              onPressed: () => _deleteEmployee(emp),
                            ),
                          ),
                        );
                      }).toList(),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Reiniciar datos de prueba en la base de datos (R01–R22 y sus 88 filtros).',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _isTesting ? null : _runSeed,
                    icon: const Icon(Icons.dataset_linked),
                    label: const Text(
                      'Ejecutar Seed (22 Rejillas / 88 Filtros)',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                    'Licencia del Dispositivo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _isLicenseActive ? Icons.verified : Icons.cancel,
                      color: _isLicenseActive ? const Color(0xFF00E676) : Colors.redAccent,
                      size: 32,
                    ),
                    title: Text(
                      _isLicenseActive ? 'Licencia Anual Activa' : 'Licencia Inactiva / No Activada',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _isLicenseActive
                          ? 'Clave: $_activeLicenseKey\nVigencia: $_licenseDaysRem días'
                          : 'Este dispositivo o navegador no cuenta con una licencia válida activa.',
                      style: const TextStyle(color: Colors.white70),
                    ),
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
