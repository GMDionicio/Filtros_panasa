import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/employee_repository.dart';
import 'admin_auth_dialog.dart';

class BlockingLoginScreen extends StatefulWidget {
  final ValueChanged<Map<String, String>> onLoginSuccess;

  const BlockingLoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<BlockingLoginScreen> createState() => _BlockingLoginScreenState();
}

class _BlockingLoginScreenState extends State<BlockingLoginScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  late final IAuthRepository _authRepository;
  late final IEmployeeRepository _employeeRepository;

  @override
  void initState() {
    super.initState();
    _authRepository = getIt<IAuthRepository>();
    _employeeRepository = getIt<IEmployeeRepository>();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final inputCode = _codeController.text.trim().toUpperCase();
    if (inputCode.isEmpty) {
      setState(() => _errorMessage = 'Ingrese su código de nómina');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Intentar login con backend remoto
      final authResult = await _authRepository.loginOperator(
        payrollCode: inputCode,
        deviceId: 'WEB-DEVICE-001',
      );

      if (authResult != null && authResult['authenticated'] == true) {
        final code = authResult['payrollCode'] as String? ?? inputCode;
        final name = authResult['name'] as String? ?? 'Operario $code';

        await _authRepository.saveActiveOperator(code, name);
        if (mounted) {
          widget.onLoginSuccess({'code': code, 'name': name});
        }
        return;
      }

      // 2. Fallback local contra la lista de empleados autorizados
      final empList = await _employeeRepository.getEmployees();
      final matched = empList.firstWhere(
        (e) => e.payrollCode.trim().toUpperCase() == inputCode,
        orElse: () => Employee(payrollCode: '', name: ''),
      );

      if (matched.payrollCode.isNotEmpty) {
        await _authRepository.saveActiveOperator(matched.payrollCode, matched.name);
        if (mounted) {
          widget.onLoginSuccess({'code': matched.payrollCode, 'name': matched.name});
        }
      } else {
        setState(() {
          _errorMessage = 'Código de nómina "$inputCode" no registrado en el sistema de la planta.';
        });
      }
    } catch (e) {
      try {
        final localEmps = await _employeeRepository.getEmployees();
        final matched = localEmps.firstWhere(
          (e) => e.payrollCode.trim().toUpperCase() == inputCode,
          orElse: () => Employee(payrollCode: '', name: ''),
        );
        if (matched.payrollCode.isNotEmpty) {
          await _authRepository.saveActiveOperator(matched.payrollCode, matched.name);
          if (mounted) {
            widget.onLoginSuccess({'code': matched.payrollCode, 'name': matched.name});
          }
          return;
        }
      } catch (_) {}

      setState(() {
        _errorMessage = 'No se pudo verificar el código "$inputCode". Ingrese un código de nómina registrado.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2228),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'FILTROS PANASA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Acceso Restringido a Planta',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ingrese su código de nómina para desbloquear el Gemelo Digital 3D y la interfaz de monitoreo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Código de Nómina',
                    hintText: 'Ej. EMP-001 o 35564',
                    labelStyle: const TextStyle(color: Colors.cyanAccent),
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                    prefixIcon: const Icon(Icons.badge_outlined, color: Colors.cyanAccent),
                    filled: true,
                    fillColor: const Color(0xFF12161A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _handleLogin(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                          )
                        : const Icon(Icons.login, size: 22),
                    label: Text(
                      _isLoading ? 'Verificando Acceso...' : 'Iniciar Sesión',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const AdminAuthDialog(),
                    );
                  },
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 18, color: Colors.white54),
                  label: const Text(
                    'Acceso de Administrador',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
