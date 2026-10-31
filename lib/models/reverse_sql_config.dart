/// Modelo de datos para configuraciones de extracción de base de datos en YAML (Reverse SQL).
/// Representa la estructura de:
/// ```yaml
/// dbconfig:
///   tables:
///     - dml: merge # merge | insert | update | delete
///       name: procedimientodinamico
///       columns: ...
///       sql: ...
///       pk_add: true
///       ignore_pk: ...
///       ins:
///         campo1: 1,2,3,4
///       filters:
///         cd_procedimiento: "= 'VALOR'"
/// ```
library;

enum ReverseSqlDml {
  merge,
  insert,
  update,
  delete;

  String get value => name;

  static ReverseSqlDml fromString(String? val) {
    switch (val?.trim().toLowerCase()) {
      case 'insert':
        return ReverseSqlDml.insert;
      case 'update':
        return ReverseSqlDml.update;
      case 'delete':
        return ReverseSqlDml.delete;
      case 'merge':
      default:
        return ReverseSqlDml.merge;
    }
  }
}

class ReverseSqlTableConfig {
  final ReverseSqlDml dml;
  final String name;
  final String? columns;
  final String? sql;
  final bool? pkAdd;
  final String? ignorePk;
  final Map<String, String> ins;
  final Map<String, String> notIns;
  final Map<String, String> betweens;
  final List<String> exists;
  final String? orderBy;
  final int? limit;
  final Map<String, String> filters;

  const ReverseSqlTableConfig({
    required this.dml,
    required this.name,
    this.columns,
    this.sql,
    this.pkAdd = true,
    this.ignorePk,
    this.ins = const {},
    this.notIns = const {},
    this.betweens = const {},
    this.exists = const [],
    this.orderBy,
    this.limit,
    this.filters = const {},
  });

  ReverseSqlTableConfig copyWith({
    ReverseSqlDml? dml,
    String? name,
    String? columns,
    String? sql,
    bool? pkAdd,
    String? ignorePk,
    Map<String, String>? ins,
    Map<String, String>? notIns,
    Map<String, String>? betweens,
    List<String>? exists,
    String? orderBy,
    int? limit,
    Map<String, String>? filters,
  }) {
    return ReverseSqlTableConfig(
      dml: dml ?? this.dml,
      name: name ?? this.name,
      columns: columns ?? this.columns,
      sql: sql ?? this.sql,
      pkAdd: pkAdd ?? this.pkAdd,
      ignorePk: ignorePk ?? this.ignorePk,
      ins: ins != null ? Map.from(ins) : this.ins,
      notIns: notIns != null ? Map.from(notIns) : this.notIns,
      betweens: betweens != null ? Map.from(betweens) : this.betweens,
      exists: exists != null ? List.from(exists) : this.exists,
      orderBy: orderBy ?? this.orderBy,
      limit: limit ?? this.limit,
      filters: filters != null ? Map.from(filters) : this.filters,
    );
  }
}

class ReverseSqlConfig {
  final List<ReverseSqlTableConfig> tables;

  const ReverseSqlConfig({this.tables = const []});

  ReverseSqlConfig copyWith({List<ReverseSqlTableConfig>? tables}) {
    return ReverseSqlConfig(tables: tables ?? this.tables);
  }

  /// Reordena una tabla de [oldIndex] a [newIndex] respetando el comportamiento estándar de ReorderableListView.
  ReverseSqlConfig reorderTable(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= tables.length) return this;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= tables.length || targetIndex == oldIndex) {
      return this;
    }
    final updated = List<ReverseSqlTableConfig>.from(tables);
    final movedItem = updated.removeAt(oldIndex);
    updated.insert(targetIndex, movedItem);
    return copyWith(tables: updated);
  }

  /// Mueve una tabla hacia arriba (decrementa su índice de ejecución).
  ReverseSqlConfig moveTableUp(int index) {
    if (index <= 0 || index >= tables.length) return this;
    final updated = List<ReverseSqlTableConfig>.from(tables);
    final temp = updated[index];
    updated[index] = updated[index - 1];
    updated[index - 1] = temp;
    return copyWith(tables: updated);
  }

  /// Mueve una tabla hacia abajo (incrementa su índice de ejecución).
  ReverseSqlConfig moveTableDown(int index) {
    if (index < 0 || index >= tables.length - 1) return this;
    final updated = List<ReverseSqlTableConfig>.from(tables);
    final temp = updated[index];
    updated[index] = updated[index + 1];
    updated[index + 1] = temp;
    return copyWith(tables: updated);
  }

  /// Genera el contenido YAML con la plantilla y comentarios estándar requeridos.
  String toYaml() {
    final sb = StringBuffer();
    sb.writeln(
      '#Debe llevar las reglas de la configuración Yaml. Para mas información https://www.redhat.com/es/topics/automation/what-is-yaml',
    );
    sb.writeln('dbconfig:');
    sb.writeln('  tables:');

    if (tables.isEmpty) {
      sb.writeln(
        '#    - dml: #merge | insert | update | delete, (required | string)',
      );
      sb.writeln('#      name: #TableName, (required | string)');
      sb.writeln(
        '#      columns: #Especificar columnas (Solo para update), (opcional | string)',
      );
      sb.writeln(
        '#      sql: #Query personalizado sin saltos de lineas, (opcional | string)',
      );
      sb.writeln('#      pk_add:  #Completa la PrimaryKey, (opcional | bool)');
      sb.writeln(
        '#      ignore_pk: #Ignora la PrimaryKey (opcional | string). Ej: cd_campo1, cd_campo2',
      );
      sb.writeln('#      ins: #Representación del IN');
      sb.writeln('#        campo1:');
      sb.writeln('#          - val1');
      sb.writeln('#          - val2');
      sb.writeln('#      not_ins: #Representación del NOT IN (opcional)');
      sb.writeln('#        campo1:');
      sb.writeln('#          - val3');
      sb.writeln('#      betweens: #Representación del BETWEEN (opcional)');
      sb.writeln("#        f_alta: \"'2026-01-01' AND '2026-12-31'\"");
      sb.writeln('#      exists: #Subconsultas EXISTS / NOT EXISTS (opcional)');
      sb.writeln(
        '#        - "SELECT 1 FROM otra_tabla WHERE campo = tabla.campo"',
      );
      sb.writeln(
        '#      order_by: "f_alta DESC" #Ordenamiento de extracción (opcional)',
      );
      sb.writeln('#      limit: 100 #Límite de registros a extraer (opcional)');
      sb.writeln('#      filters: #Representación del Where y And');
      sb.writeln(
        "#        cd_procedimiento: \"= 'SUGIERE_DIRECCION_MATRIZ_TRP'\"",
      );
      sb.writeln("#        campo2: like '%prueba%'");
      return sb.toString();
    }

    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      sb.writeln(
        '    - dml: ${t.dml.value} #merge | insert | update | delete, (required | string)',
      );
      sb.writeln('      name: ${t.name} #TableName, (required | string)');

      if (t.columns != null && t.columns!.trim().isNotEmpty) {
        sb.writeln(
          '      columns: ${t.columns!.trim()} #Especificar columnas (Solo para update), (opcional | string)',
        );
      }
      if (t.sql != null && t.sql!.trim().isNotEmpty) {
        sb.writeln(
          '      sql: ${t.sql!.trim()} #Query personalizado sin saltos de lineas, (opcional | string)',
        );
      }
      if (t.pkAdd != null) {
        sb.writeln(
          '      pk_add: ${t.pkAdd!} #Completa la PrimaryKey, (opcional | bool)',
        );
      }
      if (t.ignorePk != null && t.ignorePk!.trim().isNotEmpty) {
        sb.writeln(
          '      ignore_pk: ${t.ignorePk!.trim()} #Ignora la PrimaryKey (opcional | string)',
        );
      }

      if (t.ins.isNotEmpty) {
        final validIns = t.ins.entries.where(
          (e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty,
        );
        if (validIns.isNotEmpty) {
          sb.writeln('      ins: #Representación del IN (optional | string)');
          for (final entry in validIns) {
            final colKey = entry.key.trim();
            final items = _splitInItems(entry.value);
            if (items.length > 1) {
              sb.writeln('        $colKey:');
              for (final it in items) {
                sb.writeln('          - ${_formatYamlListItem(it)}');
              }
            } else if (items.length == 1) {
              final rawVal = items.first;
              sb.writeln('        $colKey:');
              sb.writeln('          - ${_formatYamlListItem(rawVal)}');
            } else {
              sb.writeln('        $colKey: ${entry.value.trim()}');
            }
          }
        }
      }

      if (t.notIns.isNotEmpty) {
        final validNotIns = t.notIns.entries.where(
          (e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty,
        );
        if (validNotIns.isNotEmpty) {
          sb.writeln('      not_ins: #Representación del NOT IN (opcional)');
          for (final entry in validNotIns) {
            final colKey = entry.key.trim();
            final items = _splitInItems(entry.value);
            if (items.length > 1) {
              sb.writeln('        $colKey:');
              for (final it in items) {
                sb.writeln('          - ${_formatYamlListItem(it)}');
              }
            } else if (items.length == 1) {
              final rawVal = items.first;
              sb.writeln('        $colKey:');
              sb.writeln('          - ${_formatYamlListItem(rawVal)}');
            } else {
              sb.writeln('        $colKey: ${entry.value.trim()}');
            }
          }
        }
      }

      if (t.betweens.isNotEmpty) {
        final validBetweens = t.betweens.entries.where(
          (e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty,
        );
        if (validBetweens.isNotEmpty) {
          sb.writeln('      betweens: #Representación del BETWEEN (opcional)');
          for (final entry in validBetweens) {
            final colKey = entry.key.trim();
            final val = entry.value.trim();
            if (val.startsWith('"') && val.endsWith('"')) {
              sb.writeln('        $colKey: $val');
            } else {
              sb.writeln('        $colKey: "$val"');
            }
          }
        }
      }

      if (t.exists.isNotEmpty) {
        final validExists = t.exists.where((e) => e.trim().isNotEmpty).toList();
        if (validExists.isNotEmpty) {
          sb.writeln(
            '      exists: #Subconsultas EXISTS / NOT EXISTS (opcional)',
          );
          for (final ex in validExists) {
            final trimmedEx = ex.trim();
            sb.writeln('        - "$trimmedEx"');
          }
        }
      }

      if (t.orderBy != null && t.orderBy!.trim().isNotEmpty) {
        final cleanOrder = t.orderBy!.trim();
        if (cleanOrder.startsWith('"') && cleanOrder.endsWith('"')) {
          sb.writeln('      order_by: $cleanOrder #Ordenamiento de extracción');
        } else {
          sb.writeln(
            '      order_by: "$cleanOrder" #Ordenamiento de extracción',
          );
        }
      }

      if (t.limit != null && t.limit! > 0) {
        sb.writeln('      limit: ${t.limit} #Límite de registros a extraer');
      }

      if (t.filters.isNotEmpty) {
        sb.writeln('      filters: #Representación del Where y And');
        t.filters.forEach((k, v) {
          final trimmedKey = k.trim();
          if (trimmedKey.isEmpty) return;
          final trimmedVal = v.trim();
          if (trimmedVal.startsWith('"') && trimmedVal.endsWith('"')) {
            sb.writeln('        $trimmedKey: $trimmedVal');
          } else {
            sb.writeln('        $trimmedKey: "$trimmedVal"');
          }
        });
      }

      if (i < tables.length - 1) {
        sb.writeln();
      }
    }

    return sb.toString();
  }

  /// Parsea un texto YAML extrayendo las tablas y sus propiedades.
  /// Es tolerante con comentarios, orden de atributos y variaciones de espacios.
  static ReverseSqlConfig parseYaml(String yamlText) {
    final lines = yamlText.split(RegExp(r'\r?\n'));
    final tables = <ReverseSqlTableConfig>[];

    ReverseSqlDml currentDml = ReverseSqlDml.merge;
    String currentName = '';
    String? currentColumns;
    String? currentSql;
    bool? currentPkAdd;
    String? currentIgnorePk;
    Map<String, String> currentIns = {};
    Map<String, String> currentNotIns = {};
    Map<String, String> currentBetweens = {};
    List<String> currentExists = [];
    String? currentOrderBy;
    int? currentLimit;
    Map<String, String> currentFilters = {};
    String?
    currentSection; // 'ins' | 'not_ins' | 'betweens' | 'exists' | 'filters'
    String?
    currentListKey; // Para listas YAML dentro de 'ins' o 'not_ins' (ej. 'campo:\n  - item1')
    final currentListItems = <String>[];

    void commitListKey() {
      if (currentListKey != null && currentListItems.isNotEmpty) {
        if (currentSection == 'not_ins') {
          currentNotIns[currentListKey!] = currentListItems.join(', ');
        } else {
          currentIns[currentListKey!] = currentListItems.join(', ');
        }
        currentListItems.clear();
      }
      currentListKey = null;
    }

    void commitCurrentTable() {
      commitListKey();
      if (currentName.isNotEmpty) {
        tables.add(
          ReverseSqlTableConfig(
            dml: currentDml,
            name: currentName,
            columns: currentColumns,
            sql: currentSql,
            pkAdd: currentPkAdd,
            ignorePk: currentIgnorePk,
            ins: currentIns,
            notIns: currentNotIns,
            betweens: currentBetweens,
            exists: currentExists,
            orderBy: currentOrderBy,
            limit: currentLimit,
            filters: currentFilters,
          ),
        );
      }
      currentDml = ReverseSqlDml.merge;
      currentName = '';
      currentColumns = null;
      currentSql = null;
      currentPkAdd = null;
      currentIgnorePk = null;
      currentIns = {};
      currentNotIns = {};
      currentBetweens = {};
      currentExists = [];
      currentOrderBy = null;
      currentLimit = null;
      currentFilters = {};
      currentSection = null;
    }

    for (final rawLine in lines) {
      final lineNoComment = _stripComment(rawLine);
      final trimmed = lineNoComment.trim();

      if (trimmed.isEmpty) continue;

      final leadingSpaces = _countLeadingSpaces(lineNoComment);

      // 1. Detección PRIORITARIA de inicio de tabla (- dml: ..., - name: ..., o - suelto).
      // En YAML estándar bajo `tables:`, los elementos de tabla inician con `- ` a nivel <= 4 espacios.
      if (trimmed.startsWith('- ') && leadingSpaces <= 4) {
        commitCurrentTable();
        final rest = trimmed.substring(2).trim();
        final cIdx = rest.indexOf(':');
        if (cIdx != -1) {
          final firstKey = rest.substring(0, cIdx).trim();
          final firstVal = rest.substring(cIdx + 1).trim();
          if (firstKey == 'dml') {
            currentDml = ReverseSqlDml.fromString(firstVal);
          } else if (firstKey == 'name') {
            currentName = _cleanQuotes(firstVal);
          }
        }
        currentSection = null;
        continue;
      }

      if (trimmed == '-' && leadingSpaces <= 4) {
        commitCurrentTable();
        currentSection = null;
        continue;
      }

      // 2. Control de salida de subsecciones por retroceso de indentación
      if ((currentSection == 'ins' || currentSection == 'not_ins') &&
          currentListKey != null) {
        if (leadingSpaces <= 8 && !trimmed.startsWith('- ')) {
          commitListKey();
        }
      }

      if (currentSection != null &&
          leadingSpaces <= 6 &&
          !trimmed.startsWith('- ')) {
        commitListKey();
        if (leadingSpaces <= 4) {
          currentSection = null;
        }
      }

      // 3. Ítems de lista dentro de subsecciones:
      // a) Lista bajo 'ins' o 'not_ins' (ej. "          - val")
      if ((currentSection == 'ins' || currentSection == 'not_ins') &&
          currentListKey != null &&
          leadingSpaces > 6 &&
          trimmed.startsWith('- ')) {
        final itemRaw = trimmed.substring(2).trim();
        final sqlItem = _formatSqlInElement(itemRaw);
        if (sqlItem.isNotEmpty) {
          currentListItems.add(sqlItem);
        }
        continue;
      }

      // b) Lista bajo 'exists' (ej. "        - \"SELECT 1 FROM ...\"")
      if (currentSection == 'exists' && trimmed.startsWith('- ')) {
        final exRaw = trimmed.substring(2).trim();
        final cleanEx = _cleanQuotes(exRaw);
        if (cleanEx.isNotEmpty) {
          currentExists.add(cleanEx);
        }
        continue;
      }

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx == -1) continue;

      final key = trimmed.substring(0, colonIdx).trim();
      final val = trimmed.substring(colonIdx + 1).trim();

      // Si la clave es un atributo directo conocido de la tabla (dml, name, filters, etc.)
      // y la indentación es <= 6, cerrar la subsección previa
      if (currentSection != null && leadingSpaces <= 6) {
        if (key == 'dml' ||
            key == 'name' ||
            key == 'filters' ||
            key == 'columns' ||
            key == 'sql' ||
            key == 'pk_add' ||
            key == 'ignore_pk' ||
            key == 'order_by' ||
            key == 'limit' ||
            key == 'ins' ||
            key == 'not_ins' ||
            key == 'betweens' ||
            key == 'exists') {
          commitListKey();
          currentSection = null;
        }
      }

      // Detectar subsecciones
      if (key == 'ins') {
        commitListKey();
        currentSection = 'ins';
        continue;
      }
      if (key == 'not_ins') {
        commitListKey();
        currentSection = 'not_ins';
        continue;
      }
      if (key == 'betweens') {
        commitListKey();
        currentSection = 'betweens';
        continue;
      }
      if (key == 'exists') {
        commitListKey();
        currentSection = 'exists';
        continue;
      }
      if (key == 'filters') {
        commitListKey();
        currentSection = 'filters';
        continue;
      }

      // Si estamos dentro de subsecciones
      if (currentSection == 'ins' || currentSection == 'not_ins') {
        if (leadingSpaces >= 6) {
          commitListKey();
          if (val.isEmpty) {
            currentListKey = key;
          } else {
            final normalized = _normalizeInlineIns(val);
            if (currentSection == 'not_ins') {
              currentNotIns[key] = normalized;
            } else {
              currentIns[key] = normalized;
            }
          }
          continue;
        } else {
          commitListKey();
          currentSection = null;
        }
      } else if (currentSection == 'betweens') {
        if (leadingSpaces >= 6) {
          currentBetweens[key] = _cleanQuotes(val);
          continue;
        } else {
          currentSection = null;
        }
      } else if (currentSection == 'filters') {
        if (leadingSpaces >= 6) {
          currentFilters[key] = _cleanQuotes(val);
          continue;
        } else {
          currentSection = null;
        }
      }

      // Propiedades de la tabla
      switch (key) {
        case 'dml':
          currentDml = ReverseSqlDml.fromString(val);
          break;
        case 'name':
          currentName = _cleanQuotes(val);
          break;
        case 'columns':
          currentColumns = _cleanQuotes(val);
          break;
        case 'sql':
          currentSql = _cleanQuotes(val);
          break;
        case 'pk_add':
          currentPkAdd = val.toLowerCase() == 'true';
          break;
        case 'ignore_pk':
          currentIgnorePk = _cleanQuotes(val);
          break;
        case 'order_by':
          currentOrderBy = _cleanQuotes(val);
          break;
        case 'limit':
          currentLimit = int.tryParse(val.trim());
          break;
      }
    }

    commitCurrentTable();

    return ReverseSqlConfig(tables: tables);
  }

  static String _stripComment(String line) {
    var inQuotes = false;
    var quoteChar = '';
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if ((ch == '"' || ch == "'")) {
        if (!inQuotes) {
          inQuotes = true;
          quoteChar = ch;
        } else if (quoteChar == ch) {
          inQuotes = false;
        }
      } else if (ch == '#' && !inQuotes) {
        return line.substring(0, i);
      }
    }
    return line;
  }

  static int _countLeadingSpaces(String line) {
    var count = 0;
    while (count < line.length && line[count] == ' ') {
      count++;
    }
    return count;
  }

  static String _cleanQuotes(String val) {
    var s = val.trim();
    // Si está entre comillas dobles exteriores YAML ("..."), desempacamos sólo las comillas dobles exteriores
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      return s.substring(1, s.length - 1).trim();
    }
    // Si está entre comillas simples exteriores ('...'), solo quitamos si NO es una lista de elementos
    // Ejemplo de lista: 'A','B' -> no debe quitar la primera comilla y la última porque son comillas de elementos
    if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      final inner = s.substring(1, s.length - 1);
      if (!inner.contains("'")) {
        return inner.trim();
      }
    }
    return s.trim();
  }

  /// Separa una cadena de elementos IN en lista de items individuales,
  /// respetando comillas y corchetes `[a, b]`.
  static List<String> _splitInItems(String raw) {
    var s = raw.trim();
    if (s.startsWith('[') && s.endsWith(']') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return const [];

    final result = <String>[];
    final current = StringBuffer();
    var inSingleQuotes = false;
    var inDoubleQuotes = false;

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
        current.write(ch);
      } else if (ch == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
        current.write(ch);
      } else if (ch == ',' && !inSingleQuotes && !inDoubleQuotes) {
        final part = current.toString().trim();
        if (part.isNotEmpty) result.add(part);
        current.clear();
      } else {
        current.write(ch);
      }
    }

    final lastPart = current.toString().trim();
    if (lastPart.isNotEmpty) result.add(lastPart);

    return result;
  }

  /// Formatea un valor para ser listado en YAML estándar (`- item`).
  /// Si el valor contiene comillas simples de SQL (ej. `'VALOR'`), se preserva
  /// de forma flexible: si el usuario lo introdujo con comillas simples, se mantienen
  /// para no perder el formato explícito; si vino sin comillas, se emite limpio.
  static String _formatYamlListItem(String raw) {
    var s = raw.trim();

    // Si está entre comillas dobles externas, las quitamos
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }

    // Si ya viene con comillas simples explícitas ('VALOR'), respetarlas directamente
    if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      return s;
    }

    // Si es numérico puro, escribir tal cual
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      return s;
    }

    // Si tiene caracteres especiales de sintaxis YAML o espacios, envolver entre comillas
    if (s.contains(':') ||
        s.contains('#') ||
        s.contains('[') ||
        s.contains(']') ||
        s.contains('{') ||
        s.contains('}') ||
        s.contains(',') ||
        s.startsWith('-') ||
        s.contains(' ')) {
      return '"${s.replaceAll('"', '\\"')}"';
    }

    return s;
  }

  /// Formatea un elemento leído de YAML para la cláusula SQL IN (`'VALOR'` o `123`).
  static String _formatSqlInElement(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // Si ya viene explícitamente entre comillas simples (ej: '0123' o 'AUT_...'),
    // es explícitamente un string literal de SQL: preservarlo.
    if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      return s;
    }

    // Si viene entre comillas dobles (formato YAML "string"), extraerlo y entrecomillarlo en SQL
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      final inner = s.substring(1, s.length - 1).trim();
      if (inner.isEmpty) return '';
      final cleanLiteral = inner.replaceAll("'", "''");
      return "'$cleanLiteral'";
    }

    // Si es un número (entero o decimal), no lleva comillas en SQL
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      return s;
    }

    // Es un string: asegurar que esté rodeado por comillas simples de SQL
    final cleanLiteral = s.replaceAll("'", "''");
    return "'$cleanLiteral'";
  }

  /// Normaliza valores inline como `val1, val2` o `'val1', 'val2'` a formato SQL IN.
  static String _normalizeInlineIns(String raw) {
    final items = _splitInItems(raw);
    if (items.isEmpty) return raw.trim();
    final formatted = items.map(_formatSqlInElement).where((e) => e.isNotEmpty);
    return formatted.join(', ');
  }
}
