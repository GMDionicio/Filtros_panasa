import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/models.dart';

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
