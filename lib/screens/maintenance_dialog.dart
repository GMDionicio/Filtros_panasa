import 'package:flutter/material.dart';
import '../di/service_locator.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
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
  final IAuthRepository? authRepository;

  const MaintenanceDialog({
    super.key,
    required this.grille,
    this.selectedFilter,
    this.grilleRepository,
    this.employeeRepository,
    this.authRepository,
  });

  @override
  State<MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<MaintenanceDialog> {
  late final IGrilleRepository _grilleRepository;
  late final IEmployeeRepository _employeeRepository;
  late final IAuthRepository _authRepository;

  final List<Employee> _employees = List.from(defaultEmployees);
  late String _selectedPayrollCode;
  late List<int> _selectedFilterNumbers;
  bool _isLoading = false;
  final TextEditingController _payrollController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _grilleRepository = widget.grilleRepository ?? getIt<IGrilleRepository>();
    _employeeRepository = widget.employeeRepository ?? getIt<IEmployeeRepository>();
    _authRepository = widget.authRepository ?? getIt<IAuthRepository>();

    _selectedPayrollCode = _employees.isNotEmpty ? _employees.first.payrollCode : '';
    _payrollController.text = _selectedPayrollCode;

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
    final activeOp = await _authRepository.getActiveOperator();
    final list = await _employeeRepository.getEmployees();
    if (mounted) {
      setState(() {
        if (list.isNotEmpty) {
          _employees.clear();
          _employees.addAll(list);
        }
        if (activeOp != null && activeOp['code'] != null && activeOp['code']!.isNotEmpty) {
          _selectedPayrollCode = activeOp['code']!;
          _payrollController.text = activeOp['code']!;
        } else if (_employees.isNotEmpty) {
          _selectedPayrollCode = _employees.first.payrollCode;
          _payrollController.text = _selectedPayrollCode;
        }
      });
    }
  }

  Future<void> _submit() async {
    final inputPayrollCode = _payrollController.text.trim().toUpperCase();

    if (inputPayrollCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese o seleccione su código de nómina.'),
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

    final activeOp = await _authRepository.getActiveOperator();
    if (!mounted) return;

    final activeCode = activeOp?['code']?.trim().toUpperCase();

    final existsInList = empList.any((e) => e.payrollCode.trim().toUpperCase() == inputPayrollCode);
    final isCurrentActiveOp = activeCode != null && activeCode == inputPayrollCode;

    if (!existsInList && !isCurrentActiveOp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('El código "$inputPayrollCode" no corresponde a ningún operario registrado.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final List<int> successfulFilters = [];
    final List<int> failedFilters = [];

    for (int fNum in _selectedFilterNumbers) {
      final res = await _grilleRepository.registerEvent(
        grilleCode: widget.grille.code,
        filterNumber: fNum,
        payrollCode: inputPayrollCode,
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

    if (!mounted) return;

    setState(() => _isLoading = false);

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
                'Técnico / Operario (Código de Nómina):',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              if (_employees.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _employees.map((emp) {
                    final isSelected = emp.payrollCode == _selectedPayrollCode;
                    return ChoiceChip(
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
                        if (selected) {
                          setState(() {
                            _selectedPayrollCode = emp.payrollCode;
                            _payrollController.text = emp.payrollCode;
                          });
                        }
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
                  labelText: 'Código de Nómina',
                  hintText: 'Ej. EMP-001',
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
                onChanged: (val) {
                  setState(() {
                    _selectedPayrollCode = val.trim().toUpperCase();
                  });
                },
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
