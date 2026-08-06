import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'providers/theme_provider.dart';
import 'screens/main_screen.dart';
import 'services/schema_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeStore.loadFromPrefs();
  // Iniciar carga/refresco del schema Oracle en background desde el arranque
  // para que el autocompletado esté listo cuando el usuario abra el editor.
  unawaited(SchemaService.instance.loadMetadata());
  runApp(const ProcDynamicApp());
}

class ProcDynamicApp extends StatelessWidget {
  const ProcDynamicApp({super.key});

  static ThemeData _buildDarkTheme() {
    const cs = ColorScheme.dark(
      primary: Color(0xFF0078D4),
      onPrimary: Colors.white,
      surface: Color(0xFF252526),
      surfaceContainer: Color(0xFF252526),
      surfaceContainerLow: Color(0xFF1E1E1E),
      surfaceContainerHigh: Color(0xFF2D2D2D),
      surfaceContainerHighest: Color(0xFF3C3C3C),
      onSurface: Color(0xFFD4D4D4),
      onSurfaceVariant: Color(0xFF969696),
      outline: Color(0xFF474747),
      outlineVariant: Color(0xFF3C3C3C),
    );
    return ThemeData.dark().copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surfaceContainerLow,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF323233),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFCCCCCC)),
      ),
      cardTheme: CardThemeData(color: cs.surface, elevation: 0),
      dividerColor: cs.outlineVariant,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Color(0xFF0078D4), width: 1.5),
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    const cs = ColorScheme.light(
      primary: Color(0xFF0078D4),
      onPrimary: Colors.white,
      surface: Colors.white,
      surfaceContainer: Color(0xFFECECEC),
      surfaceContainerLow: Color(0xFFF5F5F5),
      surfaceContainerHigh: Color(0xFFECECEC),
      surfaceContainerHighest: Colors.white,
      onSurface: Color(0xDD000000),
      onSurfaceVariant: Color(0x73000000),
      outline: Color(0xFFE0E0E0),
      outlineVariant: Color(0xFFEEEEEE),
    );
    return ThemeData.light().copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surfaceContainerLow,
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
      cardTheme: CardThemeData(color: cs.surface, elevation: 1),
      dividerColor: cs.outlineVariant,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: Color(0xFF0078D4), width: 1.5),
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => MaterialApp(
        title: 'Procedimientos Dinámicos',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: themeStore.themeMode,
        home: const MainScreen(),
      ),
    );
  }
}
