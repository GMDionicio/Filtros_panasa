import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/grille_cubit.dart';
import 'models/models.dart';
import 'screens/maintenance_dialog.dart';
import 'services/api_service.dart';
import 'services/local_db_service.dart';
import 'widgets/app_drawer.dart';
import 'widgets/initial_setup_dialog.dart';
import 'widgets/operator_login_dialog.dart';
import 'widgets/product_activation_dialog.dart';

enum EstadoRejilla { operativa, alerta, mantenimiento, apagada }

class CameraState {
  final double camX;
  final double camY;
  final double camZ;
  final double yaw;
  final double pitch;

  const CameraState({
    required this.camX,
    required this.camY,
    required this.camZ,
    required this.yaw,
    required this.pitch,
  });

  CameraState copyWith({
    double? camX,
    double? camY,
    double? camZ,
    double? yaw,
    double? pitch,
  }) {
    return CameraState(
      camX: camX ?? this.camX,
      camY: camY ?? this.camY,
      camZ: camZ ?? this.camZ,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
    );
  }
}

class RejillaModel {
  final int id; // 1 a 22
  final String codigo; // R01 a R22
  final int fila; // 0 = Superior, 1 = Inferior
  final int bloque; // 0 = MG-01 (Izq), 1 = MG-02 (Centro), 2 = MG-03 (Der)
  final int indiceEnFila; // 0 a 10
  final double worldX; // Posición X en el muro 3D
  final double worldY; // Posición Y en el muro 3D
  double temperaturaC;
  double caudalPorcentaje;
  Grille? liveGrille;

  RejillaModel({
    required this.id,
    required this.codigo,
    required this.fila,
    required this.bloque,
    required this.indiceEnFila,
    required this.worldX,
    required this.worldY,
    this.temperaturaC = 38.5,
    this.caudalPorcentaje = 85.0,
    this.liveGrille,
  });

  /// Deriva dinámicamente el estado del modelo inmutable de dominio Grille (SSOT)
  EstadoRejilla get estado {
    if (liveGrille == null) return EstadoRejilla.operativa;
    switch (liveGrille!.status) {
      case GrilleStatus.ok:
        return EstadoRejilla.operativa;
      case GrilleStatus.warning:
        return EstadoRejilla.alerta;
      case GrilleStatus.urgent:
        return EstadoRejilla.mantenimiento;
    }
  }
}

class FachadaRejillas3DScreen extends StatefulWidget {
  const FachadaRejillas3DScreen({super.key});

  @override
  State<FachadaRejillas3DScreen> createState() =>
      _FachadaRejillas3DScreenState();
}

class _FachadaRejillas3DScreenState extends State<FachadaRejillas3DScreen> {
  late final List<RejillaModel> _rejillas;
  RejillaModel? _seleccionada;
  bool _isConnected = false;
  Map<String, String>? _activeOperator;

  // Notificador reactivo aislado para los parámetros de cámara 3D (evita re-ejecutar build() de toda la pantalla)
  late final ValueNotifier<CameraState> _cameraNotifier;

  bool _mostrarEtiquetas = true;
  bool _modoEstadoColor = true;

  @override
  void initState() {
    super.initState();
    _rejillas = _inicializar22Rejillas();
    _cameraNotifier = ValueNotifier(const CameraState(
      camX: -2.35,
      camY: 1.75,
      camZ: 14.8,
      yaw: 0.03,
      pitch: 0.04,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOperatorLogin();
    });
  }

  Future<void> _checkOperatorLogin() async {
    const deviceId = 'WEB-DEVICE-001';

    // 1. Consultar estado general del sistema (licencia y empleados)
    final status = await ApiService.checkSystemStatus(deviceId: deviceId);
    if (!mounted) return;

    // 2. Si el producto NO está activado, exigir activación por Licencia + PIN Admin
    bool isActivated = status?['isActivated'] == true;
    while (!isActivated && mounted) {
      isActivated = await ProductActivationDialog.show(context, deviceId: deviceId);
    }
    if (!mounted) return;

    // 3. Si no existen operarios creados en el sistema, ejecutar Onboarding / Configuración Inicial
    bool hasEmployees = status?['hasEmployees'] == true;
    if (!hasEmployees && mounted) {
      final setupResult = await InitialSetupDialog.show(context);
      if (setupResult != null && mounted) {
        setState(() => _activeOperator = setupResult);
        context.read<GrilleCubit>().loadGrilles();
        return;
      }
    }
    if (!mounted) return;

    // 4. Verificar si existe sesión de operario activa en servidor online
    final onlineSession = await ApiService.checkOperatorSession(deviceId: deviceId);
    if (onlineSession != null && onlineSession['active'] == true && mounted) {
      final code = onlineSession['payrollCode'] as String;
      final name = onlineSession['name'] as String;
      await LocalDbService.saveActiveOperator(code, name);
      setState(() => _activeOperator = {'code': code, 'name': name});
      return;
    }

    // 5. Verificar sesión guardada localmente o pedir Login de Operario
    final active = await LocalDbService.getActiveOperator();
    if (mounted) {
      if (active != null) {
        setState(() => _activeOperator = active);
      } else {
        Map<String, String>? result;
        while (result == null && mounted) {
          result = await OperatorLoginDialog.show(context, canDismiss: false);
        }
        if (result != null && mounted) {
          setState(() => _activeOperator = result);
        }
      }
    }
  }

  Future<void> _openOperatorLogin() async {
    final canDismiss = _activeOperator != null;
    final result = await OperatorLoginDialog.show(context, canDismiss: canDismiss);
    if (result != null && mounted) {
      setState(() => _activeOperator = result);
    }
  }

  @override
  void dispose() {
    _cameraNotifier.dispose();
    super.dispose();
  }

  void _fetchLiveData() {
    context.read<GrilleCubit>().loadGrilles();
  }

  void _syncWithLiveData(List<Grille> liveGrilles) {
    final Map<String, Grille> grilleMap = {
      for (var g in liveGrilles) g.code: g,
      for (var g in liveGrilles) g.code.replaceAll('R', 'R-'): g,
    };

    for (var r in _rejillas) {
      final codeNorm = r.codigo.replaceAll('-', '');
      r.liveGrille = grilleMap[codeNorm] ?? grilleMap[r.codigo];
    }
  }

  List<RejillaModel> _inicializar22Rejillas() {
    final List<RejillaModel> lista = [];
    final List<double> posicionesX = [
      // MG-01 Bloque Izquierdo (4 columnas: 0..3)
      -9.30, -7.55, -5.80, -4.05,
      // MG-02 Bloque Central (3 columnas: 4..6)
      -1.65, 0.10, 1.85,
      // MG-03 Bloque Derecho (4 columnas: 7..10)
      4.15, 5.90, 7.65, 9.40,
    ];

    // Estructura de bloques de rejillas según elevación 2D real:
    // MG-01: Superior [R01..R04], Inferior [R05..R08]
    // MG-02: Superior [R09..R11], Inferior [R12..R14]
    // MG-03: Superior [R15..R18], Inferior [R19..R22]
    final List<Map<String, dynamic>> defBloques = [
      {'bloque': 0, 'cols': [0, 1, 2, 3], 'topRange': [1, 4], 'botRange': [5, 8]},
      {'bloque': 1, 'cols': [4, 5, 6], 'topRange': [9, 11], 'botRange': [12, 14]},
      {'bloque': 2, 'cols': [7, 8, 9, 10], 'topRange': [15, 18], 'botRange': [19, 22]},
    ];

    for (var b in defBloques) {
      final int bloque = b['bloque'];
      final List<int> cols = b['cols'];
      final List<int> topRange = b['topRange'];
      final List<int> botRange = b['botRange'];

      // Fila Superior (fila = 0, posY = 3.55)
      for (int i = 0; i < cols.length; i++) {
        final int id = topRange[0] + i;
        final int colIdx = cols[i];
        lista.add(RejillaModel(
          id: id,
          codigo: 'R${id.toString().padLeft(2, '0')}',
          fila: 0,
          bloque: bloque,
          indiceEnFila: colIdx,
          worldX: posicionesX[colIdx],
          worldY: 3.55,
          temperaturaC: 36.0 + (id % 5) * 1.8,
          caudalPorcentaje: 80.0 + (id % 4) * 5.0,
        ));
      }

      // Fila Inferior (fila = 1, posY = 1.95)
      for (int i = 0; i < cols.length; i++) {
        final int id = botRange[0] + i;
        final int colIdx = cols[i];
        lista.add(RejillaModel(
          id: id,
          codigo: 'R${id.toString().padLeft(2, '0')}',
          fila: 1,
          bloque: bloque,
          indiceEnFila: colIdx,
          worldX: posicionesX[colIdx],
          worldY: 1.95,
          temperaturaC: 36.0 + (id % 5) * 1.8,
          caudalPorcentaje: 80.0 + (id % 4) * 5.0,
        ));
      }
    }
    return lista;
  }

  void _restaurarCamaraFoto() {
    _cameraNotifier.value = const CameraState(
      camX: -2.35,
      camY: 1.75,
      camZ: 14.8,
      yaw: 0.03,
      pitch: 0.04,
    );
  }

  /// Calcula la proyección 2D del área táctil para hit testing al tocar
  Path _calcularHitPathParaRejilla(RejillaModel r, Size size) {
    final cam = _cameraNotifier.value;
    final focalLength = size.width * 0.62;
    final screenCenter = Offset(size.width * 0.47, size.height * 0.56);

    Offset project(double wx, double wy, double wz) {
      double dx = wx - cam.camX;
      double dy = wy - cam.camY;
      double dz = wz - cam.camZ;

      final double cosY = math.cos(cam.yaw);
      final double sinY = math.sin(cam.yaw);
      final double rx = dx * cosY - dz * sinY;
      final double rz1 = dx * sinY + dz * cosY;

      final double cosP = math.cos(cam.pitch);
      final double sinP = math.sin(cam.pitch);
      final double ry = dy * cosP - rz1 * sinP;
      final double rz = dy * sinP + rz1 * cosP;

      final double depth = (-rz).clamp(0.4, 200.0);
      final double sx = screenCenter.dx + (rx / depth) * focalLength;
      final double sy = screenCenter.dy - (ry / depth) * focalLength;
      return Offset(sx, sy);
    }

    const double halfW = 0.77;
    const double halfH = 0.62;
    const double zWall = 0.0;
    const double zTop = 0.92;
    const double zBot = 0.36;

    final double xL = r.worldX - halfW;
    final double xR = r.worldX + halfW;
    final double yT = r.worldY + halfH;
    final double yB = r.worldY - halfH;

    // Todos los puntos 3D proyectados (carcasa, visera y etiqueta R01-R22)
    final pts = [
      project(xL, yT, zWall),
      project(xR, yT, zWall),
      project(xR, yB, zWall),
      project(xL, yB, zWall),
      project(xL, yT, zTop),
      project(xR, yT, zTop),
      project(xR, yB, zBot),
      project(xL, yB, zBot),
      project(r.worldX, r.worldY, zTop + 0.05),
    ];

    double minX = pts.first.dx;
    double maxX = pts.first.dx;
    double minY = pts.first.dy;
    double maxY = pts.first.dy;

    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    // Margen holgado táctil (12px) para sensibilidad perfecta en pantallas móviles
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(12.0);
    return Path()..addRect(rect);
  }

  void _detectarToque(Offset localPosition, Size canvasSize) {
    final cam = _cameraNotifier.value;
    final List<RejillaModel> ordenadas = List.of(_rejillas)
      ..sort((a, b) {
        final distA = (a.worldX - cam.camX).abs() + (a.worldY - cam.camY).abs() * 0.4;
        final distB = (b.worldX - cam.camX).abs() + (b.worldY - cam.camY).abs() * 0.4;
        return distA.compareTo(distB);
      });

    for (final r in ordenadas) {
      final path = _calcularHitPathParaRejilla(r, canvasSize);
      if (path.contains(localPosition)) {
        setState(() {
          _seleccionada = (_seleccionada?.id == r.id) ? null : r;
        });
        return;
      }
    }
    setState(() => _seleccionada = null);
  }

  Future<void> _openMaintenanceDialog(RejillaModel r) async {
    if (r.liveGrille == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MaintenanceDialog(grille: r.liveGrille!),
    );

    if (result == true) {
      if (mounted) {
        context.read<GrilleCubit>().loadGrilles();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Mantenimiento registrado y guardado en SQLite.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GrilleCubit, GrilleState>(
      listener: (context, state) {
        if (state is GrilleLoaded) {
          setState(() {
            _isConnected = state.isConnected;
            _syncWithLiveData(state.grilles);
          });
        }
      },
      builder: (context, state) {
        if (state is GrilleLoaded && _rejillas.first.liveGrille == null) {
          _isConnected = state.isConnected;
          _syncWithLiveData(state.grilles);
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: const Text(
              'Tiroforzados Cogeneracion 13.200VAC',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: const Color(0xFF1B2228),
            actions: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _mostrarEtiquetas ? Icons.label : Icons.label_outlined,
                  color: _mostrarEtiquetas ? Colors.amber : Colors.white54,
                  size: 20,
                ),
                tooltip: _mostrarEtiquetas
                    ? 'Ocultar Etiquetas'
                    : 'Mostrar Etiquetas (R01-R22)',
                onPressed: () =>
                    setState(() => _mostrarEtiquetas = !_mostrarEtiquetas),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _modoEstadoColor ? Icons.traffic : Icons.traffic_outlined,
                  color: _modoEstadoColor ? Colors.amber : Colors.white54,
                  size: 20,
                ),
                tooltip:
                    _modoEstadoColor ? 'Modo Normal' : 'Modo Semáforo SCADA',
                onPressed: () =>
                    setState(() => _modoEstadoColor = !_modoEstadoColor),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.camera_alt_outlined,
                    size: 20, color: Colors.white70),
                onPressed: _restaurarCamaraFoto,
                tooltip: 'Ángulo Foto Original',
              ),
              Builder(
                builder: (context) {
                  final pendingCount =
                      state is GrilleLoaded ? state.pendingCount : 0;
                  final badgeColor = _isConnected
                      ? (pendingCount > 0
                          ? Colors.amber.shade900
                          : Colors.green.shade800)
                      : (pendingCount > 0
                          ? Colors.orange.shade900
                          : Colors.blueGrey.shade800);
                  final badgeText = _isConnected
                      ? (pendingCount > 0
                          ? 'Sincronizando ($pendingCount)'
                          : 'API Local')
                      : (pendingCount > 0
                          ? 'Modo Local ($pendingCount pend.)'
                          : 'Modo Local');

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _openOperatorLogin,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: _activeOperator != null ? Colors.cyan.shade900 : Colors.blueGrey.shade900,
                            border: Border.all(color: _activeOperator != null ? Colors.cyanAccent : Colors.white24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person, size: 11, color: Colors.cyanAccent),
                              const SizedBox(width: 3),
                              Text(
                                _activeOperator != null ? _activeOperator!['code']! : 'Ingresar',
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isConnected ? Icons.wifi : Icons.sd_storage,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              badgeText,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _fetchLiveData,
                tooltip: 'Actualizar Datos',
              ),
            ],
          ),
          drawer: const AppDrawer(currentRoute: '3d'),
          body: Stack(
            children: [
              // Lienzo 3D interactivo aislado con ValueListenableBuilder + RepaintBoundary
              LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return ValueListenableBuilder<CameraState>(
                    valueListenable: _cameraNotifier,
                    builder: (context, cam, child) {
                      return GestureDetector(
                        onPanUpdate: (details) {
                          _cameraNotifier.value = cam.copyWith(
                            camX: (cam.camX - details.delta.dx * 0.025)
                                .clamp(-10.0, 10.0),
                            camY: (cam.camY + details.delta.dy * 0.020)
                                .clamp(0.7, 6.5),
                            yaw: (cam.yaw + details.delta.dx * 0.0012)
                                .clamp(-0.35, 0.35),
                            pitch: (cam.pitch - details.delta.dy * 0.0012)
                                .clamp(-0.20, 0.25),
                          );
                        },
                        onTapUp: (details) {
                          _detectarToque(details.localPosition, canvasSize);
                        },
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: canvasSize,
                            painter: EdificioCogeneracion3DPainter(
                              rejillas: _rejillas,
                              seleccionadaId: _seleccionada?.id,
                              camX: cam.camX,
                              camY: cam.camY,
                              camZ: cam.camZ,
                              yaw: cam.yaw,
                              pitch: cam.pitch,
                              mostrarEtiquetas: _mostrarEtiquetas,
                              modoEstadoColor: _modoEstadoColor,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              // Controles flotantes de cámara y zoom
              Positioned(
                left: 16,
                bottom: 16,
                child: _buildControlesCamara(),
              ),

              // Panel de telemetría y mantenimiento al seleccionar una de las 22 rejillas
              if (_seleccionada != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _buildPanelInspector(_seleccionada!),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlesCamara() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.threed_rotation, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          const Text(
            'Arrastra para mover 3D | Toca una rejilla',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Acercar',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.zoom_in, size: 20, color: Colors.white),
            onPressed: () {
              final cam = _cameraNotifier.value;
              _cameraNotifier.value = cam.copyWith(
                camZ: (cam.camZ - 1.2).clamp(8.5, 22.0),
              );
            },
          ),
          IconButton(
            tooltip: 'Alejar',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.zoom_out, size: 20, color: Colors.white),
            onPressed: () {
              final cam = _cameraNotifier.value;
              _cameraNotifier.value = cam.copyWith(
                camZ: (cam.camZ + 1.2).clamp(8.5, 22.0),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanelInspector(RejillaModel r) {
    final String nombreBloque = r.bloque == 0
        ? 'MG-01 (Izquierdo)'
        : (r.bloque == 1 ? 'MG-02 (Centro)' : 'MG-03 (Derecho)');
    final String nombreFila =
        r.fila == 0 ? 'Fila Superior' : 'Fila Inferior';

    final maxDays = r.liveGrille?.maxDaysWithoutMaintenance ?? 30;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2228).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rejilla ${r.codigo}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyanAccent,
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                onPressed: () => setState(() => _seleccionada = null),
              ),
            ],
          ),
          const Divider(height: 12, color: Colors.white24),
          Text(
            'Bloque: $nombreBloque',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Text(
            'Ubicación: $nombreFila',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _datoMetrica('Días sin cambio', '$maxDays días'),
              _datoMetrica(
                  'Estado SCADA',
                  r.estado == EstadoRejilla.operativa
                      ? '🟢 OK'
                      : r.estado == EstadoRejilla.alerta
                          ? '🟡 Alerta'
                          : '🔴 Urgente'),
            ],
          ),
          const SizedBox(height: 10),

          // Filters 4 status
          if (r.liveGrille != null) ...[
            const Text(
              'Estado Filtros Internos (4):',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: r.liveGrille!.filters.map((f) {
                final color = f.status == GrilleStatus.ok
                    ? Colors.green
                    : f.status == GrilleStatus.warning
                        ? Colors.orange
                        : Colors.red;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'F${f.filterNumber}: ${f.daysSinceReplacement}d',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Maintenance Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _openMaintenanceDialog(r),
              icon: const Icon(Icons.build_circle, size: 18),
              label: const Text(
                'Registrar Mantenimiento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _datoMetrica(String titulo, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          Text(
            valor,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Motor de Proyección 3D Fotorrealista para la Fachada y las 22 Rejillas
class EdificioCogeneracion3DPainter extends CustomPainter {
  final List<RejillaModel> rejillas;
  final int? seleccionadaId;
  final double camX;
  final double camY;
  final double camZ;
  final double yaw;
  final double pitch;
  final bool mostrarEtiquetas;
  final bool modoEstadoColor;

  EdificioCogeneracion3DPainter({
    required this.rejillas,
    required this.seleccionadaId,
    required this.camX,
    required this.camY,
    required this.camZ,
    required this.yaw,
    required this.pitch,
    required this.mostrarEtiquetas,
    required this.modoEstadoColor,
  });

  late double _focalLength;
  late Offset _screenCenter;

  Offset _project(double wx, double wy, double wz) {
    double dx = wx - camX;
    double dy = wy - camY;
    double dz = wz - camZ;

    final double cosY = math.cos(yaw);
    final double sinY = math.sin(yaw);
    final double rx = dx * cosY - dz * sinY;
    final double rz1 = dx * sinY + dz * cosY;

    final double cosP = math.cos(pitch);
    final double sinP = math.sin(pitch);
    final double ry = dy * cosP - rz1 * sinP;
    final double rz = dy * sinP + rz1 * cosP;

    final double depth = (-rz).clamp(0.4, 200.0);
    final double sx = _screenCenter.dx + (rx / depth) * _focalLength;
    final double sy = _screenCenter.dy - (ry / depth) * _focalLength;
    return Offset(sx, sy);
  }

  Path _poly(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _focalLength = size.width * 0.62;
    _screenCenter = Offset(size.width * 0.47, size.height * 0.56);

    _dibujarCieloNublado(canvas, size);
    _dibujarVialidadYPiso3D(canvas, size);
    _dibujarCubiertasSuperiores3D(canvas);
    _dibujarMuroYPortones3D(canvas);

    final List<RejillaModel> ordenadas = List.of(rejillas)
      ..sort((a, b) {
        final distA = (a.worldX - camX).abs() + (a.worldY - camY).abs() * 0.4;
        final distB = (b.worldX - camX).abs() + (b.worldY - camY).abs() * 0.4;
        return distB.compareTo(distA);
      });

    for (final r in ordenadas) {
      _dibujarRejillaCapota3D(canvas, r);
    }

    _dibujarPostesIluminacion3D(canvas);
  }

  void _dibujarCieloNublado(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFC8D2DC),
          Color(0xFFDCE3EA),
          Color(0xFFBCC4CC),
        ],
        stops: [0.0, 0.42, 0.72],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);
  }

  void _dibujarVialidadYPiso3D(Canvas canvas, Size size) {
    final pAsfalto = _poly([
      _project(-22, 0, 0),
      _project(22, 0, 0),
      _project(22, 0, 14.2),
      _project(-22, 0, 14.2),
    ]);
    canvas.drawPath(
      pAsfalto,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF474C50), Color(0xFF5A5E62)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      _poly([
        _project(-13.5, 0.02, 0),
        _project(13.5, 0.02, 0),
        _project(13.5, 0.02, 2.3),
        _project(-13.5, 0.02, 2.3),
      ]),
      Paint()..color = const Color(0xFF7B7E7A),
    );

    canvas.drawPath(
      _poly([
        _project(-15.5, 0.03, 2.3),
        _project(15.5, 0.03, 2.3),
        _project(15.5, 0.03, 2.55),
        _project(-15.5, 0.03, 2.55),
      ]),
      Paint()..color = const Color(0xFFD69A2A),
    );

    canvas.drawPath(
      _poly([
        _project(-16.5, 0.02, 2.55),
        _project(16.5, 0.02, 2.55),
        _project(16.5, 0.02, 4.15),
        _project(-16.5, 0.02, 4.15),
      ]),
      Paint()..color = const Color(0xFF2874A6),
    );

    final lineaAmarillaPaint = Paint()
      ..color = const Color(0xFFD99B26)
      ..strokeWidth = 5.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      _project(-14.0, 0.02, 9.2),
      _project(14.0, 0.02, 8.6),
      lineaAmarillaPaint,
    );
    canvas.drawLine(
      _project(-11.0, 0.02, 13.8),
      _project(-0.4, 0.02, 8.9),
      lineaAmarillaPaint,
    );
    canvas.drawLine(
      _project(-0.4, 0.02, 8.9),
      _project(2.0, 0.02, 14.0),
      lineaAmarillaPaint,
    );
    canvas.drawLine(
      _project(-0.1, 0.02, 8.9),
      _project(2.35, 0.02, 14.0),
      lineaAmarillaPaint,
    );
  }

  void _dibujarCubiertasSuperiores3D(Canvas canvas) {
    final yellowRackPaint = Paint()
      ..color = const Color(0xFFC9972C)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      _project(-15.5, 4.6, 0.5),
      _project(-10.5, 4.2, 0.5),
      yellowRackPaint,
    );
    canvas.drawLine(
      _project(-15.5, 5.5, 0.5),
      _project(-10.5, 4.9, 0.5),
      yellowRackPaint,
    );

    final List<double> centrosBahia = [-6.2, -0.2, 5.8];
    for (final cx in centrosBahia) {
      canvas.drawPath(
        _poly([
          _project(cx - 3.1, 4.9, -0.4),
          _project(cx + 3.1, 4.9, -0.4),
          _project(cx + 3.1, 6.45, -0.4),
          _project(cx - 3.1, 6.45, -0.4),
        ]),
        Paint()..color = const Color(0xFF283339),
      );

      canvas.drawPath(
        _poly([
          _project(cx - 3.2, 6.45, -0.1),
          _project(cx + 3.2, 6.45, -0.1),
          _project(cx + 3.2, 6.85, -2.5),
          _project(cx - 3.2, 6.85, -2.5),
        ]),
        Paint()..color = const Color(0xFF425B63),
      );

      canvas.drawPath(
        _poly([
          _project(cx - 1.2, 4.9, -0.5),
          _project(cx + 1.2, 4.9, -0.5),
          _project(cx + 1.4, 6.6, -0.5),
          _project(cx - 1.4, 6.6, -0.5),
        ]),
        Paint()..color = const Color(0xFF9EA6AB),
      );

      final cagePaint = Paint()
        ..color = const Color(0xFFC5A24A)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        _poly([
          _project(cx - 1.4, 6.6, -0.3),
          _project(cx + 1.4, 6.6, -0.3),
          _project(cx + 1.4, 7.35, -0.3),
          _project(cx - 1.4, 7.35, -0.3),
        ]),
        cagePaint,
      );
    }

    final railPaint = Paint()
      ..color = const Color(0xFFD1A138)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      _project(-10.2, 5.45, 0.1),
      _project(10.2, 5.45, 0.1),
      railPaint,
    );
    canvas.drawLine(
      _project(-10.2, 5.15, 0.1),
      _project(10.2, 5.15, 0.1),
      railPaint,
    );
    for (double x = -10.0; x <= 10.0; x += 1.25) {
      canvas.drawLine(
        _project(x, 4.85, 0.1),
        _project(x, 5.45, 0.1),
        railPaint,
      );
    }
  }

  void _dibujarMuroYPortones3D(Canvas canvas) {
    canvas.drawPath(
      _poly([
        _project(-13.2, 0.0, 0.15),
        _project(-10.4, 0.0, 0.15),
        _project(-10.4, 2.75, 0.15),
        _project(-13.2, 2.75, 0.15),
      ]),
      Paint()..color = const Color(0xFF174A2E),
    );
    canvas.drawPath(
      _poly([
        _project(-12.5, 1.35, 0.18),
        _project(-11.2, 1.35, 0.18),
        _project(-11.2, 2.15, 0.18),
        _project(-12.5, 2.15, 0.18),
      ]),
      Paint()..color = const Color(0xFFDCE4E0),
    );

    canvas.drawPath(
      _poly([
        _project(10.4, 0.0, 0.1),
        _project(13.8, 0.0, 0.1),
        _project(13.8, 2.8, 0.1),
        _project(10.4, 2.8, 0.1),
      ]),
      Paint()..color = const Color(0xFF174A2E),
    );

    canvas.drawPath(
      _poly([
        _project(-10.5, 0.92, 0.0),
        _project(10.5, 0.92, 0.0),
        _project(10.5, 4.88, 0.0),
        _project(-10.5, 4.88, 0.0),
      ]),
      Paint()..color = const Color(0xFFD5D8D6),
    );

    canvas.drawPath(
      _poly([
        _project(-10.5, 0.0, 0.02),
        _project(10.5, 0.0, 0.02),
        _project(10.5, 0.92, 0.02),
        _project(-10.5, 0.92, 0.02),
      ]),
      Paint()..color = const Color(0xFF133322),
    );

    final pipePaint = Paint()
      ..color = const Color(0xFFC5CAC7)
      ..strokeWidth = 2.5;
    canvas.drawLine(
      _project(-6.05, 0.0, 0.05),
      _project(-6.05, 0.92, 0.05),
      pipePaint,
    );
    canvas.drawLine(
      _project(-5.65, 0.0, 0.05),
      _project(-5.65, 0.92, 0.05),
      pipePaint,
    );

    final juntaPaint = Paint()
      ..color = const Color(0xFF9DA29E)
      ..strokeWidth = 2.2;
    canvas.drawLine(
      _project(-2.85, 0.92, 0.02),
      _project(-2.85, 4.75, 0.02),
      juntaPaint,
    );
    canvas.drawLine(
      _project(3.00, 0.92, 0.02),
      _project(3.00, 4.75, 0.02),
      juntaPaint,
    );

    final tuberiaSupPaint = Paint()
      ..color = const Color(0xFFC8CCC9)
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      _project(-10.6, 4.62, 0.25),
      _project(10.5, 4.62, 0.25),
      tuberiaSupPaint,
    );
  }

  void _dibujarRejillaCapota3D(Canvas canvas, RejillaModel r) {
    const double halfW = 0.77;
    const double halfH = 0.62;
    const double zWall = 0.0;
    const double zTop = 0.92;
    const double zBot = 0.36;

    final double xL = r.worldX - halfW;
    final double xR = r.worldX + halfW;
    final double yT = r.worldY + halfH;
    final double yB = r.worldY - halfH;

    final shadowPath = _poly([
      _project(xL + 0.08, yT - 0.05, 0.01),
      _project(xR + 0.14, yT - 0.05, 0.01),
      _project(xR + 0.14, yB - 0.18, 0.01),
      _project(xL + 0.08, yB - 0.18, 0.01),
    ]);
    canvas.drawPath(
      shadowPath,
      Paint()..color = Colors.black.withValues(alpha: 0.26),
    );

    final Offset wTL = _project(xL, yT, zWall);
    final Offset wTR = _project(xR, yT, zWall);
    final Offset wBL = _project(xL, yB, zWall);
    final Offset wBR = _project(xR, yB, zWall);

    final Offset fTL = _project(xL, yT, zTop);
    final Offset fTR = _project(xR, yT, zTop);
    final Offset fBL = _project(xL, yB, zBot);
    final Offset fBR = _project(xR, yB, zBot);

    const Color colorCarcasaFrontal = Color(0xFFE3E6E4);
    Color statusVividColor = const Color(0xFF00E676); // Default green
    const Color colorLateralIzq = Color(0xFFECEFED);
    const Color colorLateralDer = Color(0xFFBDC2BF);

    switch (r.estado) {
      case EstadoRejilla.operativa:
        statusVividColor = const Color(0xFF00E676); // Vibrant Electric Green
        break;
      case EstadoRejilla.alerta:
        statusVividColor = const Color(0xFFFFD600); // Vibrant Bright Yellow
        break;
      case EstadoRejilla.mantenimiento:
        statusVividColor = const Color(0xFFFF1744); // Vibrant Neon Red
        break;
      case EstadoRejilla.apagada:
        statusVividColor = const Color(0xFF78909C);
        break;
    }

    if (camY < yB) {
      canvas.drawPath(
        _poly([wBL, wBR, fBR, fBL]),
        Paint()..color = const Color(0xFF8C918E),
      );
    }

    if (camY > yT) {
      canvas.drawPath(
        _poly([wTL, wTR, fTR, fTL]),
        Paint()..color = const Color(0xFFF2F5F3),
      );
    }

    if (camX < xL) {
      final sideLeft = _poly([wTL, fTL, fBL, wBL]);
      canvas.drawPath(sideLeft, Paint()..color = colorLateralIzq);
      canvas.drawPath(
        sideLeft,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    } else if (camX > xR) {
      final sideRight = _poly([wTR, fTR, fBR, wBR]);
      canvas.drawPath(sideRight, Paint()..color = colorLateralDer);
      canvas.drawPath(
        sideRight,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    final frontPath = _poly([fTL, fTR, fBR, fBL]);
    canvas.drawPath(frontPath, Paint()..color = colorCarcasaFrontal);

    final double yVisera = yT - 0.14;
    final double zVisera = zTop - 0.06;
    canvas.drawPath(
      _poly([
        fTL,
        fTR,
        _project(xR, yVisera, zVisera),
        _project(xL, yVisera, zVisera),
      ]),
      Paint()..color = const Color(0xFFEDEFEB),
    );

    const double padX = 0.08;
    const double padTop = 0.16;
    const double padBot = 0.07;

    final double ixL = xL + padX;
    final double ixR = xR - padX;
    final double iyT = yT - padTop;
    final double iyB = yB + padBot;

    double zEnY(double yVal) {
      final double t = (yVal - yB) / (yT - yB);
      return zBot + t * (zTop - zBot);
    }

    final innerCavity = _poly([
      _project(ixL, iyT, zEnY(iyT)),
      _project(ixR, iyT, zEnY(iyT)),
      _project(ixR, iyB, zEnY(iyB)),
      _project(ixL, iyB, zEnY(iyB)),
    ]);
    canvas.drawPath(innerCavity, Paint()..color = const Color(0xFF2B2E2C));

    final double midX = (ixL + ixR) * 0.5;
    canvas.drawLine(
      _project(midX, iyT, zEnY(iyT)),
      _project(midX, iyB, zEnY(iyB)),
      Paint()
        ..color = const Color(0xFF1E201F)
        ..strokeWidth = 1.6,
    );

    const int numLamas = 14;
    final lamaPaint = Paint()
      ..color = const Color(0xFFB5BAB7)
      ..strokeWidth = 1.65;

    for (int i = 1; i <= numLamas; i++) {
      final double frac = i / (numLamas + 1);
      final double ly = iyB + frac * (iyT - iyB);
      final double lz = zEnY(ly) + 0.01;
      canvas.drawLine(
        _project(ixL, ly, lz),
        _project(ixR, ly, lz),
        lamaPaint,
      );
    }

    final bool esSeleccionada = r.id == seleccionadaId;

    canvas.drawPath(
      frontPath,
      Paint()
        ..color = esSeleccionada ? Colors.cyanAccent : Colors.black38
        ..style = PaintingStyle.stroke
        ..strokeWidth = esSeleccionada ? 3.5 : 1.0,
    );

    // 3D Status LED Light Beacon on Top-Right Corner of Hood
    final Offset ledPos =
        _project(xR - 0.18, yT - 0.10, zTop + 0.05);
    // Outer glow halo
    canvas.drawCircle(
      ledPos,
      7.0,
      Paint()..color = statusVividColor.withValues(alpha: 0.45),
    );
    // Inner LED bulb
    canvas.drawCircle(
      ledPos,
      4.2,
      Paint()..color = statusVividColor,
    );
    canvas.drawCircle(
      ledPos,
      1.8,
      Paint()..color = Colors.white,
    );

    // Tag Badge (R01-R22) with Vivid Status Background
    if (mostrarEtiquetas || esSeleccionada) {
      final Offset centro =
          _project(r.worldX, r.worldY, zEnY(r.worldY) + 0.05);
      final tp = TextPainter(
        text: TextSpan(
          text: r.codigo,
          style: TextStyle(
            color: (r.estado == EstadoRejilla.alerta && !esSeleccionada)
                ? Colors.black
                : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = Rect.fromCenter(
        center: centro,
        width: tp.width + 10,
        height: tp.height + 6,
      );

      final Color badgeBg = esSeleccionada
          ? Colors.cyanAccent
          : modoEstadoColor
              ? statusVividColor
              : Colors.black.withValues(alpha: 0.85);

      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(5)),
        Paint()..color = badgeBg,
      );
      // Border around badge
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(5)),
        Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      tp.paint(canvas, Offset(bgRect.left + 5, bgRect.top + 3));
    }
  }

  void _dibujarPostesIluminacion3D(Canvas canvas) {
    final List<double> posPostesX = [-9.3, -2.5, 3.6, 8.9];
    final postePaint = Paint()
      ..color = const Color(0xFF4F5659)
      ..strokeWidth = 3.0;

    for (final px in posPostesX) {
      final Offset base = _project(px, 4.85, 0.15);
      final Offset tope = _project(px, 6.75, 0.15);
      canvas.drawLine(base, tope, postePaint);

      canvas.drawCircle(
        tope.translate(-4, -2),
        3.5,
        Paint()..color = const Color(0xFF373D40),
      );
      canvas.drawCircle(
        tope.translate(4, -2),
        3.5,
        Paint()..color = const Color(0xFF373D40),
      );
    }
  }

  @override
  bool shouldRepaint(covariant EdificioCogeneracion3DPainter oldDelegate) {
    return oldDelegate.camX != camX ||
        oldDelegate.camY != camY ||
        oldDelegate.camZ != camZ ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.seleccionadaId != seleccionadaId ||
        oldDelegate.mostrarEtiquetas != mostrarEtiquetas ||
        oldDelegate.modoEstadoColor != modoEstadoColor ||
        oldDelegate.rejillas != rejillas;
  }
}
