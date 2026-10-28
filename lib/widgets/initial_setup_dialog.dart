import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../repositories/auth_repository.dart';

class InitialSetupDialog extends StatefulWidget {
  final IAuthRepository? authRepository;

  const InitialSetupDialog({super.key, this.authRepository});

  static Future<Map<String, String>?> show(
    BuildContext context, {
    IAuthRepository? authRepository,
  }) async {
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: InitialSetupDialog(authRepository: authRepository),
      ),
    );
  }

  @override
  State<InitialSetupDialog> createState() => _InitialSetupDialogState();
}

class _InitialSetupDialogState extends State<InitialSetupDialog> {
  late final IAuthRepository _authRepository;

  final _pinController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSetup() async {
    final pin = _pinController.text.trim();
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (pin.isEmpty || code.isEmpty || name.isEmpty) {
      setState(() => _errorMessage = 'Complete todos los campos requeridos');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _authRepository.initialSetup(
        adminPin: pin,
        employeeCode: code,
        employeeName: name,
      );

      if (res != null && res['success'] == true) {
        final empCode = res['payrollCode'] as String? ?? code;
        final empName = res['name'] as String? ?? name;

        await _authRepository.saveActiveOperator(empCode, empName);

        if (mounted) {
          Navigator.of(context).pop({
            'code': empCode,
            'name': empName,
          });
        }
      } else {
        setState(() {
          _errorMessage = res?['message'] ?? 'PIN de Administrador incorrecto.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión durante la configuración inicial.';
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
        side: const BorderSide(color: Colors.cyanAccent, width: 2),
      ),
      title: const Row(
        children: [
          Icon(Icons.build_circle_outlined, color: Colors.cyanAccent, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Configuración Inicial de Planta',
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
              'Bienvenido a Filtros Panasa. Se inicializará la planta (22 rejillas y 88 filtros) y se registrará al primer operario.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'PIN de Administrador',
                hintText: '••••',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.lock, color: Colors.cyanAccent),
                filled: true,
                fillColor: const Color(0xFF12161A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Código de Nómina del Primer Operario',
                hintText: 'Ej: EMP-001',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.badge, color: Colors.cyanAccent),
                filled: true,
                fillColor: const Color(0xFF12161A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Nombre Completo del Operario',
                hintText: 'Ej: Juan Pérez',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.person, color: Colors.cyanAccent),
                filled: true,
                fillColor: const Color(0xFF12161A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (_) => _handleSetup(),
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
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _handleSetup,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0077C8),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.rocket_launch, size: 20),
          label: Text(
            _isLoading ? 'Inicializando...' : 'Inicializar Planta',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
