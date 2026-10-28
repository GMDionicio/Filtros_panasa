import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../repositories/auth_repository.dart';
import '../screens/settings_screen.dart';

class AdminAuthDialog extends StatefulWidget {
  final IAuthRepository? authRepository;

  const AdminAuthDialog({super.key, this.authRepository});

  @override
  State<AdminAuthDialog> createState() => _AdminAuthDialogState();
}

class _AdminAuthDialogState extends State<AdminAuthDialog> {
  late final IAuthRepository _authRepository;
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();
  }

  Future<void> _validateAndNavigate() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Por favor ingresa la clave.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final isAuthorized = await _authRepository.validateAdminPin(pin);

    if (mounted) {
      setState(() => _isLoading = false);

      if (isAuthorized) {
        Navigator.of(context).pop();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else {
        setState(() {
          _errorMessage =
              '❌ Clave incorrecta o sin respuesta del servidor online.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B2228),
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text(
            'Acceso Administrador',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ingresa la clave de administrador para acceder a la Configuración y Servidor:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, letterSpacing: 3),
            decoration: InputDecoration(
              labelText: 'Clave Administrador',
              hintText: '••••',
              prefixIcon: const Icon(Icons.lock, color: Colors.cyanAccent),
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
            onSubmitted: (_) => _isLoading ? null : _validateAndNavigate(),
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              style: const TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child:
              const Text('Cancelar', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: Colors.black,
          ),
          onPressed: _isLoading ? null : _validateAndNavigate,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.vpn_key),
          label: const Text(
            'Validar Servidor',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
