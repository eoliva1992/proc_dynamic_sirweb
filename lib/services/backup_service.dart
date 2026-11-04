import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/procedimiento.dart';
import 'app_log.dart';

typedef BackupData = ({
  String cdProcedimiento,
  String deTexto,
  String inConfiguracion,
  String ambiente,
  int version,
});

abstract final class BackupService {
  // ── Export (Procedimiento dinámico) ──────────────────────────────────────

  /// Exporta el backup y devuelve la ruta del archivo escrito,
  /// o `null` si el usuario canceló el diálogo.
  static Future<String?> exportar(
    Procedimiento proc,
    String ambiente,
    String cdUsuario,
  ) async {
    final script = _buildScript(proc, ambiente, cdUsuario);

    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar backup — ${proc.cdProcedimiento}',
      fileName: '${proc.cdProcedimiento}_${ambiente.toUpperCase()}.sql',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );
    if (path == null) return null;

    await File(path).writeAsString(script, flush: true);
    AppLog.instance.transaction(
      'Backup ${proc.cdProcedimiento}',
      source: 'Backup',
      datos: {'Ambiente': ambiente, 'Usuario': cdUsuario, 'Archivo': path},
    );
    return path;
  }

  // ── Export (Objeto de esquema Oracle: PACKAGE, PROCEDURE, etc.) ──────────

  /// Guarda el DDL fuente de un objeto de esquema Oracle en un archivo .sql.
  /// [part] puede ser 'SPEC', 'BODY' o null cuando no aplica.
  /// Devuelve la ruta del archivo escrito, o `null` si se canceló.
  static Future<String?> exportarDdl({
    required String objectName,
    required String objectType,
    required String ambiente,
    required String source,
    String? part,
  }) async {
    final partSuffix = part != null ? '_$part' : '';

    final script = buildSchemaScript(
      objectName: objectName,
      objectType: objectType,
      ambiente: ambiente,
      source: source,
      part: part,
    );

    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar backup — $objectName ($ambiente)',
      fileName:
          '${objectName}_$objectType${partSuffix}_${ambiente.toUpperCase()}.sql',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );
    if (path == null) return null;

    await File(path).writeAsString(script, flush: true);
    AppLog.instance.transaction(
      'Backup $objectName ($objectType)',
      source: 'Backup',
      datos: {'Ambiente': ambiente, 'Parte': part, 'Archivo': path},
    );
    return path;
  }

  static String buildSchemaScript({
    required String objectName,
    required String objectType,
    required String ambiente,
    required String source,
    String? part,
  }) => source;

  /// Extrae el esquema/dueño (OWNER) de un objeto Oracle a partir de su DDL
  /// (por ejemplo: `CREATE OR REPLACE PROCEDURE PRODUCTO.MI_PROC ...`
  /// o `CREATE OR REPLACE PROCEDURE "PRODUCTO"."MI_PROC"`).
  /// Retorna una cadena vacía si no se especifica esquema en el DDL.
  static String extractOwnerFromDdl(String ddl) {
    if (ddl.trim().isEmpty) return '';
    final re = RegExp(
      r'CREATE\s+(?:OR\s+REPLACE\s+)?(?:EDITIONABLE\s+|NONEDITIONABLE\s+)?'
      r'(?:PACKAGE\s+BODY|PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE\s+BODY|TYPE|VIEW)\s+'
      r'(?:"?([A-Za-z0-9_#$]+)"?\s*\.\s*)'
      r'"?[A-Za-z0-9_#$]+"?',
      caseSensitive: false,
    );
    final match = re.firstMatch(ddl);
    if (match != null) {
      final owner = match.group(1);
      if (owner != null && owner.trim().isNotEmpty) {
        return owner.replaceAll('"', '').trim().toUpperCase();
      }
    }
    return '';
  }

  /// Genera un script SQL restaurable para un objeto de esquema Oracle,
  /// contemplando SPEC y BODY para objetos compuestos (PACKAGE/TYPE).
  static String buildFullSchemaScript({
    required String objectName,
    required String objectType,
    required String ambiente,
    required String specSource,
    String? bodySource,
  }) {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final fecha =
        '${now.year}-${p(now.month)}-${p(now.day)} ${p(now.hour)}:${p(now.minute)}:${p(now.second)}';

    final buffer = StringBuffer();
    buffer.writeln(
      '-- ============================================================',
    );
    buffer.writeln('-- BACKUP SCHEMA OBJECT');
    buffer.writeln('-- Objeto   : $objectName');
    buffer.writeln('-- Tipo     : $objectType');
    buffer.writeln('-- Ambiente : $ambiente');
    buffer.writeln('-- Fecha    : $fecha');
    buffer.writeln(
      '-- ============================================================',
    );
    buffer.writeln();

    String normalizeDdl(String ddl) {
      final trimmed = ddl.trim();
      if (trimmed.isEmpty) return '';
      if (trimmed.endsWith('/')) return trimmed;
      if (trimmed.endsWith(';')) return '$trimmed\n/';
      return '$trimmed\n/';
    }

    if (objectType.toUpperCase() == 'PACKAGE' ||
        objectType.toUpperCase() == 'TYPE') {
      if (specSource.trim().isNotEmpty) {
        buffer.writeln('-- === SPEC ===');
        buffer.writeln(normalizeDdl(specSource));
        buffer.writeln();
      }
      if (bodySource != null && bodySource.trim().isNotEmpty) {
        buffer.writeln('-- === BODY ===');
        buffer.writeln(normalizeDdl(bodySource));
        buffer.writeln();
      }
    } else {
      buffer.writeln(normalizeDdl(specSource));
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Exporta el DDL completo (con SPEC y BODY si aplica) al disco como backup .sql.
  /// Devuelve la ruta donde se guardó, o null si el usuario canceló el diálogo.
  static Future<String?> exportarDdlCompleto({
    required String objectName,
    required String objectType,
    required String ambiente,
    required String specSource,
    String? bodySource,
  }) async {
    final script = buildFullSchemaScript(
      objectName: objectName,
      objectType: objectType,
      ambiente: ambiente,
      specSource: specSource,
      bodySource: bodySource,
    );

    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar backup previo — $objectName ($ambiente)',
      fileName:
          '${objectName}_${objectType}_${ambiente.toUpperCase()}_backup.sql',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );
    if (path == null) return null;

    await File(path).writeAsString(script, flush: true);
    AppLog.instance.transaction(
      'Backup completo $objectName ($objectType)',
      source: 'Backup',
      datos: {'Ambiente': ambiente, 'Archivo': path},
    );
    return path;
  }

  // ── Abrir el explorador de archivos ─────────────────────────────────────

  /// Abre el explorador de archivos del sistema con [path] seleccionado.
  /// Devuelve `true` si se lanzó el proceso correctamente.
  static Future<bool> revealInExplorer(String path) async {
    try {
      final file = File(path);
      final target = file.existsSync()
          ? file.absolute.path
          : File(path).parent.absolute.path;

      if (Platform.isWindows) {
        // explorer.exe siempre devuelve exit code 1, incluso en éxito.
        await Process.run('explorer.exe', ['/select,', target]);
        return true;
      }
      if (Platform.isMacOS) {
        final r = await Process.run('open', ['-R', target]);
        return r.exitCode == 0;
      }
      if (Platform.isLinux) {
        final dir = File(target).parent.absolute.path;
        final r = await Process.run('xdg-open', [dir]);
        return r.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('[BackupService] No se pudo abrir el explorador: $e');
      return false;
    }
  }

  // ── Import ────────────────────────────────────────────────────────────────

  static Future<BackupData?> importar() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Abrir backup de procedimiento',
      type: FileType.custom,
      allowedExtensions: ['sql'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.first.path;
    if (path == null) return null;

    final content = await File(path).readAsString();
    final data = _parseScript(content);
    AppLog.instance.transaction(
      data == null
          ? 'Restaurar backup: archivo no reconocido'
          : 'Restaurar backup ${data.cdProcedimiento}',
      source: 'Backup',
      level: data == null ? LogLevel.warning : LogLevel.info,
      datos: {'Archivo': path, 'Ambiente': data?.ambiente},
    );
    return data;
  }

  // ── Script generation — Oracle MERGE against SIR.PROCEDIMIENTODINAMICO ───

  /// Envuelve un texto de código PL/SQL en un literal Oracle seguro para CLOB.
  /// Utiliza la sintaxis de comillas alternativas `q'[...]'` (o delimitador alternativo
  /// si el texto contiene `]'`) para evitar que herramientas como PL/SQL Developer
  /// o SQL*Plus interpreten `:` como variables de entrada / bind variables.
  static String formatClobLiteral(String code) {
    if (!code.contains("]'")) {
      return "q'[$code]'";
    } else if (!code.contains("}'")) {
      return "q'{$code}'";
    } else if (!code.contains(">'")) {
      return "q'<$code>'";
    } else if (!code.contains(")'")) {
      return "q'($code)'";
    } else if (!code.contains("~'")) {
      return "q'~$code~'";
    } else {
      // Fallback a escape estándar de comillas simples
      return "'${code.replaceAll("'", "''")}'";
    }
  }

  static String buildDynamicScript(
    Procedimiento proc,
    String ambiente,
    String cdUsuario,
  ) {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final fecha =
        '${now.year}-${p(now.month)}-${p(now.day)} ${p(now.hour)}:${p(now.minute)}:${p(now.second)}';
    final estado = proc.activo ? '1' : '0';

    final safeTextoLiteral = formatClobLiteral(proc.deTexto);

    return """-- ============================================================
-- BACKUP ProcDynamic SirWeb
-- Procedimiento : ${proc.cdProcedimiento}
-- Ambiente      : $ambiente
-- Version       : ${proc.version}
-- Estado        : $estado
-- Config        : ${proc.inConfiguracion}
-- Usuario       : $cdUsuario
-- FechaBackup   : $fecha
-- ============================================================
-- Para restaurar: ejecutar en SQL*Plus o herramienta Oracle
-- ============================================================

DECLARE
  v_texto CLOB;
BEGIN
  v_texto := $safeTextoLiteral;

  MERGE INTO SIR.PROCEDIMIENTODINAMICO T
  USING DUAL ON (T.CD_PROCEDIMIENTO = '${proc.cdProcedimiento}')
  WHEN MATCHED THEN UPDATE SET
    T.DE_TEXTO         = v_texto,
    T.ST_PROCEDIMIENTO = '$estado',
    T.IN_CONFIGURACION = '${proc.inConfiguracion}',
    T.CD_USUARIO       = '$cdUsuario',
    T.FE_MODIFICACION  = SYSDATE
  WHEN NOT MATCHED THEN INSERT (
    VERSION, CD_PROCEDIMIENTO, ST_PROCEDIMIENTO,
    DE_TEXTO, IN_CONFIGURACION, CD_USUARIO, FE_MODIFICACION
  ) VALUES (
    ${proc.version}, '${proc.cdProcedimiento}', '$estado',
    v_texto, '${proc.inConfiguracion}', '$cdUsuario', SYSDATE
  );
END;
/
""";
  }

  static String _buildScript(
    Procedimiento proc,
    String ambiente,
    String cdUsuario,
  ) => buildDynamicScript(proc, ambiente, cdUsuario);

  // ── Script parsing ────────────────────────────────────────────────────────

  static BackupData? _parseScript(String content) {
    final meta = <String, String>{};

    // Extract metadata from header comment lines
    for (final m in RegExp(
      r'^--\s*(\w+)\s*:\s*(.+)$',
      multiLine: true,
    ).allMatches(content)) {
      meta[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    }

    final cdProcedimiento = meta['procedimiento'];
    final ambiente = meta['ambiente'];
    final inConfiguracion = meta['config'] ?? 'D';
    final version = int.tryParse(meta['version'] ?? '') ?? 0;

    if (cdProcedimiento == null || ambiente == null) return null;

    // Extract procedure code: content of the CLOB assignment v_texto := q'[...]' or '...';
    String deTexto = '';
    final qMatch = RegExp(
      r"v_texto\s*:=\s*q'([\[<{([~])([\s\S]*?)([\s\S])';\s*\n\s*MERGE",
    ).firstMatch(content);

    if (qMatch != null) {
      deTexto = qMatch.group(2)!;
    } else {
      final assignMatch = RegExp(
        r"v_texto\s*:=\s*'([\s\S]*?)';\s*\n\s*MERGE",
      ).firstMatch(content);
      if (assignMatch != null) {
        // Unescape doubled single quotes
        deTexto = assignMatch.group(1)!.replaceAll("''", "'");
      }
    }

    return (
      cdProcedimiento: cdProcedimiento,
      deTexto: deTexto,
      inConfiguracion: inConfiguracion,
      ambiente: ambiente,
      version: version,
    );
  }
}
