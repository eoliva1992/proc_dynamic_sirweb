import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'app_log.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'mcp_sse.dart';

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
  /// Columnas ya cacheadas en memoria de forma **síncrona**, o `null` si
  /// todavía no se consultaron. Útil para pintar sin parpadeo de spinner.
  List<({String name, String dataType})>? peekColumns(
    String tableName, {
    String? ambiente,
  }) => _caches[_env(ambiente)]?.cachedColumns[tableName.toUpperCase()];

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

  /// Caché en memoria de argumentos por `AMBIENTE|OBJETO`.
  final _argsCache =
      <String, List<({String name, String dataType, String inOut})>>{};
  final _argsInFlight =
      <String, Future<List<({String name, String dataType, String inOut})>>>{};

  static String _argsKey(String env, String name) =>
      '$env|${name.toUpperCase()}';

  /// Devuelve los argumentos ya cacheados de forma **síncrona**, o `null` si
  /// todavía no se consultaron. Útil para el autocompletado sin bloquear.
  List<({String name, String dataType, String inOut})>? peekObjectArguments(
    String objectName, {
    String? ambiente,
  }) => _argsCache[_argsKey(_env(ambiente), objectName)];

  /// Argumentos de un procedimiento o función Oracle (deduplica los duplicados del servidor).
  Future<List<({String name, String dataType, String inOut})>>
  getObjectArguments(
    String objectName, {
    String? ambiente,
    bool forceRefresh = false,
  }) {
    final key = _argsKey(_env(ambiente), objectName);
    if (forceRefresh) {
      _argsCache.remove(key);
    } else {
      final cached = _argsCache[key];
      if (cached != null) return Future.value(cached);
    }
    final inFlight = _argsInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetchObjectArguments(objectName, ambiente: ambiente)
        .then((args) {
          _argsCache[key] = args;
          return args;
        })
        .whenComplete(() {
          // OJO: no usar `() => _argsInFlight.remove(key)` (arrow function):
          // `Map.remove()` retorna el valor eliminado, que aquí es un Future.
          // `whenComplete` espera cualquier Future devuelto por su callback,
          // y como el valor removido es el propio `future` que se está
          // completando, eso provoca un deadlock por auto-referencia.
          _argsInFlight.remove(key);
        });
    _argsInFlight[key] = future;
    return future;
  }

  Future<List<({String name, String dataType, String inOut})>>
  _fetchObjectArguments(String objectName, {String? ambiente}) async {
    try {
      final result = await _call('get_object_arguments', {
        'objectName': objectName.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      final seen = <String>{};
      return rawList
          .cast<Map<String, dynamic>>()
          .where((r) {
            final name = (r['argumentName'] as String? ?? '').toUpperCase();
            final pos = (r['position'] as num?)?.toInt() ?? -1;
            return seen.add('$name:$pos');
          })
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
  ///
  /// Se cachean en memoria por `AMBIENTE|TIPO` para el autocompletado.
  Future<List<({String name, String dataType})>> getTypeAttributes(
    String typeName, {
    String? ambiente,
  }) {
    final key = _argsKey(_env(ambiente), typeName);
    final cached = _typeCache[key];
    if (cached != null) return Future.value(cached);
    final inFlight = _typeInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetchTypeAttributes(typeName, ambiente: ambiente)
        .then((attrs) {
          _typeCache[key] = attrs;
          return attrs;
        })
        .whenComplete(() {
          // Ver comentario en getObjectArguments: no usar arrow function aquí.
          _typeInFlight.remove(key);
        });
    _typeInFlight[key] = future;
    return future;
  }

  /// Devuelve los atributos ya cacheados de forma **síncrona**, o `null`.
  List<({String name, String dataType})>? peekTypeAttributes(
    String typeName, {
    String? ambiente,
  }) => _typeCache[_argsKey(_env(ambiente), typeName)];

  final _typeCache = <String, List<({String name, String dataType})>>{};
  final _typeInFlight =
      <String, Future<List<({String name, String dataType})>>>{};

  Future<List<({String name, String dataType})>> _fetchTypeAttributes(
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
  ///
  /// El resultado se cachea en memoria por `AMBIENTE|PAQUETE` y las llamadas
  /// concurrentes al mismo paquete comparten el mismo `Future`.
  Future<
    List<
      ({
        String name,
        String kind,
        List<({String name, String dataType, String inOut})> arguments,
      })
    >
  >
  getPackageSubprograms(
    String packageName, {
    String? ambiente,
    bool forceRefresh = false,
  }) {
    final key = _argsKey(_env(ambiente), packageName);
    if (forceRefresh) {
      _pkgCache.remove(key);
    } else {
      final cached = _pkgCache[key];
      if (cached != null) return Future.value(cached);
    }
    final inFlight = _pkgInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetchPackageSubprograms(packageName, ambiente: ambiente)
        .then((subs) {
          _pkgCache[key] = subs;
          return subs;
        })
        .whenComplete(() {
          // Ver comentario en getObjectArguments: no usar arrow function aquí.
          _pkgInFlight.remove(key);
        });
    _pkgInFlight[key] = future;
    return future;
  }

  /// Devuelve los subprogramas ya cacheados de forma **síncrona**, o `null`.
  List<
    ({
      String name,
      String kind,
      List<({String name, String dataType, String inOut})> arguments,
    })
  >?
  peekPackageSubprograms(String packageName, {String? ambiente}) =>
      _pkgCache[_argsKey(_env(ambiente), packageName)];

  final _pkgCache =
      <
        String,
        List<
          ({
            String name,
            String kind,
            List<({String name, String dataType, String inOut})> arguments,
          })
        >
      >{};
  final _pkgInFlight =
      <
        String,
        Future<
          List<
            ({
              String name,
              String kind,
              List<({String name, String dataType, String inOut})> arguments,
            })
          >
        >
      >{};

  Future<
    List<
      ({
        String name,
        String kind,
        List<({String name, String dataType, String inOut})> arguments,
      })
    >
  >
  _fetchPackageSubprograms(String packageName, {String? ambiente}) async {
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
    if (result['success'] == false) {
      // El detalle (ORA-, argumentos y DDL enviado) ya quedó en el log dentro
      // de `_callInner`; acá sólo se propaga el mensaje al llamador.
      throw Exception(
        result['error']?.toString() ??
            result['message']?.toString() ??
            'Error ejecutando el DDL',
      );
    }
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

  /// Ejecuta una sentencia DDL suelta (GRANT, CREATE SYNONYM, …) contra el
  /// ambiente indicado.
  ///
  /// Reutiliza el endpoint `compile_object_ddl`, que ejecuta el DDL tal cual
  /// contra Oracle. Lanza [Exception] con el `ORA-` si la sentencia falla.
  Future<void> executeDdl(
    String ddl, {
    required String objectName,
    required String objectType,
    String? ambiente,
  }) => compileObject(ddl, objectName, objectType, ambiente: ambiente);

  /// Valida la sintaxis de un objeto Oracle estático (PROCEDURE, PACKAGE, etc.) sin persistir.
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

  /// Compila el procedimiento dinámico en Oracle sin guardarlo (DROP inmediato).
  /// Usa PCK_PROCEDIMIENTO.COMPILAR_PROCEDIMIENTO en el servidor.
  Future<List<({int line, int position, String text, String attribute})>>
  compilarProcedimientoDinamico(
    String cdProcedimiento,
    String deTexto,
    String inConfiguracion, {
    String? ambiente,
  }) async {
    try {
      final result = await _call('compilar_procedimiento_dinamico', {
        'cdProcedimiento': cdProcedimiento,
        'deTexto': deTexto,
        'inConfiguracion': inConfiguracion,
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
    } catch (e) {
      debugPrint('[SchemaService] compilarProcedimientoDinamico error: $e');
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

  /// Firma de un subprograma PL/SQL para armar una llamada.
  ///
  /// Acepta el nombre en cualquiera de sus formas:
  /// `MI_PROC`, `SIR.MI_PROC`, `PCK_X.MIEMBRO` o `SIR.PCK_X.MIEMBRO`.
  ///
  /// Para los miembros de un package se usa `get_package_subprograms` (que
  /// `get_object_arguments` no resuelve) y se filtra por nombre; para los
  /// standalone se usa `get_object_arguments`. Se devuelven los argumentos en
  /// orden de posición, incluida la posición 0 (retorno de las funciones).
  Future<List<({String name, String dataType, String inOut, int position})>>
  getRoutineArguments(String objectName, {String? ambiente}) async {
    final parts = objectName
        .toUpperCase()
        .split('.')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const [];

    // 3 partes ⇒ ESQUEMA.PACKAGE.MIEMBRO (no hay ambigüedad).
    if (parts.length >= 3) {
      return _packageArguments(parts[1], parts[2], ambiente);
    }

    // 2 partes ⇒ puede ser PACKAGE.MIEMBRO o ESQUEMA.OBJETO: se prueban ambas.
    if (parts.length == 2) {
      final desdePackage = await _packageArguments(
        parts[0],
        parts[1],
        ambiente,
      );
      if (desdePackage.isNotEmpty) return desdePackage;
      return _standaloneArguments(parts[1], ambiente);
    }

    return _standaloneArguments(parts.first, ambiente);
  }

  Future<List<({String name, String dataType, String inOut, int position})>>
  _packageArguments(String packageName, String member, String? ambiente) async {
    try {
      final result = await _call('get_package_subprograms', {
        'packageName': packageName,
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final subprogramas = result['data'] as List? ?? [];
      for (final raw in subprogramas) {
        if (raw is! Map) continue;
        if ((raw['name']?.toString() ?? '').toUpperCase() != member) continue;
        return _mapArguments(raw['arguments']);
      }
    } catch (_) {
      // Package inexistente o sin permisos: se resuelve como standalone.
    }
    return const [];
  }

  Future<List<({String name, String dataType, String inOut, int position})>>
  _standaloneArguments(String objectName, String? ambiente) async {
    try {
      final result = await _call('get_object_arguments', {
        'objectName': objectName,
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      return _mapArguments(result['data']);
    } catch (_) {
      return const [];
    }
  }

  /// Normaliza la lista de argumentos que devuelven ambas tools MCP.
  List<({String name, String dataType, String inOut, int position})>
  _mapArguments(dynamic raw) {
    if (raw is! List) return const [];
    final out =
        <({String name, String dataType, String inOut, int position})>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final pos = e['position'] ?? e['posicion'];
      out.add((
        name: (e['argumentName'] ?? e['name'] ?? e['nombre'] ?? '')
            .toString()
            .toUpperCase(),
        dataType: (e['dataType'] ?? e['tipo'] ?? '').toString().toUpperCase(),
        inOut: (e['inOut'] ?? e['modo'] ?? 'IN').toString().toUpperCase(),
        position: pos is int ? pos : int.tryParse(pos?.toString() ?? '') ?? 0,
      ));
    }
    out.sort((a, b) => a.position.compareTo(b.position));
    return out;
  }

  Future<List<({String synonymName, bool isPublic, String owner})>> getSynonyms(
    String objectName, {
    String? ambiente,
  }) async {
    try {
      final result = await _call('get_object_synonyms', {
        'objectName': objectName.toUpperCase(),
        if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      });
      final rawList = result['data'] as List? ?? [];
      return rawList
          .cast<Map<String, dynamic>>()
          .map(
            (e) => (
              synonymName:
                  (e['synonymName'] as String? ??
                          e['synonym_name'] as String? ??
                          e['name'] as String? ??
                          '')
                      .toUpperCase(),
              isPublic: switch (e['synonymType'] ??
                  e['type'] ??
                  e['isPublic']) {
                'PUBLIC' || true || 1 => true,
                _ => false,
              },
              owner: (e['owner'] as String? ?? '').toUpperCase(),
            ),
          )
          .where((s) => s.synonymName.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// DDL de una tabla Oracle vía DBMS_METADATA (endpoint get_table_ddl).
  Future<
    ({
      String tableName,
      String owner,
      String createTable,
      String? comments,
      String? grants,
    })
  >
  getTableDdl(String tableName, {String? ambiente}) async {
    final result = await _call('get_table_ddl', {
      'tableName': tableName.toUpperCase(),
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    if (result['success'] == false) {
      throw Exception(
        result['message']?.toString() ??
            result['error']?.toString() ??
            'Error obteniendo DDL de tabla',
      );
    }
    final data = result['data'] as Map<String, dynamic>? ?? {};
    return (
      tableName: (data['tableName'] as String? ?? tableName).toUpperCase(),
      owner: (data['owner'] as String? ?? '').toUpperCase(),
      createTable: data['createTable'] as String? ?? '',
      comments: data['comments'] as String?,
      grants: data['grants'] as String?,
    );
  }

  /// Fuerza recarga desde el servidor en la próxima llamada (para todos los ambientes).
  void clearCache() {
    _caches.clear();
    _argsCache.clear();
    _pkgCache.clear();
    _typeCache.clear();
  }

  /// Fuerza recarga solo del ambiente dado desde el servidor.
  Future<SchemaMetadata> refreshAmbiente(String ambiente) {
    final env = _env(ambiente);
    _caches.remove(env);
    _argsCache.removeWhere((k, _) => k.startsWith('$env|'));
    _pkgCache.removeWhere((k, _) => k.startsWith('$env|'));
    _typeCache.removeWhere((k, _) => k.startsWith('$env|'));
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

  /// Timeout por defecto para cualquier llamada al servidor MCP.
  static const Duration kCallTimeout = Duration(seconds: 30);

  /// Ejecuta una herramienta MCP.
  ///
  /// El servidor responde con `Content-Type: text/event-stream` y **mantiene el
  /// stream abierto** tras enviar el resultado. Por eso NO se usa `client.post`
  /// (que espera el EOF del cuerpo y dejaría el `Future` colgado aunque los
  /// datos ya hayan llegado): se lee el stream línea a línea y se resuelve en
  /// cuanto aparece el primer evento `data:`, cancelando la suscripción.
  Future<Map<String, dynamic>> _call(
    String toolName,
    Map<String, dynamic> arguments, {
    Duration timeout = kCallTimeout,
  }) {
    return _callInner(toolName, arguments, timeout);
  }

  Future<Map<String, dynamic>> _callInner(
    String toolName,
    Map<String, dynamic> arguments,
    Duration timeout,
  ) async {
    final reloj = Stopwatch()..start();
    final request = http.Request('POST', Uri.parse(_mcpUrl))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      })
      ..body = jsonEncode({
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': {'name': toolName, 'arguments': arguments},
      });

    final http.StreamedResponse streamed;
    final String payload;
    try {
      streamed = await _client
          .send(request)
          .timeout(
            timeout,
            onTimeout: () =>
                throw TimeoutException('MCP $toolName: sin respuesta', timeout),
          );
      payload = await readFirstSseData(
        streamed,
        toolName: toolName,
        timeout: timeout,
      );
    } catch (e) {
      // Fallo de transporte (timeout, socket, TLS…): el servidor no respondió.
      AppLog.instance.server(
        toolName,
        message: AppLog.describe(e),
        argumentos: arguments,
        source: 'Servidor (MCP)',
      );
      rethrow;
    }

    final envelope = jsonDecode(payload) as Map<String, dynamic>;

    if (envelope.containsKey('error')) {
      final err = envelope['error'] as Map<String, dynamic>;
      final msg = err['message']?.toString() ?? 'Error MCP';
      AppLog.instance.server(
        toolName,
        message: msg,
        argumentos: arguments,
        respuesta: payload,
        source: 'Servidor (MCP)',
      );
      throw Exception(msg);
    }

    final contentList = envelope['result']['content'] as List<dynamic>;
    final text = contentList.first['text'] as String;
    final data = jsonDecode(text) as Map<String, dynamic>;

    // El backend puede responder 200 con `success:false`: se registra siempre,
    // aunque el llamador decida ignorarlo o convertirlo en excepción.
    if (data['success'] == false || data['ok'] == false) {
      AppLog.instance.server(
        toolName,
        message:
            data['error']?.toString() ??
            data['message']?.toString() ??
            'El servidor respondió success:false',
        argumentos: arguments,
        respuesta: text,
        source: 'Servidor (MCP)',
      );
    } else {
      // Transacción normal: queda el rastro de qué se pidió y cuánto tardó.
      AppLog.instance.transaction(
        toolName,
        source: 'MCP',
        duracion: reloj.elapsed,
        datos: {
          'Ambiente': arguments['ambiente']?.toString() ?? 'Desa',
          'Filas': _rowCount(data['data'])?.toString(),
        },
        detalle: arguments.isEmpty
            ? null
            : 'Argumentos: ${arguments.keys.join(', ')}',
      );
    }
    return data;
  }

  /// Cantidad de filas devueltas, cuando el envelope trae una lista.
  static int? _rowCount(Object? data) => data is List ? data.length : null;
}
