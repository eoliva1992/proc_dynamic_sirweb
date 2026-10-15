import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/procedimiento.dart';
import '../widgets/app_tab.dart';
import 'editor_draft_service.dart';

/// Datos serializables de una pestaña para restaurar la sesión.
class SessionTabData {
  final String ambiente;
  final bool isDirty;
  final String? currentEditorCode;
  final String? localFilePath;
  final bool isSqlExecutor;

  // Datos de procedimiento dinámico si aplica
  final Map<String, dynamic>? procedimientoJson;

  // Datos de visor de código fuente si aplica
  final String? sourceViewerName;
  final String? sourceViewerType;
  final String? sourceViewerAmbiente;
  final int? sourceViewerInitialLine;
  final String? sourceViewerInitialSearchTerm;

  const SessionTabData({
    required this.ambiente,
    this.isDirty = false,
    this.currentEditorCode,
    this.localFilePath,
    this.isSqlExecutor = false,
    this.procedimientoJson,
    this.sourceViewerName,
    this.sourceViewerType,
    this.sourceViewerAmbiente,
    this.sourceViewerInitialLine,
    this.sourceViewerInitialSearchTerm,
  });

  Map<String, dynamic> toJson() => {
    'ambiente': ambiente,
    'isDirty': isDirty,
    if (currentEditorCode != null) 'currentEditorCode': currentEditorCode,
    if (localFilePath != null) 'localFilePath': localFilePath,
    'isSqlExecutor': isSqlExecutor,
    if (procedimientoJson != null) 'procedimiento': procedimientoJson,
    if (sourceViewerName != null) 'sourceViewerName': sourceViewerName,
    if (sourceViewerType != null) 'sourceViewerType': sourceViewerType,
    if (sourceViewerAmbiente != null)
      'sourceViewerAmbiente': sourceViewerAmbiente,
    if (sourceViewerInitialLine != null)
      'sourceViewerInitialLine': sourceViewerInitialLine,
    if (sourceViewerInitialSearchTerm != null)
      'sourceViewerInitialSearchTerm': sourceViewerInitialSearchTerm,
  };

  factory SessionTabData.fromJson(Map<String, dynamic> json) {
    return SessionTabData(
      ambiente: json['ambiente'] as String? ?? 'Desa',
      isDirty: json['isDirty'] as bool? ?? false,
      currentEditorCode: json['currentEditorCode'] as String?,
      localFilePath: json['localFilePath'] as String?,
      isSqlExecutor: json['isSqlExecutor'] as bool? ?? false,
      procedimientoJson: json['procedimiento'] is Map<String, dynamic>
          ? json['procedimiento'] as Map<String, dynamic>
          : null,
      sourceViewerName: json['sourceViewerName'] as String?,
      sourceViewerType: json['sourceViewerType'] as String?,
      sourceViewerAmbiente: json['sourceViewerAmbiente'] as String?,
      sourceViewerInitialLine: json['sourceViewerInitialLine'] as int?,
      sourceViewerInitialSearchTerm:
          json['sourceViewerInitialSearchTerm'] as String?,
    );
  }

  static SessionTabData fromAppTab(AppTab tab) {
    Map<String, dynamic>? procMap;
    if (tab.procedimiento != null) {
      final p = tab.procedimiento!;
      procMap = {
        'cdProcedimiento': p.cdProcedimiento,
        'deTexto': tab.currentEditorCode ?? p.deTexto,
        'inConfiguracion': p.inConfiguracion,
        'version': p.version,
        'stProcedimiento': p.stProcedimiento,
        if (p.feModificacion != null) 'feModificacion': p.feModificacion,
        if (p.cdUsuario != null) 'cdUsuario': p.cdUsuario,
      };
    }

    final sv = tab.sourceViewer;
    return SessionTabData(
      ambiente: tab.ambiente,
      isDirty: tab.isDirty,
      currentEditorCode: tab.currentEditorCode,
      localFilePath: tab.localFilePath,
      isSqlExecutor: tab.isSqlExecutor,
      procedimientoJson: procMap,
      sourceViewerName: sv?.name,
      sourceViewerType: sv?.objectType,
      sourceViewerAmbiente: sv?.ambiente,
      sourceViewerInitialLine: sv?.initialLine,
      sourceViewerInitialSearchTerm: sv?.initialSearchTerm,
    );
  }

  AppTab toAppTab() {
    final tab = AppTab(ambiente: ambiente);
    tab.isDirty = isDirty;
    tab.currentEditorCode = currentEditorCode;
    tab.localFilePath = localFilePath;
    tab.isSqlExecutor = isSqlExecutor;

    if (procedimientoJson != null) {
      tab.procedimiento = Procedimiento.fromJson(procedimientoJson!);
    } else if (localFilePath != null) {
      // Recrea el procedimiento sintético para documentos locales
      // si no venía en procedimientoJson
      tab.procedimiento = Procedimiento(
        cdProcedimiento: 'LOCAL_${DateTime.now().microsecondsSinceEpoch}',
        deTexto: currentEditorCode ?? '',
        inConfiguracion: 'S',
        version: 0,
        stProcedimiento: '1',
      );
    }

    if (sourceViewerName != null && sourceViewerType != null) {
      tab.sourceViewer = (
        name: sourceViewerName!,
        objectType: sourceViewerType!,
        ambiente: sourceViewerAmbiente ?? ambiente,
        initialLine: sourceViewerInitialLine,
        initialSearchTerm: sourceViewerInitialSearchTerm,
      );
    }

    return tab;
  }
}

/// Estado global de la sesión persistida.
class SavedSession {
  final List<SessionTabData> tabs;
  final int activeTab;

  const SavedSession({required this.tabs, required this.activeTab});

  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'activeTab': activeTab,
  };

  factory SavedSession.fromJson(Map<String, dynamic> json) {
    final tabsList = json['tabs'];
    final tabs = <SessionTabData>[];
    if (tabsList is List) {
      for (final item in tabsList) {
        if (item is Map<String, dynamic>) {
          tabs.add(SessionTabData.fromJson(item));
        }
      }
    }
    return SavedSession(
      tabs: tabs,
      activeTab: (json['activeTab'] as int? ?? 0).clamp(0, 999),
    );
  }
}

/// Servicio que guarda y restaura el conjunto de pestañas abiertas
/// (similar a Notepad++ o Notepad de Windows 11).
abstract final class SessionService {
  static const String _keySessionState = 'app_session_tabs_v1';
  static const String _keyRestoreEnabled = 'app_session_restore_enabled';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Visible for testing.
  @visibleForTesting
  static void setMockPrefs(SharedPreferences prefs) {
    _prefs = prefs;
  }

  /// Indica si la restauración de sesión está activada por defecto (`true`).
  static Future<bool> isRestoreEnabled() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyRestoreEnabled) ?? true;
  }

  /// Alterna o define si la restauración de sesión está activada.
  static Future<void> setRestoreEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyRestoreEnabled, enabled);
    if (!enabled) {
      await clearSession();
    }
  }

  /// Guarda la sesión actual de pestañas.
  static Future<void> saveSession({
    required List<AppTab> tabs,
    required int activeTab,
  }) async {
    final prefs = await _getPrefs();
    final enabled = prefs.getBool(_keyRestoreEnabled) ?? true;
    if (!enabled) return;

    // También aseguramos guardar los borradores activos en EditorDraftService
    for (final tab in tabs) {
      if (tab.procedimiento != null && tab.currentEditorCode != null) {
        final procId = tab.procedimiento!.cdProcedimiento;
        await EditorDraftService.save(
          procId,
          tab.ambiente,
          tab.currentEditorCode!,
        );
      }
    }

    final session = SavedSession(
      tabs: tabs.map(SessionTabData.fromAppTab).toList(),
      activeTab: activeTab,
    );
    final jsonStr = jsonEncode(session.toJson());
    await prefs.setString(_keySessionState, jsonStr);
  }

  /// Carga la sesión guardada si la restauración está habilitada.
  static Future<SavedSession?> loadSession() async {
    final prefs = await _getPrefs();
    final enabled = prefs.getBool(_keyRestoreEnabled) ?? true;
    if (!enabled) return null;

    final jsonStr = prefs.getString(_keySessionState);
    if (jsonStr == null || jsonStr.trim().isEmpty) return null;

    try {
      final map = jsonDecode(jsonStr);
      if (map is Map<String, dynamic>) {
        final session = SavedSession.fromJson(map);
        if (session.tabs.isNotEmpty) {
          return session;
        }
      }
    } catch (e) {
      debugPrint('[SessionService] Error leyendo sesión guardada: $e');
    }
    return null;
  }

  /// Limpia los datos de la sesión persistida.
  static Future<void> clearSession() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keySessionState);
  }
}
