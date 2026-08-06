import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Claves en SharedPreferences ───────────────────────────────────────────────
const _kTables = 'schema_tables';
const _kViews = 'schema_views';
const _kObjects = 'schema_objects';
const _kLastUpdated = 'schema_last_updated';
const _kColPrefix = 'schema_columns_'; // + TABLE_NAME

/// Estado del proceso de carga del schema — para mostrar en la barra de estado.
enum SchemaLoadStatus {
  idle, // sin actividad
  loadingLocal, // leyendo SharedPreferences
  loadingServer, // consultando el servidor MCP
  refreshing, // refresco silencioso en background (ya hay datos)
  ready, // cargado y disponible
  error, // falló la carga
}

/// Metadata del schema Oracle para el autocompletado del editor.
class SchemaMetadata {
  final List<String> tables;
  final List<String> views;
  final List<({String name, String type})>
  objects; // PROCEDURE, FUNCTION, PACKAGE
  final Map<String, List<({String name, String dataType})>> cachedColumns;

  const SchemaMetadata({
    required this.tables,
    required this.views,
    required this.objects,
    this.cachedColumns = const {},
  });

  SchemaMetadata copyWithColumns(
    String table,
    List<({String name, String dataType})> cols,
  ) {
    final updated = Map<String, List<({String name, String dataType})>>.from(
      cachedColumns,
    );
    updated[table.toUpperCase()] = cols;
    return SchemaMetadata(
      tables: tables,
      views: views,
      objects: objects,
      cachedColumns: updated,
    );
  }
}

/// Servicio singleton que obtiene el schema Oracle para el autocompletado.
///
/// **Estrategia de caché:**
/// 1. Al iniciar: lee de [SharedPreferences] de forma instantánea (sin red).
/// 2. Si el caché tiene más de 24 h → refresca en background de forma silenciosa.
/// 3. Si no hay caché local → carga del servidor y persiste.
///
/// Las columnas se persisten por tabla (clave `schema_columns_TABLA`) y se
/// cargan bajo demanda cuando el usuario escribe `TABLA.`.
class SchemaService {
  SchemaService._();
  static final SchemaService instance = SchemaService._();

  static const String _mcpUrl = 'http://localhost:5179/mcp';

  SchemaMetadata? _cache;
  bool _loading = false;
  int _nextId = 1;

  /// Notifica el estado actual de carga — escúchalo para actualizar la UI.
  final status = ValueNotifier<SchemaLoadStatus>(SchemaLoadStatus.idle);

  // ── Carga inicial ──────────────────────────────────────────────────────────

  /// Devuelve el schema en caché sin disparar un refresco.
  /// Si la carga inicial aún está en curso, espera a que termine.
  /// Usar desde el editor para no repetir el refresh al abrir cada pestaña.
  Future<SchemaMetadata> getMetadata({String? ambiente}) async {
    if (_cache != null) return _cache!;
    if (_loading) {
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cache!;
    }
    // Sin caché y sin carga en curso → delegar a loadMetadata (primera vez)
    return loadMetadata(ambiente: ambiente);
  }

  /// Devuelve el schema local inmediatamente si existe, y **siempre** lanza
  /// un refresco en background al iniciar la app para mantener los datos frescos.
  Future<SchemaMetadata> loadMetadata({String? ambiente}) async {
    // 1. Ya está en memoria → devolver y refrescar en background
    if (_cache != null) {
      _launchBackgroundRefresh(ambiente: ambiente);
      return _cache!;
    }

    // 2. Evitar cargas paralelas
    if (_loading) {
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cache!;
    }
    _loading = true;

    try {
      status.value = SchemaLoadStatus.loadingLocal;
      final prefs = await SharedPreferences.getInstance();
      final local = _readFromPrefs(prefs);

      if (local != null) {
        // Tenemos datos locales → devolver de inmediato
        _cache = local;
        status.value = SchemaLoadStatus.ready;
        // Siempre refrescar en background al iniciar la app
        _refreshInBackground(prefs, ambiente: ambiente);
        return _cache!;
      }

      // No hay datos locales → primera vez, cargar del servidor
      status.value = SchemaLoadStatus.loadingServer;
      final fresh = await _fetchFromServer(ambiente: ambiente);
      _cache = fresh;
      _saveToPrefs(prefs, fresh);
      status.value = SchemaLoadStatus.ready;
      return _cache!;
    } catch (_) {
      status.value = SchemaLoadStatus.error;
      rethrow;
    } finally {
      _loading = false;
    }
  }

  /// Lanza un refresco en background si no hay uno en curso.
  void _launchBackgroundRefresh({String? ambiente}) {
    if (status.value == SchemaLoadStatus.refreshing ||
        status.value == SchemaLoadStatus.loadingServer) {
      return;
    }
    SharedPreferences.getInstance().then(
      (prefs) => _refreshInBackground(prefs, ambiente: ambiente),
    );
  }

  // ── Columnas bajo demanda ──────────────────────────────────────────────────

  /// Retorna columnas de [tableName].
  /// Orden de prioridad: memoria → SharedPreferences → servidor.
  Future<List<({String name, String dataType})>> getColumns(
    String tableName, {
    String? ambiente,
  }) async {
    final table = tableName.toUpperCase();

    // 1. Memoria
    if (_cache?.cachedColumns.containsKey(table) == true) {
      return _cache!.cachedColumns[table]!;
    }

    // 2. SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final local = _readColumnsFromPrefs(prefs, table);
    if (local != null) {
      if (_cache != null) {
        _cache = _cache!.copyWithColumns(table, local);
      }
      return local;
    }

    // 3. Servidor
    try {
      final result = await _call('get_table_columns', {
        'tableName': table,
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });

      final rawList = result['data'] as List? ?? [];
      final cols = rawList
          .cast<Map<String, dynamic>>()
          .map(
            (r) => (
              name: (r['columnName'] as String? ?? '').toUpperCase(),
              dataType: r['dataType'] as String? ?? '',
            ),
          )
          .where((c) => c.name.isNotEmpty)
          .toList();

      // Persistir en prefs y en memoria
      _saveColumnsToPrefs(prefs, table, cols);
      if (_cache != null) {
        _cache = _cache!.copyWithColumns(table, cols);
      }
      return cols;
    } catch (_) {
      return [];
    }
  }

  /// Argumentos de un procedimiento o función Oracle (deduplica los duplicados del servidor).
  Future<List<({String name, String dataType, String inOut})>>
  getObjectArguments(String objectName, {String? ambiente}) async {
    try {
      final result = await _call('get_object_arguments', {
        'objectName': objectName.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      final seen = <int>{};
      return rawList
          .cast<Map<String, dynamic>>()
          .where((r) => seen.add((r['position'] as num?)?.toInt() ?? -1))
          .map(
            (r) => (
              name: (r['argumentName'] as String? ?? '').toUpperCase(),
              dataType: r['dataType'] as String? ?? '',
              inOut: r['inOut'] as String? ?? '',
            ),
          )
          .where((a) => a.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fuerza recarga desde el servidor en la próxima llamada.
  void clearCache() {
    _cache = null;
  }

  // ── Internos: servidor ─────────────────────────────────────────────────────

  Future<SchemaMetadata> _fetchFromServer({String? ambiente}) async {
    final result = await _call('get_schema_overview', {
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });

    final data = result['data'] as Map<String, dynamic>? ?? {};
    return SchemaMetadata(
      tables: _toStringList(data['tables']),
      views: _toStringList(data['views']),
      objects: [
        ..._toStringList(
          data['procedures'],
        ).map((n) => (name: n, type: 'PROCEDURE')),
        ..._toStringList(
          data['functions'],
        ).map((n) => (name: n, type: 'FUNCTION')),
        ..._toStringList(
          data['packages'],
        ).map((n) => (name: n, type: 'PACKAGE')),
      ],
    );
  }

  /// Refresca el schema desde el servidor en background sin bloquear nada.
  void _refreshInBackground(SharedPreferences prefs, {String? ambiente}) {
    status.value = SchemaLoadStatus.refreshing;
    _fetchFromServer(ambiente: ambiente)
        .then((fresh) {
          final existingCols =
              Map<String, List<({String name, String dataType})>>.from(
                _cache?.cachedColumns ?? {},
              );
          _cache = SchemaMetadata(
            tables: fresh.tables,
            views: fresh.views,
            objects: fresh.objects,
            cachedColumns: existingCols,
          );
          _saveToPrefs(prefs, fresh);
          status.value = SchemaLoadStatus.ready;
        })
        .catchError((_) {
          status.value = SchemaLoadStatus
              .ready; // error silencioso — mantener datos locales
        });
  }

  // ── Internos: SharedPreferences ────────────────────────────────────────────

  SchemaMetadata? _readFromPrefs(SharedPreferences prefs) {
    final tablesJson = prefs.getString(_kTables);
    final viewsJson = prefs.getString(_kViews);
    final objectsJson = prefs.getString(_kObjects);
    if (tablesJson == null || objectsJson == null) return null;

    final tables = (jsonDecode(tablesJson) as List).cast<String>();
    final views = viewsJson != null
        ? (jsonDecode(viewsJson) as List).cast<String>()
        : <String>[];
    final objects = (jsonDecode(objectsJson) as List)
        .cast<Map<String, dynamic>>()
        .map((o) => (name: o['name'] as String, type: o['type'] as String))
        .toList();

    return SchemaMetadata(tables: tables, views: views, objects: objects);
  }

  void _saveToPrefs(SharedPreferences prefs, SchemaMetadata schema) {
    prefs.setString(_kTables, jsonEncode(schema.tables));
    prefs.setString(_kViews, jsonEncode(schema.views));
    prefs.setString(
      _kObjects,
      jsonEncode(
        schema.objects.map((o) => {'name': o.name, 'type': o.type}).toList(),
      ),
    );
    prefs.setString(_kLastUpdated, DateTime.now().toIso8601String());
  }

  List<({String name, String dataType})>? _readColumnsFromPrefs(
    SharedPreferences prefs,
    String table,
  ) {
    final json = prefs.getString('$_kColPrefix$table');
    if (json == null) return null;
    final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    return list
        .map((c) => (name: c['name'] as String, dataType: c['type'] as String))
        .toList();
  }

  void _saveColumnsToPrefs(
    SharedPreferences prefs,
    String table,
    List<({String name, String dataType})> cols,
  ) {
    prefs.setString(
      '$_kColPrefix$table',
      jsonEncode(
        cols.map((c) => {'name': c.name, 'type': c.dataType}).toList(),
      ),
    );
  }

  // ── Internos: HTTP MCP ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final response = await http.post(
      Uri.parse(_mcpUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': {'name': toolName, 'arguments': arguments},
      }),
    );

    final dataStr = _extractSseData(response.body);
    final envelope = jsonDecode(dataStr) as Map<String, dynamic>;

    if (envelope.containsKey('error')) {
      final err = envelope['error'] as Map<String, dynamic>;
      throw Exception(err['message']?.toString() ?? 'Error MCP');
    }

    final contentList = envelope['result']['content'] as List<dynamic>;
    final text = contentList.first['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  String _extractSseData(String raw) {
    for (final line in raw.split('\n')) {
      if (line.startsWith('data: ')) return line.substring(6);
    }
    return raw;
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().toUpperCase()).toList();
    }
    return [];
  }
}
