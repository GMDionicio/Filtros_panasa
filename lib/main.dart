import 'package:flutter/material.dart';
import 'interfaz.dart';

void main() {
  runApp(const FiltrosPanasa3DApp());
}

class FiltrosPanasa3DApp extends StatelessWidget {
  const FiltrosPanasa3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Filtros Panasa — Gemelo Digital 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12161A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0077C8),
          secondary: Color(0xFFE5A93B),
        ),
      ),
      home: const FachadaRejillas3DScreen(),
    );
  }
}
