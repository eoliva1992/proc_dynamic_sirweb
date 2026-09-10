import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'app_navigator.dart';
import 'providers/theme_provider.dart';
import 'screens/main_screen.dart';
import 'services/app_log.dart';
import 'services/favorites_service.dart';
import 'services/schema_service.dart';
import 'widgets/_editor_themes.dart';
import 'widgets/code_editor_panel.dart';
import 'widgets/object_source_page.dart';

Future<void> main(List<String> args) async {
  // ── Sub-window: visor de código fuente (proceso OS independiente) ──────────
  // Lanzado desde source_float_window.dart via Process.start.
  // Al ser un proceso separado, exit(0) solo termina ESTA ventana, no la principal.
  // Args: ['multi_window', <placeholder>, argumentsJson]
  if (args.firstOrNull == 'multi_window') {
    // Para la sub-ventana se inicializa el binding aquí, fuera de runZonedGuarded,
    // lo cual es correcto porque runApp también se llama aquí (misma zona).
    WidgetsFlutterBinding.ensureInitialized();

    // Captura errores de Flutter en el proceso hijo y los imprime (visibles en
    // debug porque el proceso ya no es DETACHED_PROCESS).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint(
        '[sub-window] FlutterError: ${details.exception}\n${details.stack}',
      );
    };

    // ── Estrategia pre-resize (sin hide/show) ───────────────────────────────
    // Llamamos setSize ANTES de runApp, cuando la superficie de render aún no
    // existe. Flutter la crea directamente al tamaño correcto → sin flash
    // blanco ni reinicios de superficie.
    try {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1060, 700));
      await windowManager.center();
    } catch (e) {
      debugPrint('[sub-window] windowManager init error: $e');
    }

    final argumentsJson = args.length > 2 ? args[2] : '';
    final data = argumentsJson.isNotEmpty
        ? jsonDecode(argumentsJson) as Map<String, dynamic>
        : <String, dynamic>{};

    try {
      await editorThemeStore.loadFromPrefs();
    } catch (e) {
      debugPrint('[sub-window] loadFromPrefs error: $e');
    }

    runApp(
      SourceViewerApp(
        name: data['name'] as String? ?? '',
        objectType: data['objectType'] as String? ?? '',
        ambiente: data['ambiente'] as String? ?? '',
      ),
    );

    // Solo enfocamos después del primer frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.focus();
      } catch (_) {}
    });

    return;
  }

  // ── Ventana principal ────────────────────────────────────────────────────────
  // Se inicializa TODO dentro de runZonedGuarded para evitar el "Zone mismatch"
  // de Flutter 3.13+: ensureInitialized y runApp deben estar en la misma zona.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Graceful exit on Ctrl+C / flutter run stop
      ProcessSignal.sigint.watch().listen((_) => exit(0));

      await windowManager.ensureInitialized();
      await themeStore.loadFromPrefs();
      await editorThemeStore.loadFromPrefs();
      await FavoritesService.load();
      unawaited(SchemaService.instance.loadMetadata());

      // Catch any unhandled Flutter framework errors: show on-screen instead of closing
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exception}\n${details.stack}');
        AppLog.instance.exception(
          details.context?.toString() ?? 'Error de la interfaz',
          details.exception,
          stack: details.stack,
          source: 'Flutter',
          datos: {'Librería': details.library},
        );
      };

      // Diagnóstico solo-debug: `ext.sirweb.evalJs` permite evaluar JS dentro
      // del WebView2 de Monaco desde el VM service.
      CodeEditorPanel.registerDebugEvalExtension();

      runApp(const ProcDynamicApp());
    },
    (error, stack) {
      debugPrint('Unhandled error: $error\n$stack');
      AppLog.instance.exception('Error no controlado', error, stack: stack);
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

class ProcDynamicApp extends StatelessWidget {
  const ProcDynamicApp({super.key});

  // ── Theme builder ───────────────────────────────────────────────────────
  //
  // Una sola implementación para claro y oscuro: los colores vienen de la
  // AppPalette declarada junto al tema en `_editor_themes.dart`.

  static ThemeData _fromPalette(AppPalette p, {required bool isDark}) {
    final cs = isDark
        ? ColorScheme.dark(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.secondary,
            onSecondary: p.onPrimary,
            tertiary: p.tertiary,
            surface: p.surface,
            surfaceContainer: p.surfaceContainer,
            surfaceContainerLow: p.surfaceContainerLow,
            surfaceContainerHigh: p.surfaceContainerHigh,
            surfaceContainerHighest: p.surfaceContainerHighest,
            onSurface: p.onSurface,
            onSurfaceVariant: p.onSurfaceVariant,
            outline: p.outline,
            outlineVariant: p.outlineVariant,
          )
        : ColorScheme.light(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.secondary,
            onSecondary: p.onPrimary,
            tertiary: p.tertiary,
            surface: p.surface,
            surfaceContainer: p.surfaceContainer,
            surfaceContainerLow: p.surfaceContainerLow,
            surfaceContainerHigh: p.surfaceContainerHigh,
            surfaceContainerHighest: p.surfaceContainerHighest,
            onSurface: p.onSurface,
            onSurfaceVariant: p.onSurfaceVariant,
            outline: p.outline,
            outlineVariant: p.outlineVariant,
          );

    final base = isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: p.scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBarBg,
        foregroundColor: p.onAppBar,
        elevation: isDark ? 0 : 1,
        iconTheme: IconThemeData(color: p.onAppBar),
        actionsIconTheme: IconThemeData(color: p.onAppBar),
        titleTextStyle: TextStyle(
          color: p.onAppBar,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(color: cs.surface, elevation: isDark ? 0 : 1),
      dividerColor: cs.outlineVariant,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
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
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),
    );
  }

  // ── Per-theme definitions ───────────────────────────────────────────────
  //
  // La paleta de cada tema vive junto a su definición Monaco en
  // `widgets/_editor_themes.dart` (fuente única). Aquí solo se resuelve el id.

  static ThemeData buildThemeFor(String id) {
    final meta = kEditorThemeById[id] ?? kEditorThemes.first;
    return _fromPalette(meta.palette, isDark: meta.isDark);
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: ListenableBuilder(
        listenable: editorThemeStore,
        builder: (_, _) => MaterialApp(
          title: 'Procedimientos Dinámicos',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
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
