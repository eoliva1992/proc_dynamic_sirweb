/// Información de contexto para autocompletado en un archivo YAML de Reverse SQL.
class YamlCursorContext {
  /// Nombre de la tabla identificada en el bloque actual (en mayúsculas), o null si no se detectó.
  final String? tableName;

  /// Tipo de campo o bloque donde se encuentra el cursor.
  final YamlColumnFieldType fieldType;

  /// Clave o prefijo que el usuario está escribiendo actualmente.
  final String currentWord;

  const YamlCursorContext({
    this.tableName,
    required this.fieldType,
    this.currentWord = '',
  });

  /// Indica si en este contexto tiene sentido recomendar nombres de columnas.
  bool get expectsColumn =>
      tableName != null &&
      tableName!.isNotEmpty &&
      fieldType != YamlColumnFieldType.none;
}

enum YamlColumnFieldType {
  /// Lista separada por comas en 'columns: col1, col2'
  columnsList,

  /// Lista en 'ignore_pk: col1, col2'
  ignorePkList,

  /// Clave de columna bajo 'filters:'
  filterKey,

  /// Clave de columna bajo 'ins:'
  insKey,

  /// Clave de columna bajo 'not_ins:'
  notInsKey,

  /// Clave de columna bajo 'betweens:'
  betweensKey,

  /// Clave de columna bajo 'set_columns:'
  setColumnsKey,

  /// 'order_by: col1 ASC, col2 DESC'
  orderBy,

  /// No es un campo de columnas
  none,
}

/// Analizador liviano de contexto para Reverse SQL en Monaco YAML editor.
class ReverseSqlYamlContextExtractor {
  static final RegExp _tableBlockRegex = RegExp(r'^\s*-\s+dml:');
  static final RegExp _tableNameRegex = RegExp(
    r'^\s*name:\s*([A-Za-z0-9_]+)',
    caseSensitive: false,
  );
  static final RegExp _topSectionRegex = RegExp(r'^\s*([a-zA-Z_]\w*):');

  /// Determina la tabla y el contexto de columnas dada la línea actual (1-based) y el texto completo YAML.
  static YamlCursorContext extractContext({
    required String fullText,
    required int lineNumber, // 1-based
    required int column, // 1-based
  }) {
    final lines = fullText.split('\n');
    if (lines.isEmpty) {
      return const YamlCursorContext(fieldType: YamlColumnFieldType.none);
    }

    final lineIdx = (lineNumber - 1).clamp(0, lines.length - 1);
    final currentLine = lines[lineIdx];
    final textBeforeCursor = column > 1 && column <= currentLine.length + 1
        ? currentLine.substring(0, column - 1)
        : currentLine;

    // 1. Encontrar la tabla actual rastreando hacia arriba y hacia abajo dentro del bloque de tabla
    final tableName = _findCurrentTable(lines, lineIdx);

    // 2. Determinar el tipo de campo en la línea actual
    final fieldType = _determineFieldType(lines, lineIdx, textBeforeCursor);

    // 3. Extraer la palabra actual antes del cursor
    final currentWord = _extractCurrentWord(textBeforeCursor);

    return YamlCursorContext(
      tableName: tableName,
      fieldType: fieldType,
      currentWord: currentWord,
    );
  }

  static String? _findCurrentTable(List<String> lines, int targetLineIdx) {
    // Buscar el inicio del bloque de tabla más cercano hacia arriba
    int blockStartIdx = -1;
    for (int i = targetLineIdx; i >= 0; i--) {
      if (_tableBlockRegex.hasMatch(lines[i])) {
        blockStartIdx = i;
        break;
      }
    }

    if (blockStartIdx == -1) {
      // Si el cursor está encima del primer '- dml:', buscar si la primera tabla tiene name
      for (int i = 0; i < lines.length && i <= targetLineIdx + 5; i++) {
        final match = _tableNameRegex.firstMatch(lines[i]);
        if (match != null) {
          return match.group(1)?.trim().toUpperCase();
        }
      }
      return null;
    }

    // Desde blockStartIdx hacia abajo (hasta el siguiente '- dml:' o límite razonable)
    for (int i = blockStartIdx; i < lines.length; i++) {
      if (i > blockStartIdx && _tableBlockRegex.hasMatch(lines[i])) {
        // Entró en otra tabla
        break;
      }
      final match = _tableNameRegex.firstMatch(lines[i]);
      if (match != null) {
        return match.group(1)?.trim().toUpperCase();
      }
    }

    return null;
  }

  static YamlColumnFieldType _determineFieldType(
    List<String> lines,
    int currentLineIdx,
    String textBeforeCursor,
  ) {
    final trimmedLine = textBeforeCursor.trimLeft();

    // Valores en línea: 'columns:', 'ignore_pk:', 'order_by:'
    if (trimmedLine.startsWith('columns:') ||
        RegExp(r'^\s*columns:\s*').hasMatch(textBeforeCursor)) {
      return YamlColumnFieldType.columnsList;
    }
    if (trimmedLine.startsWith('ignore_pk:') ||
        RegExp(r'^\s*ignore_pk:\s*').hasMatch(textBeforeCursor)) {
      return YamlColumnFieldType.ignorePkList;
    }
    if (trimmedLine.startsWith('order_by:') ||
        RegExp(r'^\s*order_by:\s*').hasMatch(textBeforeCursor)) {
      return YamlColumnFieldType.orderBy;
    }

    // Si la línea actual es clave o está indentada bajo una sección
    // Rastrear hacia arriba la sección contenedora inmediata basándose en la indentación
    final currentIndent = _getIndent(lines[currentLineIdx]);
    String? currentSection;
    for (int i = currentLineIdx; i >= 0; i--) {
      final line = lines[i];
      if (_tableBlockRegex.hasMatch(line)) {
        break;
      }

      final trimmed = line.trim();
      final lineIndent = _getIndent(line);
      // Solo consideramos secciones contenedoras de nivel superior a la línea actual si estamos en una línea indentada,
      // o la línea misma si estamos en ella
      if (i < currentLineIdx &&
          lineIndent >= currentIndent &&
          trimmed.isNotEmpty) {
        continue;
      }

      if (trimmed == 'filters:' || trimmed.startsWith('filters:')) {
        currentSection = 'filters';
        break;
      } else if (trimmed == 'ins:' || trimmed.startsWith('ins:')) {
        currentSection = 'ins';
        break;
      } else if (trimmed == 'not_ins:' || trimmed.startsWith('not_ins:')) {
        currentSection = 'not_ins';
        break;
      } else if (trimmed == 'betweens:' || trimmed.startsWith('betweens:')) {
        currentSection = 'betweens';
        break;
      } else if (trimmed == 'set_columns:' ||
          trimmed.startsWith('set_columns:')) {
        currentSection = 'set_columns';
        break;
      } else if (i < currentLineIdx &&
          _topSectionRegex.hasMatch(trimmed) &&
          !trimmed.startsWith('-')) {
        // Otra sección como sql:, limit:, pk_add:, columns:, etc.
        break;
      }
    }

    if (currentSection != null) {
      // Verificar si en la línea actual estamos escribiendo el nombre de la columna (clave antes de ':')
      // o un valor tras ':'
      final hasColon = textBeforeCursor.contains(':');
      final isNewKey = !hasColon || textBeforeCursor.trim().endsWith(':');

      switch (currentSection) {
        case 'filters':
          return YamlColumnFieldType.filterKey;
        case 'ins':
          return YamlColumnFieldType.insKey;
        case 'not_ins':
          return YamlColumnFieldType.notInsKey;
        case 'betweens':
          return YamlColumnFieldType.betweensKey;
        case 'set_columns':
          return isNewKey
              ? YamlColumnFieldType.setColumnsKey
              : YamlColumnFieldType.none;
      }
    }

    return YamlColumnFieldType.none;
  }

  static int _getIndent(String line) {
    int count = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        count++;
      } else if (line[i] == '\t') {
        count += 2;
      } else {
        break;
      }
    }
    return count;
  }

  static String _extractCurrentWord(String textBeforeCursor) {
    // Si estamos en una lista separada por comas (columns: a, b, c)
    if (textBeforeCursor.contains(',')) {
      final lastToken = textBeforeCursor.split(',').last;
      return lastToken.trim();
    }
    // Si estamos tras ':'
    if (textBeforeCursor.contains(':')) {
      final afterColon = textBeforeCursor.split(':').last;
      return afterColon.trim();
    }
    // Palabra al final
    final match = RegExp(r'([A-Za-z0-9_]+)$').firstMatch(textBeforeCursor);
    return match?.group(1) ?? '';
  }
}
