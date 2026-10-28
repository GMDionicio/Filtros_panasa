import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';

class MaintenanceDialog extends StatefulWidget {
  final Grille grille;
  final FilterItem? selectedFilter;

  const MaintenanceDialog({
    super.key,
    required this.grille,
    this.selectedFilter,
  });

  @override
  State<MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<MaintenanceDialog> {
  final List<Employee> _employees = List.from(defaultEmployees);
  late String _selectedPayrollCode;
  late List<int> _selectedFilterNumbers;
  bool _isLoading = false;
  final TextEditingController _payrollController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPayrollCode = _employees.isNotEmpty ? _employees.first.payrollCode : 'EMP-001';
    _payrollController.text = _selectedPayrollCode;

    if (widget.selectedFilter != null) {
      _selectedFilterNumbers = [widget.selectedFilter!.filterNumber];
    } else {
      _selectedFilterNumbers = [1, 2, 3, 4];
    }
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final activeOp = await LocalDbService.getActiveOperator();
    final list = await ApiService.getEmployees();
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
    final payrollCode = _payrollController.text.trim().isEmpty
        ? 'EMP-001'
        : _payrollController.text.trim();

    if (_selectedFilterNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona al menos un filtro.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    bool successAll = true;
    for (int fNum in _selectedFilterNumbers) {
      final res = await ApiService.registerEvent(
        grilleCode: widget.grille.code,
        filterNumber: fNum,
        payrollCode: payrollCode,
        notes: _notesController.text.trim().isEmpty
            ? 'Mantenimiento registrado'
            : _notesController.text.trim(),
      );
      if (!res) successAll = false;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop(successAll);
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
