import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sql_execution.dart';
import '../models/table_metadata.dart';
import 'schema_service.dart';
import 'sql_executor_service.dart';

/// Servicio para consultar metadatos estructurales de tablas y vistas
/// (restricciones, disparadores/triggers e índices) usando `SqlExecutorService`
/// contra el diccionario de datos de Oracle (`ALL_*`).
///
/// Dispone de caché en memoria por `ambiente|owner|table` para evitar consultas
/// repetidas al cambiar de pestaña.
class TableMetadataService {
  static final TableMetadataService _instance = TableMetadataService._();
  factory TableMetadataService() => _instance;
  TableMetadataService._();

  final SqlExecutorService _sqlService = SqlExecutorService();

  // Cachés en memoria por clave "ambiente|owner|tabla"
  final Map<String, List<TableConstraintInfo>> _constraintsCache = {};
  final Map<String, List<TableTriggerInfo>> _triggersCache = {};
  final Map<String, List<TableIndexInfo>> _indexesCache = {};

  final Map<String, Future<List<TableConstraintInfo>>> _constraintsInFlight =
      {};
  final Map<String, Future<List<TableTriggerInfo>>> _triggersInFlight = {};
  final Map<String, Future<List<TableIndexInfo>>> _indexesInFlight = {};

  static String _cacheKey(String ambiente, String? owner, String table) {
    final env = ambiente.trim();
    final o = (owner ?? '').trim().toUpperCase();
    final t = table.trim().toUpperCase();
    return '$env|$o|$t';
  }

  /// Limpia las cachés para una tabla o todas si se omite.
  void invalidate({String? ambiente, String? owner, String? table}) {
    if (ambiente != null && table != null) {
      final key = _cacheKey(ambiente, owner, table);
      _constraintsCache.remove(key);
      _triggersCache.remove(key);
      _indexesCache.remove(key);
    } else {
      _constraintsCache.clear();
      _triggersCache.clear();
      _indexesCache.clear();
    }
  }

  String _resolveOwner(String? owner, String tableName, String ambiente) {
    if (owner != null && owner.trim().isNotEmpty) {
      return owner.trim().toUpperCase();
    }
    final cached = SchemaService.instance.getCached(ambiente: ambiente);
    if (cached != null) {
      final upper = tableName.trim().toUpperCase();
      final tableOwner = cached.tableOwners[upper];
      if (tableOwner != null && tableOwner.isNotEmpty) return tableOwner;
      final viewOwner = cached.viewOwners[upper];
      if (viewOwner != null && viewOwner.isNotEmpty) return viewOwner;
      final obj = cached.objects.where((o) => o.name == upper).firstOrNull;
      if (obj != null && obj.owner.isNotEmpty) return obj.owner;
      if (cached.owner.isNotEmpty) return cached.owner;
    }
    return '';
  }

  int _colIndex(List<SqlColumn> cols, String name) {
    final target = name.toUpperCase();
    return cols.indexWhere((c) => c.name.toUpperCase() == target);
  }

  dynamic _val(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. RESTRICCIONES (CONSTRAINTS)
  // ───────────────────────────────────────────────────────────────────────────
  Future<List<TableConstraintInfo>> getTableConstraints(
    String tableName, {
    required String ambiente,
    String? owner,
    bool forceRefresh = false,
  }) async {
    final effectiveOwner = _resolveOwner(owner, tableName, ambiente);
    final key = _cacheKey(ambiente, effectiveOwner, tableName);

    if (!forceRefresh && _constraintsCache.containsKey(key)) {
      return _constraintsCache[key]!;
    }
    if (_constraintsInFlight.containsKey(key)) {
      return _constraintsInFlight[key]!;
    }

    final future = _loadConstraints(tableName, effectiveOwner, ambiente);
    _constraintsInFlight[key] = future;
    try {
      final result = await future;
      _constraintsCache[key] = result;
      return result;
    } finally {
      _constraintsInFlight.remove(key);
    }
  }

  Future<List<TableConstraintInfo>> _loadConstraints(
    String tableName,
    String effectiveOwner,
    String ambiente,
  ) async {
    final upperTable = tableName.trim().toUpperCase();
    final ownerFilter = effectiveOwner.isNotEmpty
        ? "AND c.OWNER = '$effectiveOwner'"
        : '';
    final rOwnerFilter = effectiveOwner.isNotEmpty
        ? "AND r.OWNER = '$effectiveOwner'"
        : '';

    final sql =
        '''
SELECT 
    c.CONSTRAINT_NAME,
    c.CONSTRAINT_TYPE,
    c.STATUS,
    c.SEARCH_CONDITION,
    c.R_OWNER,
    c.R_CONSTRAINT_NAME,
    (SELECT r.TABLE_NAME FROM ALL_CONSTRAINTS r WHERE r.CONSTRAINT_NAME = c.R_CONSTRAINT_NAME $rOwnerFilter AND ROWNUM = 1) AS R_TABLE_NAME,
    cc.COLUMN_NAME,
    cc.POSITION
FROM ALL_CONSTRAINTS c
LEFT JOIN ALL_CONS_COLUMNS cc 
    ON c.OWNER = cc.OWNER 
   AND c.CONSTRAINT_NAME = cc.CONSTRAINT_NAME 
   AND c.TABLE_NAME = cc.TABLE_NAME
WHERE c.TABLE_NAME = '$upperTable'
  $ownerFilter
ORDER BY 
    CASE c.CONSTRAINT_TYPE 
        WHEN 'P' THEN 1 
        WHEN 'R' THEN 2 
        WHEN 'U' THEN 3 
        WHEN 'C' THEN 4 
        ELSE 5 
    END,
    c.CONSTRAINT_NAME,
    cc.POSITION NULLS LAST
''';

    try {
      final res = await _sqlService.executeSelect(
        sql,
        ambiente: ambiente,
        owner: effectiveOwner,
        maxRows: 500,
        timeoutSegundos: 20,
      );

      final idxCName = _colIndex(res.columns, 'CONSTRAINT_NAME');
      final idxCType = _colIndex(res.columns, 'CONSTRAINT_TYPE');
      final idxStatus = _colIndex(res.columns, 'STATUS');
      final idxSearch = _colIndex(res.columns, 'SEARCH_CONDITION');
      final idxROwner = _colIndex(res.columns, 'R_OWNER');
      final idxRCName = _colIndex(res.columns, 'R_CONSTRAINT_NAME');
      final idxRTName = _colIndex(res.columns, 'R_TABLE_NAME');
      final idxColName = _colIndex(res.columns, 'COLUMN_NAME');

      final Map<
        String,
        ({
          String name,
          ConstraintType type,
          String status,
          String? searchCondition,
          String? rOwner,
          String? rConstraintName,
          String? rTableName,
          List<String> cols,
        })
      >
      grouped = {};

      for (final row in res.rows) {
        final cName = _val(row, idxCName)?.toString() ?? '';
        if (cName.isEmpty) continue;

        final rawType = _val(row, idxCType)?.toString();
        final status = _val(row, idxStatus)?.toString() ?? 'ENABLED';
        final searchCond = _val(row, idxSearch)?.toString();
        final rOwner = _val(row, idxROwner)?.toString();
        final rCName = _val(row, idxRCName)?.toString();
        final rTName = _val(row, idxRTName)?.toString();
        final colName = _val(row, idxColName)?.toString();

        if (!grouped.containsKey(cName)) {
          grouped[cName] = (
            name: cName,
            type: ConstraintType.fromOracleCode(rawType),
            status: status,
            searchCondition: searchCond,
            rOwner: rOwner,
            rConstraintName: rCName,
            rTableName: rTName,
            cols: [],
          );
        }

        if (colName != null && colName.isNotEmpty) {
          if (!grouped[cName]!.cols.contains(colName)) {
            grouped[cName]!.cols.add(colName);
          }
        }
      }

      return grouped.values
          .map(
            (g) => TableConstraintInfo(
              name: g.name,
              type: g.type,
              status: g.status,
              columns: g.cols,
              searchCondition: g.searchCondition,
              rOwner: g.rOwner,
              rConstraintName: g.rConstraintName,
              rTableName: g.rTableName,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('TableMetadataService.getTableConstraints error: $e');
      rethrow;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. DISPARADORES / TRIGGERS
  // ───────────────────────────────────────────────────────────────────────────
  Future<List<TableTriggerInfo>> getTableTriggers(
    String tableName, {
    required String ambiente,
    String? owner,
    bool forceRefresh = false,
  }) async {
    final effectiveOwner = _resolveOwner(owner, tableName, ambiente);
    final key = _cacheKey(ambiente, effectiveOwner, tableName);

    if (!forceRefresh && _triggersCache.containsKey(key)) {
      return _triggersCache[key]!;
    }
    if (_triggersInFlight.containsKey(key)) {
      return _triggersInFlight[key]!;
    }

    final future = _loadTriggers(tableName, effectiveOwner, ambiente);
    _triggersInFlight[key] = future;
    try {
      final result = await future;
      _triggersCache[key] = result;
      return result;
    } finally {
      _triggersInFlight.remove(key);
    }
  }

  Future<List<TableTriggerInfo>> _loadTriggers(
    String tableName,
    String effectiveOwner,
    String ambiente,
  ) async {
    final upperTable = tableName.trim().toUpperCase();
    final ownerFilter = effectiveOwner.isNotEmpty
        ? "AND (TABLE_OWNER = '$effectiveOwner' OR OWNER = '$effectiveOwner')"
        : '';

    final sql =
        '''
SELECT 
    TRIGGER_NAME,
    TRIGGER_TYPE,
    TRIGGERING_EVENT,
    STATUS,
    OWNER
FROM ALL_TRIGGERS
WHERE TABLE_NAME = '$upperTable'
  $ownerFilter
ORDER BY TRIGGER_NAME
''';

    try {
      final res = await _sqlService.executeSelect(
        sql,
        ambiente: ambiente,
        owner: effectiveOwner,
        maxRows: 500,
        timeoutSegundos: 20,
      );

      final idxName = _colIndex(res.columns, 'TRIGGER_NAME');
      final idxType = _colIndex(res.columns, 'TRIGGER_TYPE');
      final idxEvent = _colIndex(res.columns, 'TRIGGERING_EVENT');
      final idxStatus = _colIndex(res.columns, 'STATUS');
      final idxOwner = _colIndex(res.columns, 'OWNER');

      return res.rows
          .map((row) {
            final tName = _val(row, idxName)?.toString() ?? '';
            final tType = _val(row, idxType)?.toString() ?? '';
            final tEvent = _val(row, idxEvent)?.toString() ?? '';
            final status = _val(row, idxStatus)?.toString() ?? 'ENABLED';
            final o = _val(row, idxOwner)?.toString() ?? effectiveOwner;

            return TableTriggerInfo(
              name: tName,
              triggerType: tType,
              triggeringEvent: tEvent,
              status: status,
              owner: o,
            );
          })
          .where((t) => t.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('TableMetadataService.getTableTriggers error: $e');
      rethrow;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. ÍNDICES (INDEXES)
  // ───────────────────────────────────────────────────────────────────────────
  Future<List<TableIndexInfo>> getTableIndexes(
    String tableName, {
    required String ambiente,
    String? owner,
    bool forceRefresh = false,
  }) async {
    final effectiveOwner = _resolveOwner(owner, tableName, ambiente);
    final key = _cacheKey(ambiente, effectiveOwner, tableName);

    if (!forceRefresh && _indexesCache.containsKey(key)) {
      return _indexesCache[key]!;
    }
    if (_indexesInFlight.containsKey(key)) {
      return _indexesInFlight[key]!;
    }

    final future = _loadIndexes(tableName, effectiveOwner, ambiente);
    _indexesInFlight[key] = future;
    try {
      final result = await future;
      _indexesCache[key] = result;
      return result;
    } finally {
      _indexesInFlight.remove(key);
    }
  }

  Future<List<TableIndexInfo>> _loadIndexes(
    String tableName,
    String effectiveOwner,
    String ambiente,
  ) async {
    final upperTable = tableName.trim().toUpperCase();
    final ownerFilter = effectiveOwner.isNotEmpty
        ? "AND i.TABLE_OWNER = '$effectiveOwner'"
        : '';

    final sql =
        '''
SELECT 
    i.INDEX_NAME,
    i.UNIQUENESS,
    i.INDEX_TYPE,
    i.STATUS,
    ic.COLUMN_NAME,
    ic.COLUMN_POSITION,
    ic.DESCEND
FROM ALL_INDEXES i
JOIN ALL_IND_COLUMNS ic 
    ON i.OWNER = ic.INDEX_OWNER 
   AND i.INDEX_NAME = ic.INDEX_NAME
WHERE i.TABLE_NAME = '$upperTable'
  $ownerFilter
ORDER BY 
    i.UNIQUENESS DESC,
    i.INDEX_NAME,
    ic.COLUMN_POSITION
''';

    try {
      final res = await _sqlService.executeSelect(
        sql,
        ambiente: ambiente,
        owner: effectiveOwner,
        maxRows: 500,
        timeoutSegundos: 20,
      );

      final idxName = _colIndex(res.columns, 'INDEX_NAME');
      final idxUniq = _colIndex(res.columns, 'UNIQUENESS');
      final idxType = _colIndex(res.columns, 'INDEX_TYPE');
      final idxStatus = _colIndex(res.columns, 'STATUS');
      final idxColName = _colIndex(res.columns, 'COLUMN_NAME');
      final idxColPos = _colIndex(res.columns, 'COLUMN_POSITION');
      final idxDescend = _colIndex(res.columns, 'DESCEND');

      final Map<
        String,
        ({
          String name,
          String uniqueness,
          String indexType,
          String status,
          List<TableIndexColumnInfo> cols,
        })
      >
      grouped = {};

      for (final row in res.rows) {
        final idxNameVal = _val(row, idxName)?.toString() ?? '';
        if (idxNameVal.isEmpty) continue;

        final uniqueness = _val(row, idxUniq)?.toString() ?? 'NONUNIQUE';
        final indexType = _val(row, idxType)?.toString() ?? 'NORMAL';
        final status = _val(row, idxStatus)?.toString() ?? 'VALID';
        final colName = _val(row, idxColName)?.toString() ?? '';
        final colPos =
            int.tryParse(_val(row, idxColPos)?.toString() ?? '1') ?? 1;
        final descend = _val(row, idxDescend)?.toString() ?? 'ASC';

        if (!grouped.containsKey(idxNameVal)) {
          grouped[idxNameVal] = (
            name: idxNameVal,
            uniqueness: uniqueness,
            indexType: indexType,
            status: status,
            cols: [],
          );
        }

        if (colName.isNotEmpty) {
          grouped[idxNameVal]!.cols.add(
            TableIndexColumnInfo(
              columnName: colName,
              columnPosition: colPos,
              descend: descend,
            ),
          );
        }
      }

      return grouped.values
          .map(
            (g) => TableIndexInfo(
              name: g.name,
              uniqueness: g.uniqueness,
              indexType: g.indexType,
              status: g.status,
              columns: g.cols,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('TableMetadataService.getTableIndexes error: $e');
      rethrow;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. ACCIONES DDL (HABILITAR / DESHABILITAR)
  // ───────────────────────────────────────────────────────────────────────────

  /// Sanitiza un identificador Oracle para evitar inyecciones.
  String _sanitizeIdentifier(String id) {
    return id.replaceAll('"', '').trim().toUpperCase();
  }

  /// Habilita o deshabilita una restricción de una tabla mediante DDL:
  /// `ALTER TABLE <owner>.<table_name> ENABLE/DISABLE CONSTRAINT <constraint_name>`
  Future<SqlDdlResult> setConstraintStatus({
    required String tableName,
    required String constraintName,
    required bool enable,
    required String ambiente,
    String? owner,
  }) async {
    final effectiveOwner = _resolveOwner(owner, tableName, ambiente);
    final cleanTable = _sanitizeIdentifier(tableName);
    final cleanConstraint = _sanitizeIdentifier(constraintName);
    final action = enable ? 'ENABLE' : 'DISABLE';

    final target = effectiveOwner.isNotEmpty
        ? '"$effectiveOwner"."$cleanTable"'
        : '"$cleanTable"';

    final sql = 'ALTER TABLE $target $action CONSTRAINT "$cleanConstraint"';

    try {
      final res = await _sqlService.executeDdl(
        sql,
        ambiente: ambiente,
        owner: effectiveOwner,
        objectName: cleanTable,
        objectType: 'TABLE',
        timeoutSegundos: 30,
      );

      // Invalida la caché de constraints de esta tabla
      final key = _cacheKey(ambiente, effectiveOwner, tableName);
      _constraintsCache.remove(key);

      return res;
    } catch (e) {
      debugPrint('TableMetadataService.setConstraintStatus error: $e');
      rethrow;
    }
  }

  /// Habilita o deshabilita un trigger en Oracle mediante DDL:
  /// `ALTER TRIGGER <owner>.<trigger_name> ENABLE/DISABLE`
  Future<SqlDdlResult> setTriggerStatus({
    required String triggerName,
    required bool enable,
    required String ambiente,
    String? owner,
    String? tableName,
  }) async {
    final cleanTrigger = _sanitizeIdentifier(triggerName);
    final effectiveOwner = (owner ?? '').trim().toUpperCase().isNotEmpty
        ? owner!.trim().toUpperCase()
        : _resolveOwner(null, triggerName, ambiente);
    final action = enable ? 'ENABLE' : 'DISABLE';

    final target = effectiveOwner.isNotEmpty
        ? '"$effectiveOwner"."$cleanTrigger"'
        : '"$cleanTrigger"';

    final sql = 'ALTER TRIGGER $target $action';

    try {
      final res = await _sqlService.executeDdl(
        sql,
        ambiente: ambiente,
        owner: effectiveOwner,
        objectName: cleanTrigger,
        objectType: 'TRIGGER',
        timeoutSegundos: 30,
      );

      // Invalida la caché de triggers para la tabla si se proporcionó
      if (tableName != null && tableName.isNotEmpty) {
        final key = _cacheKey(ambiente, effectiveOwner, tableName);
        _triggersCache.remove(key);
      } else {
        _triggersCache.clear();
      }

      return res;
    } catch (e) {
      debugPrint('TableMetadataService.setTriggerStatus error: $e');
      rethrow;
    }
  }
}
