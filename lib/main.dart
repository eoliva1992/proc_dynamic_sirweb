import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/theme_provider.dart';
import 'screens/main_screen.dart';
import 'services/favorites_service.dart';
import 'services/schema_service.dart';
import 'widgets/_editor_themes.dart';
import 'widgets/object_source_page.dart';
import 'widgets/source_float_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure clean exit when flutter run is stopped (Ctrl+C / VS Code stop)
  // Without this, WebView2 leaves locks that block the next run.
  ProcessSignal.sigint.watch().listen((_) {
    closeAllSourceWindows();
    exit(0);
  });

  // ── Secondary window: source viewer ──────────────────────────────────────
  final sourceArg = args.where((a) => a.startsWith('--source=')).firstOrNull;
  if (sourceArg != null) {
    final params = sourceArg.substring('--source='.length).split('::');
    if (params.length >= 3) {
      await windowManager.ensureInitialized();
      final WindowOptions opts = WindowOptions(
        size: const Size(920, 680),
        center: true,
        title: '${params[0]} \u2014 ${params[1]}',
        minimumSize: const Size(480, 320),
        skipTaskbar: false,
      );
      windowManager.waitUntilReadyToShow(opts, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      await editorThemeStore.loadFromPrefs();
      runApp(
        SourceViewerApp(
          name: params[0],
          objectType: params[1],
          ambiente: params[2],
        ),
      );
      return;
    }
  }

  // ── Main window ───────────────────────────────────────────────────────────
  await windowManager.ensureInitialized();
  await themeStore.loadFromPrefs();
  await editorThemeStore.loadFromPrefs();
  await FavoritesService.load();
  unawaited(SchemaService.instance.loadMetadata());
  runApp(const ProcDynamicApp());
}

class ProcDynamicApp extends StatelessWidget {
  const ProcDynamicApp({super.key});

  // ── Dark-theme builder ──────────────────────────────────────────────────

  static ThemeData _dark({
    required Color primary,
    required Color scaffoldBg,
    required Color surface,
    required Color surfaceContainer,
    required Color surfaceContainerLow,
    required Color surfaceContainerHigh,
    required Color surfaceContainerHighest,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
    required Color outlineVariant,
    required Color appBarBg,
  }) {
    final cs = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
    );
    return ThemeData.dark().copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFCCCCCC)),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
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
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),
    );
  }

  // ── Light-theme builder ─────────────────────────────────────────────────

  static ThemeData _light({
    required Color primary,
    required Color scaffoldBg,
    required Color surface,
    required Color surfaceContainer,
    required Color surfaceContainerLow,
    required Color surfaceContainerHigh,
    required Color surfaceContainerHighest,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
    required Color outlineVariant,
    Color appBarBg = const Color(0xFF2C2C2C),
  }) {
    final cs = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
    );
    return ThemeData.light().copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
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
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),
    );
  }

  // ── Per-theme definitions ───────────────────────────────────────────────

  static ThemeData buildThemeFor(String id) => switch (id) {
    'monokai' => _dark(
      primary: const Color(0xFFA6E22E),
      scaffoldBg: const Color(0xFF272822),
      surface: const Color(0xFF2D2E27),
      surfaceContainer: const Color(0xFF32332C),
      surfaceContainerLow: const Color(0xFF272822),
      surfaceContainerHigh: const Color(0xFF3E3D32),
      surfaceContainerHighest: const Color(0xFF49483E),
      onSurface: const Color(0xFFF8F8F2),
      onSurfaceVariant: const Color(0xFF90908A),
      outline: const Color(0xFF4E4D40),
      outlineVariant: const Color(0xFF3E3D32),
      appBarBg: const Color(0xFF1F1F1A),
    ),
    'dracula' => _dark(
      primary: const Color(0xFFBD93F9),
      scaffoldBg: const Color(0xFF282A36),
      surface: const Color(0xFF2E3045),
      surfaceContainer: const Color(0xFF32354A),
      surfaceContainerLow: const Color(0xFF21222C),
      surfaceContainerHigh: const Color(0xFF44475A),
      surfaceContainerHighest: const Color(0xFF565A75),
      onSurface: const Color(0xFFF8F8F2),
      onSurfaceVariant: const Color(0xFF6272A4),
      outline: const Color(0xFF44475A),
      outlineVariant: const Color(0xFF2E3045),
      appBarBg: const Color(0xFF1E1F29),
    ),
    'solarized-dark' => _dark(
      primary: const Color(0xFF268BD2),
      scaffoldBg: const Color(0xFF002B36),
      surface: const Color(0xFF073642),
      surfaceContainer: const Color(0xFF0A3F4E),
      surfaceContainerLow: const Color(0xFF002B36),
      surfaceContainerHigh: const Color(0xFF0D4858),
      surfaceContainerHighest: const Color(0xFF104F62),
      onSurface: const Color(0xFF839496),
      onSurfaceVariant: const Color(0xFF657B83),
      outline: const Color(0xFF2F5867),
      outlineVariant: const Color(0xFF1C4050),
      appBarBg: const Color(0xFF001C23),
    ),
    'solarized-light' => _light(
      primary: const Color(0xFF268BD2),
      scaffoldBg: const Color(0xFFEEE8D5),
      surface: const Color(0xFFFDF6E3),
      surfaceContainer: const Color(0xFFEDE5CF),
      surfaceContainerLow: const Color(0xFFEEE8D5),
      surfaceContainerHigh: const Color(0xFFE5DCCA),
      surfaceContainerHighest: const Color(0xFFFDF6E3),
      onSurface: const Color(0xFF657B83),
      onSurfaceVariant: const Color(0xFF93A1A1),
      outline: const Color(0xFFC8BEAC),
      outlineVariant: const Color(0xFFD5CDB8),
    ),
    'one-dark' => _dark(
      primary: const Color(0xFF61AFEF),
      scaffoldBg: const Color(0xFF21252B),
      surface: const Color(0xFF282C34),
      surfaceContainer: const Color(0xFF2C313A),
      surfaceContainerLow: const Color(0xFF21252B),
      surfaceContainerHigh: const Color(0xFF313842),
      surfaceContainerHighest: const Color(0xFF3E4451),
      onSurface: const Color(0xFFABB2BF),
      onSurfaceVariant: const Color(0xFF5C6370),
      outline: const Color(0xFF3E4451),
      outlineVariant: const Color(0xFF2C313A),
      appBarBg: const Color(0xFF1A1D23),
    ),
    'github-dark' => _dark(
      primary: const Color(0xFF79C0FF),
      scaffoldBg: const Color(0xFF0D1117),
      surface: const Color(0xFF161B22),
      surfaceContainer: const Color(0xFF21262D),
      surfaceContainerLow: const Color(0xFF0D1117),
      surfaceContainerHigh: const Color(0xFF30363D),
      surfaceContainerHighest: const Color(0xFF3D444D),
      onSurface: const Color(0xFFE6EDF3),
      onSurfaceVariant: const Color(0xFF8B949E),
      outline: const Color(0xFF30363D),
      outlineVariant: const Color(0xFF21262D),
      appBarBg: const Color(0xFF161B22),
    ),
    'github-light' => _light(
      primary: const Color(0xFF0969DA),
      scaffoldBg: const Color(0xFFF6F8FA),
      surface: Colors.white,
      surfaceContainer: const Color(0xFFF6F8FA),
      surfaceContainerLow: const Color(0xFFF6F8FA),
      surfaceContainerHigh: const Color(0xFFEAEEF2),
      surfaceContainerHighest: Colors.white,
      onSurface: const Color(0xFF24292F),
      onSurfaceVariant: const Color(0xFF57606A),
      outline: const Color(0xFFD0D7DE),
      outlineVariant: const Color(0xFFEAEEF2),
    ),
    'nord' => _dark(
      primary: const Color(0xFF88C0D0),
      scaffoldBg: const Color(0xFF2E3440),
      surface: const Color(0xFF3B4252),
      surfaceContainer: const Color(0xFF434C5E),
      surfaceContainerLow: const Color(0xFF2E3440),
      surfaceContainerHigh: const Color(0xFF4C566A),
      surfaceContainerHighest: const Color(0xFF5A667D),
      onSurface: const Color(0xFFECEFF4),
      onSurfaceVariant: const Color(0xFFD8DEE9),
      outline: const Color(0xFF4C566A),
      outlineVariant: const Color(0xFF434C5E),
      appBarBg: const Color(0xFF2C3346),
    ),
    'tokyo-night' => _dark(
      primary: const Color(0xFF7AA2F7),
      scaffoldBg: const Color(0xFF1A1B26),
      surface: const Color(0xFF24283B),
      surfaceContainer: const Color(0xFF2A2B3C),
      surfaceContainerLow: const Color(0xFF1A1B26),
      surfaceContainerHigh: const Color(0xFF303345),
      surfaceContainerHighest: const Color(0xFF3D405E),
      onSurface: const Color(0xFFC0CAF5),
      onSurfaceVariant: const Color(0xFF565F89),
      outline: const Color(0xFF3B4261),
      outlineVariant: const Color(0xFF2A2B3C),
      appBarBg: const Color(0xFF16161E),
    ),
    'catppuccin-mocha' => _dark(
      primary: const Color(0xFFCBA6F7),
      scaffoldBg: const Color(0xFF1E1E2E),
      surface: const Color(0xFF24273A),
      surfaceContainer: const Color(0xFF2A2B3C),
      surfaceContainerLow: const Color(0xFF1E1E2E),
      surfaceContainerHigh: const Color(0xFF313244),
      surfaceContainerHighest: const Color(0xFF363650),
      onSurface: const Color(0xFFCDD6F4),
      onSurfaceVariant: const Color(0xFF6C7086),
      outline: const Color(0xFF45475A),
      outlineVariant: const Color(0xFF313244),
      appBarBg: const Color(0xFF181825),
    ),
    'hc-black' => _dark(
      primary: Colors.white,
      scaffoldBg: Colors.black,
      surface: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerLow: Colors.black,
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF222222),
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFC8C8C8),
      outline: const Color(0xFF6B6B6B),
      outlineVariant: const Color(0xFF3D3D3D),
      appBarBg: const Color(0xFF111111),
    ),
    'hc-light' => _light(
      primary: const Color(0xFF0000CC),
      scaffoldBg: Colors.white,
      surface: const Color(0xFFF5F5F5),
      surfaceContainer: const Color(0xFFEBEBEB),
      surfaceContainerLow: Colors.white,
      surfaceContainerHigh: const Color(0xFFE0E0E0),
      surfaceContainerHighest: const Color(0xFFF5F5F5),
      onSurface: Colors.black,
      onSurfaceVariant: const Color(0xFF3D3D3D),
      outline: const Color(0xFF767676),
      outlineVariant: const Color(0xFFABABAB),
      appBarBg: Colors.black,
    ),
    // oracle-light and vs share the same Flutter palette
    'oracle-light' || 'vs' => _light(
      primary: const Color(0xFF0078D4),
      scaffoldBg: const Color(0xFFF5F5F5),
      surface: Colors.white,
      surfaceContainer: const Color(0xFFECECEC),
      surfaceContainerLow: const Color(0xFFF5F5F5),
      surfaceContainerHigh: const Color(0xFFECECEC),
      surfaceContainerHighest: Colors.white,
      onSurface: const Color(0xDD000000),
      onSurfaceVariant: const Color(0x73000000),
      outline: const Color(0xFFE0E0E0),
      outlineVariant: const Color(0xFFEEEEEE),
    ),
    // oracle-dark, vs-dark, and anything else → default dark palette
    _ => _dark(
      primary: const Color(0xFF0078D4),
      scaffoldBg: const Color(0xFF1E1E1E),
      surface: const Color(0xFF252526),
      surfaceContainer: const Color(0xFF252526),
      surfaceContainerLow: const Color(0xFF1E1E1E),
      surfaceContainerHigh: const Color(0xFF2D2D2D),
      surfaceContainerHighest: const Color(0xFF3C3C3C),
      onSurface: const Color(0xFFD4D4D4),
      onSurfaceVariant: const Color(0xFF969696),
      outline: const Color(0xFF474747),
      outlineVariant: const Color(0xFF3C3C3C),
      appBarBg: const Color(0xFF323233),
    ),
  };

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: ListenableBuilder(
        listenable: editorThemeStore,
        builder: (_, _) => MaterialApp(
          title: 'Procedimientos Dinámicos',
          debugShowCheckedModeBanner: false,
          theme: ProcDynamicApp.buildThemeFor(editorThemeStore.themeId),
          home: const MainScreen(),
        ),
      ),
    );
  }
}

// ── Ventana secundaria: visor de código fuente ────────────────────────────────

class SourceViewerApp extends StatelessWidget {
  final String name;
  final String objectType;
  final String ambiente;

  const SourceViewerApp({
    super.key,
    required this.name,
    required this.objectType,
    required this.ambiente,
  });

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: ListenableBuilder(
        listenable: editorThemeStore,
        builder: (_, child) => MaterialApp(
          title: '$name — Código fuente',
          debugShowCheckedModeBanner: false,
          theme: ProcDynamicApp.buildThemeFor(editorThemeStore.themeId),
          home: ObjectSourcePage(
            name: name,
            objectType: objectType,
            ambiente: ambiente,
          ),
        ),
      ),
    );
  }
}
