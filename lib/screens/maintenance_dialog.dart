import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

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
  final List<Employee> _employees = [
    Employee(payrollCode: 'EMP-001', name: 'Juan Pérez'),
    Employee(payrollCode: 'EMP-002', name: 'Carlos López'),
    Employee(payrollCode: 'EMP-003', name: 'María Gómez'),
    Employee(payrollCode: 'EMP-004', name: 'Dionicio Gómez'),
  ];
  late String _selectedPayrollCode;
  late List<int> _selectedFilterNumbers;
  bool _isLoading = false;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPayrollCode = _employees.first.payrollCode;
    if (widget.selectedFilter != null) {
      _selectedFilterNumbers = [widget.selectedFilter!.filterNumber];
    } else {
      _selectedFilterNumbers = [1, 2, 3, 4];
    }
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final list = await ApiService.getEmployees();
    if (mounted && list.isNotEmpty) {
      setState(() {
        _employees.clear();
        _employees.addAll(list);
        if (!_employees.any((e) => e.payrollCode == _selectedPayrollCode)) {
          _selectedPayrollCode = _employees.first.payrollCode;
        }
      });
    }
  }

  Future<void> _submit() async {
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
        payrollCode: _selectedPayrollCode,
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
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.build_circle, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mantenimiento ${widget.grille.code}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Seleccionar Filtros:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List.generate(4, (index) {
                  final fNum = index + 1;
                  final isSelected = _selectedFilterNumbers.contains(fNum);
                  return FilterChip(
                    label: Text('Filtro #$fNum'),
                    selected: isSelected,
                    selectedColor: Colors.indigo.shade100,
                    checkmarkColor: Colors.indigo,
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
                'Técnico / Empleado (Código de Nómina):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _employees.map((emp) {
                  final isSelected = emp.payrollCode == _selectedPayrollCode;
                  return ChoiceChip(
                    label: Text('${emp.payrollCode} (${emp.name})'),
                    selected: isSelected,
                    selectedColor: Colors.indigo.shade100,
                    checkmarkColor: Colors.indigo,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedPayrollCode = emp.payrollCode);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Notas opcionales:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  hintText: 'Ej. Filtro limpiado y reemplazado...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
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
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
