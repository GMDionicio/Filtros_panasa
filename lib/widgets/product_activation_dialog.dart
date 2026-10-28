import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../repositories/auth_repository.dart';

class ProductActivationDialog extends StatefulWidget {
  final String deviceId;
  final IAuthRepository? authRepository;

  const ProductActivationDialog({
    super.key,
    required this.deviceId,
    this.authRepository,
  });

  static Future<bool> show(
    BuildContext context, {
    required String deviceId,
    IAuthRepository? authRepository,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ProductActivationDialog(
          deviceId: deviceId,
          authRepository: authRepository,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<ProductActivationDialog> createState() => _ProductActivationDialogState();
}

class _ProductActivationDialogState extends State<ProductActivationDialog> {
  late final IAuthRepository _authRepository;

  final _licenseController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    final licenseKey = _licenseController.text.trim();
    final adminPin = _pinController.text.trim();

    if (licenseKey.isEmpty || adminPin.isEmpty) {
      setState(() => _errorMessage = 'Ingrese la clave de licencia y el PIN de administrador');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _authRepository.activateProduct(
        licenseKey: licenseKey,
        adminPin: adminPin,
        deviceId: widget.deviceId,
      );

      if (res != null && res['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _errorMessage = res?['message'] ?? 'Clave de Licencia o PIN de Administrador incorrecto.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión al validar la licencia.';
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
          Icon(Icons.verified_user, color: Colors.amberAccent, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Activación de Producto',
              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
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
              'Este dispositivo o navegador requiere ser licenciado para acceder al sistema de la planta industrial.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _licenseController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Clave de Licencia de Producto',
                hintText: 'Ej: PAN-XXXX-XXXX-XXXX',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.key, color: Colors.cyanAccent),
                filled: true,
                fillColor: const Color(0xFF12161A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
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
              onSubmitted: (_) => _handleActivation(),
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
          onPressed: _isLoading ? null : _handleActivation,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amberAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.check_circle, size: 20),
          label: Text(
            _isLoading ? 'Activando...' : 'Activar Licencia',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
