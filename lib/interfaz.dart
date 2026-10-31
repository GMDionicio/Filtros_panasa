import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/grille_cubit.dart';
import 'di/service_locator.dart';
import 'models/models.dart';
import 'painters/edificio_3d_painter.dart';
import 'repositories/employee_repository.dart';
import 'screens/maintenance_dialog.dart';
import 'services/api_service.dart';
import 'services/local_db_service.dart';
import 'widgets/app_drawer.dart';
import 'widgets/blocking_login_screen.dart';
import 'widgets/initial_setup_dialog.dart';
import 'widgets/operator_login_dialog.dart';
import 'widgets/product_activation_dialog.dart';

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
    final deviceId = await LocalDbService.getOrCreateDeviceId();

    // 1. Consultar estado general del sistema (remoto y local)
    final status = await ApiService.checkSystemStatus(deviceId: deviceId);
    if (!mounted) return;

    final localEmps = await getIt<IEmployeeRepository>().getEmployees();
    if (!mounted) return;

    // 2. Si el producto NO está activado y no hay datos locales previa activación, exigir activación
    bool isActivated = status?['isActivated'] == true || localEmps.isNotEmpty;
    while (!isActivated && mounted) {
      isActivated = await ProductActivationDialog.show(context, deviceId: deviceId);
    }
    if (!mounted) return;

    // 3. Si no existen operarios creados en el sistema, ejecutar Configuración Inicial
    bool hasEmployees = status?['hasEmployees'] == true || localEmps.isNotEmpty;
    if (!hasEmployees && mounted) {
      final setupResult = await InitialSetupDialog.show(context);
      if (setupResult != null && mounted) {
        setState(() => _activeOperator = setupResult);
        context.read<GrilleCubit>().loadGrilles();
        return;
      }
    }
    if (!mounted) return;

    // 4. Verificar sesión guardada localmente y validar token contra el servidor si está online
    Map<String, String>? active = await LocalDbService.getActiveOperator();
    if (active != null) {
      final hasToken = active['token'] != null && active['token']!.isNotEmpty;
      if (!hasToken && status != null) {
        // Sesión antigua sin Bearer token: re-autenticar para obtener token del servidor
        final loginData = await ApiService.loginOperator(
          payrollCode: active['code']!,
          deviceId: deviceId,
        );
        if (loginData != null && loginData['token'] != null) {
          await LocalDbService.saveActiveOperator(
            active['code']!,
            loginData['name'] ?? active['name']!,
            token: loginData['token'],
          );
          active = await LocalDbService.getActiveOperator();
        } else {
          await LocalDbService.clearActiveOperator();
          active = null;
        }
      } else if (hasToken && status != null) {
        final sessionCheck = await ApiService.checkOperatorSession(deviceId: deviceId);
        if (sessionCheck == null || sessionCheck['active'] != true) {
          // Intentar renovar sesión automáticamente con el código de nómina actual
          final renewed = await ApiService.loginOperator(
            payrollCode: active['code']!,
            deviceId: deviceId,
          );
          if (renewed != null && renewed['token'] != null) {
            await LocalDbService.saveActiveOperator(
              active['code']!,
              renewed['name'] ?? active['name']!,
              token: renewed['token'],
            );
            active = await LocalDbService.getActiveOperator();
          } else {
            await LocalDbService.clearActiveOperator();
            active = null;
          }
        }
      }
    }

    if (!mounted) return;

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

    if (mounted && _activeOperator != null) {
      context.read<GrilleCubit>().loadGrilles();
    }
  }

  Future<void> _openOperatorLogin() async {
    final canDismiss = _activeOperator != null;
    final result = await OperatorLoginDialog.show(context, canDismiss: canDismiss);
    if (result != null && mounted) {
      setState(() => _activeOperator = result);
      context.read<GrilleCubit>().loadGrilles();
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
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => MaintenanceDialog(grille: r.liveGrille!),
    );

    if (result is MaintenanceResult) {
      if (result.isFullSuccess || result.isPartialSuccess) {
        if (mounted) {
          context.read<GrilleCubit>().loadGrilles();

          if (result.isFullSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Mantenimiento registrado correctamente en ${result.successfulFilters.length} filtro(s).',
                ),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ Mantenimiento registrado parcialmente (Exitosos: #${result.successfulFilters.join(", ")}; Fallaron: #${result.failedFilters.join(", ")}).',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } else if (result == true) {
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
    if (_activeOperator == null) {
      return BlockingLoginScreen(
        onLoginSuccess: (op) {
          setState(() => _activeOperator = op);
          context.read<GrilleCubit>().loadGrilles();
        },
      );
    }

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

              // Controles flotantes de cámara y zoom (Elevados para no interferir con botones del sistema)
              () {
                final double bottomInset = MediaQuery.of(context).padding.bottom;
                final double rightInset = MediaQuery.of(context).padding.right;
                final double leftInset = MediaQuery.of(context).padding.left;

                // Elevación suficiente para librar la barra gestual / botones digitales en vertical u horizontal
                final double safeBottom = math.max(bottomInset + 28.0, 32.0);
                final double safeRight = math.max(rightInset + 16.0, 16.0);
                final double safeLeft = math.max(leftInset + 16.0, 16.0);

                final bool isMobileNarrow = MediaQuery.of(context).size.width < 600;

                return Stack(
                  children: [
                    Positioned(
                      left: safeLeft,
                      bottom: safeBottom + (_seleccionada != null && isMobileNarrow ? 240.0 : 0.0),
                      child: _buildControlesCamara(),
                    ),
                    if (_seleccionada != null)
                      Positioned(
                        right: safeRight,
                        left: isMobileNarrow ? safeLeft : null,
                        bottom: safeBottom,
                        child: _buildPanelInspector(_seleccionada!),
                      ),
                  ],
                );
              }(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlesCamara() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.threed_rotation, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          const Text(
            'Vista 3D',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 14),

          // Botón HUD Videojuego Zoom Out (-)
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.3),
              onTap: () {
                final cam = _cameraNotifier.value;
                _cameraNotifier.value = cam.copyWith(
                  camZ: (cam.camZ + 1.2).clamp(8.5, 22.0),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.25),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.remove, size: 26, color: Colors.white),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Botón HUD Videojuego Zoom In (+)
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: Colors.cyanAccent.withValues(alpha: 0.4),
              onTap: () {
                final cam = _cameraNotifier.value;
                _cameraNotifier.value = cam.copyWith(
                  camZ: (cam.camZ - 1.2).clamp(8.5, 22.0),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.add, size: 26, color: Colors.cyanAccent),
                ),
              ),
            ),
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
    final double maxHeight = math.min(380.0, MediaQuery.of(context).size.height * 0.75);

    return Container(
      width: 300,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: SingleChildScrollView(
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
      ),
    );
  }

  Widget _datoMetrica(String titulo, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
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
