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
  final Map<String, String> filters;

  const ReverseSqlTableConfig({
    required this.dml,
    required this.name,
    this.columns,
    this.sql,
    this.pkAdd = true,
    this.ignorePk,
    this.ins = const {},
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
      sb.writeln('#      ins: #Representación del IN (optional | string)');
      sb.writeln('#       campo1: 1,2,3,4');
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
        sb.writeln('      ins: #Representación del IN (optional | string)');
        t.ins.forEach((k, v) {
          sb.writeln('        $k: $v');
        });
      }

      if (t.filters.isNotEmpty) {
        sb.writeln('      filters: #Representación del Where y And');
        t.filters.forEach((k, v) {
          final trimmedVal = v.trim();
          if (trimmedVal.startsWith('"') && trimmedVal.endsWith('"')) {
            sb.writeln('        $k: $trimmedVal');
          } else {
            sb.writeln('        $k: "$trimmedVal"');
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
    Map<String, String> currentFilters = {};
    String? currentSection; // 'ins' | 'filters'

    void commitCurrentTable() {
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
      currentFilters = {};
      currentSection = null;
    }

    for (final rawLine in lines) {
      final lineNoComment = _stripComment(rawLine);
      final trimmed = lineNoComment.trim();

      if (trimmed.isEmpty) continue;

      // Detección de inicio de una tabla con '- ' (ej. '- dml:', '- name:')
      if (trimmed.startsWith('- ')) {
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

      // O un '-' suelto que abre elemento
      if (trimmed == '-') {
        commitCurrentTable();
        currentSection = null;
        continue;
      }

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx == -1) continue;

      final key = trimmed.substring(0, colonIdx).trim();
      final val = trimmed.substring(colonIdx + 1).trim();

      // Detectar subsecciones
      if (key == 'ins') {
        currentSection = 'ins';
        continue;
      }
      if (key == 'filters') {
        currentSection = 'filters';
        continue;
      }

      // Si estamos dentro de ins o filters
      if (currentSection == 'ins') {
        final leadingSpaces = _countLeadingSpaces(lineNoComment);
        if (leadingSpaces >= 6) {
          currentIns[key] = _cleanQuotes(val);
          continue;
        } else {
          currentSection = null;
        }
      } else if (currentSection == 'filters') {
        final leadingSpaces = _countLeadingSpaces(lineNoComment);
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
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      if (s.length >= 2) {
        s = s.substring(1, s.length - 1);
      }
    }
    return s.trim();
  }
}
