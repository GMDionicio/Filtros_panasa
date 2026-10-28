import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/grille_cubit.dart';
import 'di/service_locator.dart';
import 'interfaz.dart';
import 'screens/dashboard_screen.dart';
import 'screens/employees_screen.dart';
import 'services/sync_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  getIt<SyncManager>().initConnectivityListener();
  runApp(const FiltrosPanasa3DApp());
}

class FiltrosPanasa3DApp extends StatelessWidget {
  const FiltrosPanasa3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<GrilleCubit>()..loadGrilles(),
      child: MaterialApp(
        title: 'Filtros Panasa — Gemelo Digital 3D',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF12161A),
          cardColor: const Color(0xFF1B2228),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1B2228),
            foregroundColor: Colors.white,
            elevation: 2,
            iconTheme: IconThemeData(color: Colors.cyanAccent),
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF1B2228),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF1B2228),
            titleTextStyle: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF0077C8),
            secondary: Colors.cyanAccent,
            surface: Color(0xFF1B2228),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const FachadaRejillas3DScreen(),
          '/3d': (context) => const FachadaRejillas3DScreen(),
          '/2d': (context) => const DashboardScreen(),
          '/employees': (context) => const EmployeesScreen(),
        },
      ),
    );
  }
}
