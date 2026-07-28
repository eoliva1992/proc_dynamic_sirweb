import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/procedimientos_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const ProcDynamicApp());
}

class ProcDynamicApp extends StatelessWidget {
  const ProcDynamicApp({super.key});

  static ThemeData _buildDarkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF0078D4),
        surface: Color(0xFF252526),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF323233),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFCCCCCC)),
      ),
      cardTheme: const CardThemeData(color: Color(0xFF252526), elevation: 0),
      dividerColor: const Color(0xFF3C3C3C),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0078D4),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2C2C2C),
        elevation: 1,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: const CardThemeData(color: Colors.white, elevation: 1),
      dividerColor: Colors.grey.shade300,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProcedimientosProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Procedimientos Dinámicos',
            debugShowCheckedModeBanner: false,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: themeProvider.themeMode,
            home: const MainScreen(),
          );
        },
      ),
    );
  }
}



// graphify watch test 08:44:12
