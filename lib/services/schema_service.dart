import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Claves en SharedPreferences (se prefijan con el ambiente) ────────────────
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
  final List<({String name, String type, String owner})> objects;
  final Map<String, List<({String name, String dataType})>> cachedColumns;
  final String
  owner; // usuario conectado (fallback cuando no hay owner por objeto)
  final Map<String, String> tableOwners; // TABLE_NAME → OWNER
  final Map<String, String> viewOwners; // VIEW_NAME  → OWNER

  const SchemaMetadata({
    required this.tables,
    required this.views,
    required this.objects,
    this.cachedColumns = const {},
    this.owner = '',
    this.tableOwners = const {},
    this.viewOwners = const {},
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
      owner: owner,
      tableOwners: tableOwners,
      viewOwners: viewOwners,
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

  // Per-ambiente in-memory caches and loading flags
  final _caches = <String, SchemaMetadata>{};
  final _loadings = <String, bool>{};
  // Completers replace busy-wait loops for concurrent callers
  final _loadCompleters = <String, Completer<SchemaMetadata>>{};
  int _nextId = 1;
  final _client = http.Client();

  /// Normaliza el nombre del ambiente para usarlo como clave de caché.
  static String _env(String? a) => (a == null || a.isEmpty) ? 'Desa' : a;

  /// Notifica el estado actual de carga — escúchalo para actualizar la UI.
  final status = ValueNotifier<SchemaLoadStatus>(SchemaLoadStatus.idle);

  // ── Carga inicial ──────────────────────────────────────────────────────────

  /// Devuelve el schema en caché sin disparar un refresco.
  /// Si la carga inicial aún está en curso, espera a que termine.
  Future<SchemaMetadata> getMetadata({String? ambiente}) async {
    final env = _env(ambiente);
    if (_caches.containsKey(env)) return _caches[env]!;
    if (_loadCompleters.containsKey(env)) return _loadCompleters[env]!.future;
    return loadMetadata(ambiente: ambiente);
  }

  /// Devuelve el schema local inmediatamente si existe, y **siempre** lanza
  /// un refresco en background al iniciar la app para mantener los datos frescos.
  Future<SchemaMetadata> loadMetadata({String? ambiente}) async {
    final env = _env(ambiente);

    if (_caches.containsKey(env)) {
      _launchBackgroundRefresh(ambiente: ambiente);
      return _caches[env]!;
    }

    if (_loadCompleters.containsKey(env)) return _loadCompleters[env]!.future;
    _loadings[env] = true;
    final completer = Completer<SchemaMetadata>();
    _loadCompleters[env] = completer;

    try {
      status.value = SchemaLoadStatus.loadingLocal;
      final prefs = await SharedPreferences.getInstance();
      final local = _readFromPrefs(prefs, env);

      if (local != null) {
        _caches[env] = local;
        status.value = SchemaLoadStatus.ready;
        _refreshInBackground(prefs, ambiente: ambiente);
        completer.complete(_caches[env]!);
        return _caches[env]!;
      }

      status.value = SchemaLoadStatus.loadingServer;
      final fresh = await _fetchFromServer(ambiente: ambiente);
      _caches[env] = fresh;
      _saveToPrefs(prefs, fresh, env);
      status.value = SchemaLoadStatus.ready;
      completer.complete(_caches[env]!);
      return _caches[env]!;
    } catch (e) {
      status.value = SchemaLoadStatus.error;
      completer.completeError(e);
      rethrow;
    } finally {
      _loadings[env] = false;
      _loadCompleters.remove(env);
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
    String? owner,
    String? ambiente,
  }) async {
    final table = tableName.toUpperCase();
    final env = _env(ambiente);

    if (_caches[env]?.cachedColumns.containsKey(table) == true) {
      return _caches[env]!.cachedColumns[table]!;
    }

    final prefs = await SharedPreferences.getInstance();
    final local = _readColumnsFromPrefs(prefs, table, env);
    if (local != null) {
      if (_caches.containsKey(env)) {
        _caches[env] = _caches[env]!.copyWithColumns(table, local);
      }
      return local;
    }

    try {
      final result = await _call('get_table_columns', {
        'tableName': table,
        if (owner != null && owner.isNotEmpty) 'tableOwner': owner,
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

      _saveColumnsToPrefs(prefs, table, cols, env);
      if (_caches.containsKey(env)) {
        _caches[env] = _caches[env]!.copyWithColumns(table, cols);
      }
      return cols;
    } catch (e) {
      debugPrint('SchemaService.getColumns($tableName): $e');
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
    } catch (e) {
      debugPrint('SchemaService.getObjectArguments($objectName): $e');
      return [];
    }
  }

  /// Atributos de un TYPE Oracle objeto (vacío para colecciones TABLE/VARRAY).
  Future<List<({String name, String dataType})>> getTypeAttributes(
    String typeName, {
    String? ambiente,
  }) async {
    try {
      final result = await _call('get_type_attributes', {
        'typeName': typeName.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      return rawList
          .cast<Map<String, dynamic>>()
          .map(
            (r) => (
              name: (r['attributeName'] as String? ?? '').toUpperCase(),
              dataType: r['dataType'] as String? ?? '',
            ),
          )
          .where((a) => a.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('SchemaService.getTypeAttributes($typeName): $e');
      return [];
    }
  }

  /// Subprogramas de un paquete Oracle con sus argumentos en una sola llamada.
  Future<
    List<
      ({
        String name,
        String kind,
        List<({String name, String dataType, String inOut})> arguments,
      })
    >
  >
  getPackageSubprograms(String packageName, {String? ambiente}) async {
    try {
      final result = await _call('get_package_subprograms', {
        'packageName': packageName.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      return rawList.cast<Map<String, dynamic>>().map((p) {
        final args = (p['arguments'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(
              (a) => (
                name: (a['argumentName'] as String? ?? '').toUpperCase(),
                dataType: a['dataType'] as String? ?? '',
                inOut: a['inOut'] as String? ?? '',
              ),
            )
            .toList();
        return (
          name: (p['name'] as String? ?? '').toUpperCase(),
          kind: p['kind'] as String? ?? 'PROCEDURE',
          arguments: args,
        );
      }).toList();
    } catch (e) {
      debugPrint('SchemaService.getPackageSubprograms($packageName): $e');
      return [];
    }
  }

  /// Ejecuta el DDL en Oracle y retorna lista de errores de compilación (vacía = éxito).
  Future<List<({int line, int position, String text, String attribute})>>
  compileObject(
    String source,
    String objectName,
    String objectType, {
    String? ambiente,
  }) async {
    final result = await _call('compile_object_ddl', {
      'source': source,
      'objectName': objectName.toUpperCase(),
      'objectType': objectType.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final rawList = result['data'] as List? ?? [];
    return rawList
        .cast<Map<String, dynamic>>()
        .map(
          (e) => (
            line: (e['line'] as num).toInt(),
            position: (e['position'] as num).toInt(),
            text: e['text'] as String? ?? '',
            attribute: e['attribute'] as String? ?? 'ERROR',
          ),
        )
        .toList();
  }

  /// Validates PL/SQL syntax without persisting changes to Oracle.
  /// Backend tool 'validate_syntax_ddl': CREATE with temp name → read USER_ERRORS → DROP.
  Future<List<({int line, int position, String text, String attribute})>>
  validateSyntax(String source, String objectType, {String? ambiente}) async {
    try {
      final result = await _call('validate_syntax_ddl', {
        'source': source,
        'objectType': objectType.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      return rawList
          .cast<Map<String, dynamic>>()
          .map(
            (e) => (
              line: (e['line'] as num).toInt(),
              position: (e['position'] as num).toInt(),
              text: e['text'] as String? ?? '',
              attribute: e['attribute'] as String? ?? 'ERROR',
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Código fuente de un objeto Oracle. Para PACKAGE/TYPE también retorna el body.
  Future<({String spec, String? body})> getObjectSource(
    String objectName,
    String objectType, {
    String? ambiente,
  }) async {
    final result = await _call('get_object_source', {
      'objectName': objectName.toUpperCase(),
      'objectType': objectType.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    if (result['success'] == false) {
      throw Exception(
        result['message']?.toString() ??
            result['error']?.toString() ??
            'Error obteniendo fuente',
      );
    }
    final data = result['data'] as Map<String, dynamic>? ?? {};
    return (spec: data['spec'] as String? ?? '', body: data['body'] as String?);
  }

  Future<
    List<({String grantee, String privilege, bool grantable, String grantor})>
  >
  getObjectPrivileges(String objectName, {String? ambiente}) async {
    final result = await _call('get_object_privileges', {
      'objectName': objectName.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final rawList = result['data'] as List? ?? [];
    return rawList
        .cast<Map<String, dynamic>>()
        .map(
          (e) => (
            grantee: e['grantee'] as String? ?? '',
            privilege: e['privilege'] as String? ?? '',
            grantable: switch (e['grantable']) {
              true || 1 || 'YES' || 'Y' => true,
              _ => false,
            },
            grantor: e['grantor'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<({String name, String type, String owner})>> getObjectReferences(
    String objectName, {
    String? ambiente,
  }) async {
    final result = await _call('get_object_dependencies', {
      'objectName': objectName.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final rawList = result['data'] as List? ?? [];
    return rawList
        .cast<Map<String, dynamic>>()
        .map(
          (e) => (
            name: e['name'] as String? ?? '',
            type: e['type'] as String? ?? '',
            owner: e['owner'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<({String name, String value})>> getObjectInfo(
    String objectName,
    String objectType, {
    String? ambiente,
  }) async {
    final result = await _call('get_object_info', {
      'objectName': objectName.toUpperCase(),
      'objectType': objectType.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final rawList = (result['data'] is List)
        ? result['data'] as List
        : (result['data'] as Map<String, dynamic>?)?['properties'] as List? ??
              [];
    // Backend returns a list with one flat-map row — convert to name/value pairs
    if (rawList.isNotEmpty && rawList.first is Map) {
      final row = rawList.first as Map<String, dynamic>;
      return row.entries
          .map(
            (e) => (
              name: e.key.toUpperCase(),
              value: e.value?.toString() ?? '(null)',
            ),
          )
          .toList();
    }
    return rawList
        .cast<Map<String, dynamic>>()
        .map(
          (e) => (
            name: e['name'] as String? ?? '',
            value: e['value']?.toString() ?? '',
          ),
        )
        .toList();
  }

  /// Fuerza recarga desde el servidor en la próxima llamada (para todos los ambientes).
  void clearCache() => _caches.clear();

  /// Fuerza recarga solo del ambiente dado desde el servidor.
  Future<SchemaMetadata> refreshAmbiente(String ambiente) {
    _caches.remove(_env(ambiente));
    return loadMetadata(ambiente: ambiente);
  }

  /// Devuelve el schema en memoria para el ambiente dado, sin disparar carga ni refresco.
  SchemaMetadata? getCached({String? ambiente}) => _caches[_env(ambiente)];

  // ── Internos: servidor ─────────────────────────────────────────────────────

  Future<SchemaMetadata> _fetchFromServer({String? ambiente}) async {
    final result = await _call('get_schema_overview', {
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });

    final data = result['data'] as Map<String, dynamic>? ?? {};

    List<({String name, String owner})> parseItems(dynamic raw) {
      if (raw == null) return [];
      return (raw as List)
          .map((e) {
            if (e is String) return (name: e.toUpperCase(), owner: '');
            final m = e as Map<String, dynamic>;
            return (
              name: (m['name'] as String? ?? '').toUpperCase(),
              owner: (m['owner'] as String? ?? '').toUpperCase(),
            );
          })
          .where((x) => x.name.isNotEmpty)
          .toList();
    }

    List<({String name, String type, String owner})> parseObjects(
      dynamic raw,
      String type,
    ) {
      if (raw == null) return [];
      return (raw as List)
          .map((e) {
            if (e is String) {
              return (name: e.toUpperCase(), type: type, owner: '');
            }
            final m = e as Map<String, dynamic>;
            return (
              name: (m['name'] as String? ?? '').toUpperCase(),
              type: type,
              owner: (m['owner'] as String? ?? '').toUpperCase(),
            );
          })
          .where((x) => x.name.isNotEmpty)
          .toList();
    }

    final tableItems = parseItems(data['tables']);
    final viewItems = parseItems(data['views']);
    return SchemaMetadata(
      tables: tableItems.map((e) => e.name).toList(),
      views: viewItems.map((e) => e.name).toList(),
      objects: [
        ...parseObjects(data['procedures'], 'PROCEDURE'),
        ...parseObjects(data['functions'], 'FUNCTION'),
        ...parseObjects(data['packages'], 'PACKAGE'),
        ...parseObjects(data['types'], 'TYPE'),
      ],
      owner: data['owner'] as String? ?? '',
      tableOwners: {for (final e in tableItems) e.name: e.owner},
      viewOwners: {for (final e in viewItems) e.name: e.owner},
    );
  }

  /// Refresca el schema desde el servidor en background sin bloquear nada.
  void dispose() {
    _client.close();
    status.dispose();
  }

  void _refreshInBackground(SharedPreferences prefs, {String? ambiente}) {
    final env = _env(ambiente);
    status.value = SchemaLoadStatus.refreshing;
    _fetchFromServer(ambiente: ambiente)
        .then((fresh) {
          final existingCols =
              Map<String, List<({String name, String dataType})>>.from(
                _caches[env]?.cachedColumns ?? {},
              );
          _caches[env] = SchemaMetadata(
            tables: fresh.tables,
            views: fresh.views,
            objects: fresh.objects,
            cachedColumns: existingCols,
            owner: fresh.owner,
            tableOwners: fresh.tableOwners,
            viewOwners: fresh.viewOwners,
          );
          _saveToPrefs(prefs, fresh, env);
          status.value = SchemaLoadStatus.ready;
        })
        .catchError((_) {
          status.value = SchemaLoadStatus.ready;
        });
  }

  // ── Internos: SharedPreferences (claves prefijadas por ambiente) ─────────

  /// Lee schema del ambiente indicado. Para 'Desa' intenta clave sin prefijo como fallback.
  SchemaMetadata? _readFromPrefs(SharedPreferences prefs, String env) {
    String? t = prefs.getString('${env}_$_kTables');
    String? v = prefs.getString('${env}_$_kViews');
    String? o = prefs.getString('${env}_$_kObjects');
    // Migración: claves legacy sin prefijo para Desa
    if (t == null && env == 'Desa') {
      t = prefs.getString(_kTables);
      v = prefs.getString(_kViews);
      o = prefs.getString(_kObjects);
    }
    if (t == null || o == null) return null;
    final tables = (jsonDecode(t) as List).cast<String>();
    final views = v != null
        ? (jsonDecode(v) as List).cast<String>()
        : <String>[];
    final objects = (jsonDecode(o) as List)
        .cast<Map<String, dynamic>>()
        .map(
          (x) => (
            name: x['name'] as String,
            type: x['type'] as String,
            owner: (x['owner'] as String? ?? '').toUpperCase(),
          ),
        )
        .toList();
    return SchemaMetadata(tables: tables, views: views, objects: objects);
  }

  void _saveToPrefs(
    SharedPreferences prefs,
    SchemaMetadata schema,
    String env,
  ) {
    prefs.setString('${env}_$_kTables', jsonEncode(schema.tables));
    prefs.setString('${env}_$_kViews', jsonEncode(schema.views));
    prefs.setString(
      '${env}_$_kObjects',
      jsonEncode(
        schema.objects
            .map((o) => {'name': o.name, 'type': o.type, 'owner': o.owner})
            .toList(),
      ),
    );
    prefs.setString('${env}_$_kLastUpdated', DateTime.now().toIso8601String());
  }

  List<({String name, String dataType})>? _readColumnsFromPrefs(
    SharedPreferences prefs,
    String table,
    String env,
  ) {
    String? json = prefs.getString('${env}_$_kColPrefix$table');
    // Migración: clave legacy para Desa
    if (json == null && env == 'Desa') {
      json = prefs.getString('$_kColPrefix$table');
    }
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
    String env,
  ) {
    prefs.setString(
      '${env}_$_kColPrefix$table',
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
    final response = await _client.post(
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
}
