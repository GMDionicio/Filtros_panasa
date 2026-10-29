import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/employee_repository.dart';

class OperatorLoginDialog extends StatefulWidget {
  final bool canDismiss;
  final IAuthRepository? authRepository;
  final IEmployeeRepository? employeeRepository;

  const OperatorLoginDialog({
    super.key,
    this.canDismiss = false,
    this.authRepository,
    this.employeeRepository,
  });

  /// Muestra el diálogo de login y retorna datos del operario si inició sesión
  static Future<Map<String, String>?> show(
    BuildContext context, {
    bool canDismiss = false,
    IAuthRepository? authRepository,
    IEmployeeRepository? employeeRepository,
  }) async {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: canDismiss,
      builder: (ctx) => PopScope(
        canPop: canDismiss,
        child: OperatorLoginDialog(
          canDismiss: canDismiss,
          authRepository: authRepository,
          employeeRepository: employeeRepository,
        ),
      ),
    );
  }

  @override
  State<OperatorLoginDialog> createState() => _OperatorLoginDialogState();
}

class _OperatorLoginDialogState extends State<OperatorLoginDialog> {
  late final IAuthRepository _authRepository;
  late final IEmployeeRepository _employeeRepository;

  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();
    _employeeRepository = widget.employeeRepository ?? getIt<IEmployeeRepository>();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployees() async {
    final list = await _employeeRepository.getEmployees();
    if (mounted) {
      setState(() => _employees = list);
    }
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
      final deviceId = await _authRepository.getOrCreateDeviceId();
      final authResult = await _authRepository.loginOperator(
        payrollCode: inputCode,
        deviceId: deviceId,
      );

      if (authResult != null && authResult['authenticated'] == true) {
        final code = authResult['payrollCode'] as String? ?? inputCode;
        final name = authResult['name'] as String? ?? 'Operario $code';

        await _authRepository.saveActiveOperator(code, name, token: authResult['token'] as String?);
        if (mounted) {
          Navigator.of(context).pop({
            'code': code,
            'name': name,
          });
        }
        return;
      }

      var empList = _employees;
      if (empList.isEmpty) {
        empList = await _employeeRepository.getEmployees();
      }

      final matched = empList.firstWhere(
        (e) => e.payrollCode.toUpperCase() == inputCode,
        orElse: () => Employee(payrollCode: '', name: ''),
      );

      if (matched.payrollCode.isNotEmpty) {
        await _authRepository.saveActiveOperator(matched.payrollCode, matched.name);
        if (mounted) {
          Navigator.of(context).pop({
            'code': matched.payrollCode,
            'name': matched.name,
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Código de nómina "$inputCode" no encontrado en el sistema.';
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
            Navigator.of(context).pop({
              'code': matched.payrollCode,
              'name': matched.name,
            });
          }
          return;
        }
      } catch (_) {}

      setState(() {
        _errorMessage = 'No se pudo verificar el código "$inputCode". Ingrese un código registrado.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B2228),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.badge_outlined, color: Colors.cyanAccent, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Acceso de Operario',
              style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingrese su código de nómina para autenticarse y registrar mantenimientos en el sistema.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Código de Nómina',
                hintText: 'Ej: EMP-001, 1002...',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.person, color: Colors.cyanAccent),
                filled: true,
                fillColor: const Color(0xFF12161A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                ),
              ),
              onSubmitted: (_) => _handleLogin(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.canDismiss)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _handleLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0077C8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.login, size: 18),
          label: Text(_isLoading ? 'Verificando...' : 'Ingresar'),
        ),
      ],
    );
  }
}
