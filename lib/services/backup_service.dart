import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/procedimiento.dart';

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
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final fecha =
        '${now.year}-${p(now.month)}-${p(now.day)} ${p(now.hour)}:${p(now.minute)}:${p(now.second)}';
    final partLabel = part != null ? ' ($part)' : '';
    final partSuffix = part != null ? '_$part' : '';

    final script =
        '''-- ============================================================
-- BACKUP Schema Object — SirWeb
-- Objeto      : $objectName
-- Tipo        : $objectType$partLabel
-- Ambiente    : $ambiente
-- FechaBackup : $fecha
-- ============================================================

$source
''';

    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar backup — $objectName ($ambiente)',
      fileName:
          '${objectName}_${objectType}${partSuffix}_${ambiente.toUpperCase()}.sql',
      type: FileType.custom,
      allowedExtensions: ['sql'],
    );
    if (path == null) return null;

    await File(path).writeAsString(script, flush: true);
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
    return _parseScript(content);
  }

  // ── Script generation — Oracle MERGE against SIR.PROCEDIMIENTODINAMICO ───

  static String _buildScript(
    Procedimiento proc,
    String ambiente,
    String cdUsuario,
  ) {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final fecha =
        '${now.year}-${p(now.month)}-${p(now.day)} ${p(now.hour)}:${p(now.minute)}:${p(now.second)}';
    final estado = proc.activo ? '1' : '0';

    // Escape single quotes in the procedure code for SQL safety
    final safeTexto = proc.deTexto.replaceAll("'", "''");

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
  v_texto := '$safeTexto';

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
  COMMIT;
END;
/
""";
  }

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

    // Extract procedure code: content of the CLOB assignment  v_texto := '...';
    String deTexto = '';
    final assignMatch = RegExp(
      r"v_texto\s*:=\s*'([\s\S]*?)';\s*\n\s*MERGE",
    ).firstMatch(content);
    if (assignMatch != null) {
      // Unescape doubled single quotes
      deTexto = assignMatch.group(1)!.replaceAll("''", "'");
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
