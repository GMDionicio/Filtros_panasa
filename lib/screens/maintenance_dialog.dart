import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/employee_repository.dart';
import '../repositories/grille_repository.dart';

class MaintenanceResult {
  final List<int> successfulFilters;
  final List<int> failedFilters;

  const MaintenanceResult({
    required this.successfulFilters,
    required this.failedFilters,
  });

  bool get isFullSuccess => failedFilters.isEmpty && successfulFilters.isNotEmpty;
  bool get isPartialSuccess => successfulFilters.isNotEmpty && failedFilters.isNotEmpty;
  bool get isFullFailure => successfulFilters.isEmpty;
}

class MaintenanceDialog extends StatefulWidget {
  final Grille grille;
  final FilterItem? selectedFilter;
  final IGrilleRepository? grilleRepository;
  final IEmployeeRepository? employeeRepository;

  const MaintenanceDialog({
    super.key,
    required this.grille,
    this.selectedFilter,
    this.grilleRepository,
    this.employeeRepository,
  });

  @override
  State<MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<MaintenanceDialog> {
  late final IGrilleRepository _grilleRepository;
  late final IEmployeeRepository _employeeRepository;

  final List<Employee> _employees = List.from(defaultEmployees);
  final List<String> _selectedPayrollCodes = [];
  late List<int> _selectedFilterNumbers;
  bool _isLoading = false;
  final TextEditingController _payrollController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _grilleRepository = widget.grilleRepository ?? getIt<IGrilleRepository>();
    _employeeRepository = widget.employeeRepository ?? getIt<IEmployeeRepository>();

    if (widget.selectedFilter != null) {
      _selectedFilterNumbers = [widget.selectedFilter!.filterNumber];
    } else {
      _selectedFilterNumbers = [1, 2, 3, 4];
    }
    _loadEmployees();
  }

  @override
  void dispose() {
    _payrollController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final list = await _employeeRepository.getEmployees();
    if (mounted) {
      setState(() {
        if (list.isNotEmpty) {
          _employees.clear();
          _employees.addAll(list);
        }
      });
    }
  }

  void _addCodeFromField(String value) {
    final code = value.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      if (!_selectedPayrollCodes.contains(code)) {
        _selectedPayrollCodes.add(code);
      }
      _payrollController.clear();
    });
  }

  Future<void> _submit() async {
    final selectedCodes = List<String>.from(_selectedPayrollCodes);

    if (selectedCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor seleccione al menos un código de nómina (operario participante).'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedFilterNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona al menos un filtro.')),
      );
      return;
    }

    var empList = _employees;
    if (empList.isEmpty) {
      empList = await _employeeRepository.getEmployees();
    }

    // Validar que todos los códigos seleccionados correspondan a un operario registrado.
    final validCodes = empList.map((e) => e.payrollCode.trim().toUpperCase()).toSet();
    for (final code in selectedCodes) {
      if (!validCodes.contains(code)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El código "$code" no corresponde a ningún operario registrado.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    final List<int> successfulFilters = [];
    final List<int> failedFilters = [];

    try {
      for (int fNum in _selectedFilterNumbers) {
        final res = await _grilleRepository.registerEvent(
          grilleCode: widget.grille.code,
          filterNumber: fNum,
          payrollCodes: selectedCodes,
          notes: _notesController.text.trim().isEmpty
              ? 'Mantenimiento registrado'
              : _notesController.text.trim(),
        );
        if (res) {
          successfulFilters.add(fNum);
        } else {
          failedFilters.add(fNum);
        }
      }
    } catch (e) {
      debugPrint('Error registrando mantenimientos: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!mounted) return;

    final result = MaintenanceResult(
      successfulFilters: successfulFilters,
      failedFilters: failedFilters,
    );

    if (result.isFullFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No se pudo registrar el mantenimiento en ningún filtro. Reintente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth * 0.88).clamp(280.0, 500.0);

    return AlertDialog(
      backgroundColor: const Color(0xFF1B2228),
      title: Row(
        children: [
          const Icon(Icons.build_circle, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mantenimiento ${widget.grille.code}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seleccionar Filtros:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List.generate(4, (index) {
                  final fNum = index + 1;
                  final isSelected = _selectedFilterNumbers.contains(fNum);
                  return FilterChip(
                    label: Text(
                      'Filtro #$fNum',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.cyanAccent,
                    backgroundColor: Colors.black38,
                    checkmarkColor: Colors.black,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedFilterNumbers.add(fNum);
                        } else {
                          if (_selectedFilterNumbers.length > 1) {
                            _selectedFilterNumbers.remove(fNum);
                          }
                        }
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 12),
              const Text(
                'Operarios participantes (Código de Nómina):',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const Text(
                'Seleccione uno o más operarios que realizaron el mantenimiento.',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              if (_employees.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _employees.map((emp) {
                    final isSelected = _selectedPayrollCodes.contains(emp.payrollCode);
                    return FilterChip(
                      label: Text(
                        '${emp.payrollCode} (${emp.name})',
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.cyanAccent,
                      backgroundColor: Colors.black38,
                      checkmarkColor: Colors.black,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (!_selectedPayrollCodes.contains(emp.payrollCode)) {
                              _selectedPayrollCodes.add(emp.payrollCode);
                            }
                          } else {
                            _selectedPayrollCodes.remove(emp.payrollCode);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _payrollController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Agregar otro código de nómina',
                  hintText: 'Ej. EMP-001 (presione Enter para agregar)',
                  hintStyle: const TextStyle(color: Colors.white38),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onSubmitted: _addCodeFromField,
              ),
              const SizedBox(height: 6),
              Text(
                _selectedPayrollCodes.isEmpty
                    ? 'Sin operarios seleccionados.'
                    : 'Seleccionados (${_selectedPayrollCodes.length}): ${_selectedPayrollCodes.join(", ")}',
                style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
              ),
              const SizedBox(height: 12),
              const Text(
                'Notas opcionales:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ej. Filtro limpiado y reemplazado...',
                  hintStyle: const TextStyle(color: Colors.white38),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: Colors.black,
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text(
                  'Guardar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}
