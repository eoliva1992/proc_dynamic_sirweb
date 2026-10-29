import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/deploy_ticket.dart';
import '../models/reverse_sql_config.dart';
import '../models/sql_execution.dart';
import 'backup_service.dart';
import 'excel_exporter_service.dart';
import 'schema_service.dart';
import 'sirweb_service.dart';
import 'sql_executor_service.dart';

/// Item de resultado para cada archivo generado en el paquete de exportación.
class ExportedDeployFile {
  final String nombreArchivo;
  final String rutaCompleta;
  final String
  categoria; // RN, PROC, FUN, TRG, OBJ, PCK, SQL, RSQL, BLK, EXCEL, SCRIPT_AUDITORIA
  final int byteSize;

  const ExportedDeployFile({
    required this.nombreArchivo,
    required this.rutaCompleta,
    required this.categoria,
    required this.byteSize,
  });
}

/// Progreso reportado durante la exportación de artefactos.
class DeployExportProgress {
  final int total;
  final int actual;
  final String mensaje;

  const DeployExportProgress({
    required this.total,
    required this.actual,
    required this.mensaje,
  });

  double get porcentaje => total == 0 ? 1.0 : (actual / total).clamp(0.0, 1.0);
}

/// Servicio que orquesta la extracción y exportación completa de un ticket de pase a producción:
/// 1. Extrae desde la BD origen del ticket (ej. 'DESA'):
///    - Reglas de negocio (RN): Consulta SIR.PROCEDIMIENTODINAMICO, genera MERGE y nombra:
///      `{posicion:00}-{usuario}-{nombreReglaLimpio}-{yyyymmdd}-V{version}.sql`
///    - Procedimientos, funciones, triggers, types: `{DUENO}.{NOMBRE}.sql`
///    - Paquetes: `{PAQUETE}.sql` (especificación y cuerpo juntos separados por /)
///    - Bloques lógicos (BLK): `block-{usuario}-{nombre}{ddmmyyyy}-{yyyymmdd}-V{version}.sql` (envueltos en BEGIN..END; /)
///    - SQL: `{posicion:00}-{usuario}-{nombre}-{ddmmyyyy}-V{version}.sql`
///    - RSQL: Lee el YAML, consulta la BD origen con SqlExecutorService, genera DML y nombra:
///      `{posicion:00}-{usuario}-{nombre}Reverse{ddmmyyyy}-{yyyymmdd}-V{version}.sql`
/// 2. Genera el Excel `pase_archivo_{yyyymmddhhmmss}.xlsx` con la hoja 'Pase Git' y las 10 columnas oficiales.
/// 3. Genera el script SQL de auditoría `pase_script_{yyyymmddhhmmss}.sql` para la tabla `PASEAMBIENTESCRIPT`.
class DeployTicketExporterService {
  final SirwebService sirwebService;
  final SchemaService schemaService;
  final SqlExecutorService sqlExecutorService;
  final ExcelExporterService excelExporter;

  DeployTicketExporterService({
    SirwebService? sirwebService,
    SchemaService? schemaService,
    SqlExecutorService? sqlExecutorService,
    ExcelExporterService? excelExporter,
  }) : sirwebService = sirwebService ?? SirwebService(),
       schemaService = schemaService ?? SchemaService.instance,
       sqlExecutorService = sqlExecutorService ?? SqlExecutorService(),
       excelExporter = excelExporter ?? ExcelExporterService.instance;

  static final DeployTicketExporterService instance =
      DeployTicketExporterService();

  /// Limpia un nombre de regla de negocio para que contenga únicamente letras,
  /// eliminando guiones, guiones bajos, espacios y números.
  static String sanitizeRuleName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z]'), '');
  }

  /// Formatea la fecha en formato yyyymmdd (ej. 20261026).
  static String formatDateYmd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Formatea la fecha en formato ddmmyyyy (ej. 26102026).
  static String formatDateDdmmyyyy(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d$m$y';
  }

  /// Formatea la fecha y hora sin caracteres especiales (ej. 20261026085835).
  static String formatTimestamp(DateTime date) {
    final ymd = formatDateYmd(date);
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$ymd$h$min$s';
  }

  /// Formatea fecha legible dd/MM/yyyy.
  static String formatDateDdMmYyyy(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }

  /// Capitaliza un texto (ej. "matriz" -> "Matriz").
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Ejecuta la exportación integral de artefactos de un ticket en la carpeta destino seleccionada.
  Future<List<ExportedDeployFile>> exportarTicket({
    required DeployTicket ticket,
    required String targetDirectoryPath,
    void Function(DeployExportProgress progress)? onProgress,
  }) async {
    final baseDir = Directory(targetDirectoryPath);
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final now = DateTime.now();
    final fechaYmd = formatDateYmd(now);
    final fechaDdmmyyyy = formatDateDdmmyyyy(now);
    final timestamp = formatTimestamp(now);
    final horaActualStr = now.hour.toString().padLeft(2, '0');

    // Nomenclatura de carpeta: PaseScriptAmbiente{yyyymmdd}_{numeroSolicitud} (ej. PaseScriptAmbiente20261026_1305).
    // Si no tiene número de solicitud, se mantiene PaseScriptAmbiente{yyyymmdd}.
    final rawNumSol = ticket.numeroSolicitud.trim();
    final cleanNumSol = rawNumSol.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '');
    final folderName = cleanNumSol.isNotEmpty
        ? 'PaseScriptAmbiente${fechaYmd}_$cleanNumSol'
        : 'PaseScriptAmbiente$fechaYmd';

    // Carpeta contenedora. Si ya existe, se limpia y reemplaza su contenido; si no existe, se crea.
    final targetDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}$folderName',
    );
    if (await targetDir.exists()) {
      // Limpiar recursivamente el contenido existente para reemplazarlo
      await for (final entity in targetDir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } else {
      await targetDir.create(recursive: true);
    }

    final dbOrigen =
        (ticket.database != null && ticket.database!.trim().isNotEmpty)
        ? ticket.database!.trim()
        : 'Desa';
    final usuario = ticket.usuarioActualiza?.trim().isNotEmpty == true
        ? ticket.usuarioActualiza!.trim().toLowerCase()
        : (ticket.usuarioCrea.trim().isNotEmpty
              ? ticket.usuarioCrea.trim().toLowerCase()
              : 'usuario');
    final usuarioMayus = usuario.toUpperCase();
    final autorizaMayus = ticket.autoriza.trim().toUpperCase();

    final exportedFiles = <ExportedDeployFile>[];
    final excelRows = <List<dynamic>>[];

    // Calcular total aproximado de tareas para la barra de progreso
    final totalItems =
        ticket.reglasNegocio.length +
        ticket.sql.length +
        ticket.reverseSql.length +
        ticket.objetos.length +
        ticket.triggers.length +
        ticket.funciones.length +
        ticket.paquetes.length +
        ticket.bloqueLogico.length +
        2; // Excel + script de auditoría

    var currentProgress = 0;
    void report(String msg) {
      currentProgress++;
      onProgress?.call(
        DeployExportProgress(
          total: totalItems,
          actual: currentProgress,
          mensaje: msg,
        ),
      );
    }

    var posicion = 1;

    // Helper para guardar archivo de script directamente en PaseScriptAmbiente{yyyymmdd} y registrar en el Excel
    Future<void> registrarScript({
      required String fileName,
      required String content,
      required String categoria,
    }) async {
      final filePath = '${targetDir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsString(content, encoding: utf8);
      final bytes = await file.length();

      exportedFiles.add(
        ExportedDeployFile(
          nombreArchivo: fileName,
          rutaCompleta: filePath,
          categoria: categoria,
          byteSize: bytes.toInt(),
        ),
      );

      // Fila para el Excel 'Pase Git' (10 columnas):
      // NM_SCRIPT, FE_ACTU, FE_PASE, CD_USUARIO_AUTORIZADOR, CD_USUARIO_PASE,
      // VERSION, Tipo Solicitud, Solicitud, HR_EJECUCION, NU_APROBACION_AZURE_DEVOP
      excelRows.add([
        fileName,
        null, // FE_ACTU
        formatDateDdMmYyyy(now), // FE_PASE
        autorizaMayus,
        usuarioMayus,
        ticket.version,
        capitalize(ticket.tipoSolicitud),
        ticket.numeroSolicitud,
        horaActualStr,
        ticket.url?.trim().isNotEmpty == true ? ticket.url!.trim() : null,
      ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Reglas de Negocio (RN) -> Merge DML
    // Nomenclatura: {posicion:00}-{usuario}-{nombreReglaLimpio}-{yyyymmdd}-V{version}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final rn in ticket.reglasNegocio) {
      if (rn.trim().isEmpty) continue;
      final rnName = rn.trim();
      report('Consultando regla de negocio $rnName...');

      String scriptMerge;
      try {
        final proc = await sirwebService.obtenerProcedimiento(
          rnName,
          ambiente: dbOrigen,
        );
        scriptMerge = BackupService.buildDynamicScript(
          proc,
          dbOrigen,
          usuarioMayus,
        );
      } catch (e) {
        debugPrint('Error al consultar procedimiento $rnName: $e');
        // Si no se encuentra en el servicio, generar merge con placeholder
        scriptMerge = _buildFallbackDynamicMerge(
          cdProcedimiento: rnName,
          version: ticket.version,
          usuario: usuarioMayus,
        );
      }

      final cleanName = sanitizeRuleName(rnName);
      final posStr = posicion.toString().padLeft(2, '0');
      final fileName =
          '$posStr-$usuario-$cleanName-$fechaYmd-V${ticket.version}.sql';
      posicion++;

      await registrarScript(
        fileName: fileName,
        content: scriptMerge,
        categoria: 'RN',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Scripts SQL (SQL)
    // Nomenclatura: {posicion:00}-{usuario}-{nombre}-{ddmmyyyy}-V{version}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final s in ticket.sql) {
      if (s.nombre.trim().isEmpty) continue;
      report('Exportando script SQL ${s.nombre}...');
      final posStr = posicion.toString().padLeft(2, '0');
      final cleanBaseName = s.nombre
          .replaceAll('.sql', '')
          .replaceAll(' ', '_');
      final fileName =
          '$posStr-$usuario-$cleanBaseName-$fechaDdmmyyyy-V${ticket.version}.sql';
      posicion++;

      await registrarScript(
        fileName: fileName,
        content: s.contenido,
        categoria: 'SQL',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Reverse SQL (RSQL) -> Extracción desde BD Origen según YAML
    // Nomenclatura: {posicion:00}-{usuario}-{nombre}Reverse{ddmmyyyy}-{yyyymmdd}-V{version}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final r in ticket.reverseSql) {
      if (r.nombre.trim().isEmpty) continue;
      report('Extrayendo RSQL ${r.nombre} desde BD $dbOrigen...');

      final posStr = posicion.toString().padLeft(2, '0');
      final cleanBaseName = r.nombre
          .replaceAll('.yaml', '')
          .replaceAll('.yml', '')
          .replaceAll('.sql', '')
          .replaceAll(' ', '_');
      final fileName =
          '$posStr-$usuario-${cleanBaseName}Reverse$fechaDdmmyyyy-$fechaYmd-V${ticket.version}.sql';
      posicion++;

      String rsqlContent;
      try {
        rsqlContent = await _generarRsqlDesdeYaml(
          yamlContent: r.contenido,
          ambiente: dbOrigen,
          owner: 'SIR',
          usuario: usuarioMayus,
        );
      } catch (e) {
        debugPrint('Error extrayendo RSQL desde BD: $e');
        rsqlContent =
            '-- Error al extraer datos desde $dbOrigen: $e\n'
            '-- Contenido YAML original:\n'
            '${r.contenido.split('\n').map((l) => '-- $l').join('\n')}\n';
      }

      await registrarScript(
        fileName: fileName,
        content: rsqlContent,
        categoria: 'RSQL',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Objetos / Types (OBJ)
    // Nomenclatura: {DUENO}.{NOMBRE}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final obj in ticket.objetos) {
      if (obj.trim().isEmpty) continue;
      final objName = obj.trim().toUpperCase();
      report('Extrayendo Type / Objeto $objName...');
      final owner = await _resolverDueno(objName, 'TYPE', dbOrigen);
      final source = await _extraerFuenteObjeto(objName, 'TYPE', dbOrigen);
      final fileName = '$owner.$objName.sql';

      await registrarScript(
        fileName: fileName,
        content: source,
        categoria: 'OBJ',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Triggers (TRG)
    // Nomenclatura: {DUENO}.{NOMBRE}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final trg in ticket.triggers) {
      if (trg.trim().isEmpty) continue;
      final trgName = trg.trim().toUpperCase();
      report('Extrayendo Trigger $trgName...');
      final owner = await _resolverDueno(trgName, 'TRIGGER', dbOrigen);
      final source = await _extraerFuenteObjeto(trgName, 'TRIGGER', dbOrigen);
      final fileName = '$owner.$trgName.sql';

      await registrarScript(
        fileName: fileName,
        content: source,
        categoria: 'TRG',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Funciones (FUN)
    // Nomenclatura: {DUENO}.{NOMBRE}.sql
    // ─────────────────────────────────────────────────────────────────────────
    for (final fun in ticket.funciones) {
      if (fun.trim().isEmpty) continue;
      final funName = fun.trim().toUpperCase();
      report('Extrayendo Función $funName...');
      final owner = await _resolverDueno(funName, 'FUNCTION', dbOrigen);
      final source = await _extraerFuenteObjeto(funName, 'FUNCTION', dbOrigen);
      final fileName = '$owner.$funName.sql';

      await registrarScript(
        fileName: fileName,
        content: source,
        categoria: 'FUN',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Paquetes (PCK)
    // Nomenclatura: {PAQUETE}.sql (especificación y cuerpo separados por /)
    // ─────────────────────────────────────────────────────────────────────────
    for (final pck in ticket.paquetes) {
      if (pck.trim().isEmpty) continue;
      final pckName = pck.trim().toUpperCase();
      report('Extrayendo Paquete $pckName...');
      final packageSource = await _extraerFuentePaquete(pckName, dbOrigen);
      final fileName = '$pckName.sql';

      await registrarScript(
        fileName: fileName,
        content: packageSource,
        categoria: 'PCK',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. Bloques Lógicos (BLK)
    // Nomenclatura: block-{usuario}-{nombre}{ddmmyyyy}-{yyyymmdd}-V{version}.sql
    // Contenido: envuelto en BEGIN ... END; /
    // ─────────────────────────────────────────────────────────────────────────
    for (final blk in ticket.bloqueLogico) {
      if (blk.nombre.trim().isEmpty) continue;
      report('Exportando bloque lógico ${blk.nombre}...');
      final cleanBaseName = blk.nombre
          .replaceAll('.sql', '')
          .replaceAll(' ', '_');
      final fileName =
          'block-$usuario-$cleanBaseName$fechaDdmmyyyy-$fechaYmd-V${ticket.version}.sql';

      final wrappedContent = _wrapBlockLogic(blk.contenido);

      await registrarScript(
        fileName: fileName,
        content: wrappedContent,
        categoria: 'BLK',
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 10. Archivo Excel .xlsx
    // Nombre: pase_archivo_{timestamp}.xlsx
    // ─────────────────────────────────────────────────────────────────────────
    report('Generando archivo Excel...');
    final excelFileName = 'pase_archivo_$timestamp.xlsx';
    final excelFilePath =
        '${targetDir.path}${Platform.pathSeparator}$excelFileName';
    final excelHeaders = [
      'NM_SCRIPT',
      'FE_ACTU',
      'FE_PASE',
      'CD_USUARIO_AUTORIZADOR',
      'CD_USUARIO_PASE',
      'VERSION',
      'Tipo Solicitud',
      'Solicitud',
      'HR_EJECUCION',
      'NU_APROBACION_AZURE_DEVOP',
    ];

    final excelBytes = excelExporter.generateXlsx(
      sheetName: 'Pase Git',
      headers: excelHeaders,
      rows: excelRows,
    );
    final excelFile = File(excelFilePath);
    await excelFile.writeAsBytes(excelBytes);

    exportedFiles.add(
      ExportedDeployFile(
        nombreArchivo: excelFileName,
        rutaCompleta: excelFilePath,
        categoria: 'EXCEL',
        byteSize: excelBytes.length,
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 11. Script SQL para tabla PASEAMBIENTESCRIPT
    // Nombre: pase_script_{timestamp}.sql
    // ─────────────────────────────────────────────────────────────────────────
    report('Generando script SQL de auditoría PASEAMBIENTESCRIPT...');
    final auditFileName = 'pase_script_$timestamp.sql';
    final auditFilePath =
        '${targetDir.path}${Platform.pathSeparator}$auditFileName';

    final auditSql = _buildPaseAmbienteScriptSql(
      ticket: ticket,
      scriptsGenerados: excelRows.map((r) => r[0] as String).toList(),
      now: now,
      usuarioPase: usuarioMayus,
      usuarioAutoriza: autorizaMayus,
    );

    final auditFile = File(auditFilePath);
    await auditFile.writeAsString(auditSql, encoding: utf8);

    exportedFiles.add(
      ExportedDeployFile(
        nombreArchivo: auditFileName,
        rutaCompleta: auditFilePath,
        categoria: 'SCRIPT_AUDITORIA',
        byteSize: auditSql.length,
      ),
    );

    report('Exportación finalizada con éxito.');
    return exportedFiles;
  }

  /// Exporta únicamente los scripts de artefactos del ticket directamente a [targetDirectoryPath],
  /// sin crear subcarpetas `PaseScriptAmbiente...`, sin generar el archivo Excel `.xlsx`
  /// y sin generar el script `pase_script_*.sql` para `PASEAMBIENTESCRIPT`.
  ///
  /// Especialmente diseñado para la integración directa con la rama de Hotfix en el repositorio Git.
  Future<List<ExportedDeployFile>> exportarScriptsHotfix({
    required DeployTicket ticket,
    required String targetDirectoryPath,
    void Function(DeployExportProgress progress)? onProgress,
  }) async {
    final targetDir = Directory(targetDirectoryPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final dbOrigen =
        (ticket.database != null && ticket.database!.trim().isNotEmpty)
        ? ticket.database!.trim()
        : 'Desa';
    final usuario = ticket.usuarioActualiza?.trim().isNotEmpty == true
        ? ticket.usuarioActualiza!.trim().toLowerCase()
        : (ticket.usuarioCrea.trim().isNotEmpty
              ? ticket.usuarioCrea.trim().toLowerCase()
              : 'usuario');
    final usuarioMayus = usuario.toUpperCase();

    final exportedFiles = <ExportedDeployFile>[];

    final now = DateTime.now();
    final fechaYmd = formatDateYmd(now);
    final fechaDdmmyyyy = formatDateDdmmyyyy(now);

    final totalItems =
        ticket.reglasNegocio.length +
        ticket.sql.length +
        ticket.reverseSql.length +
        ticket.objetos.length +
        ticket.triggers.length +
        ticket.funciones.length +
        ticket.paquetes.length +
        ticket.bloqueLogico.length;

    var currentProgress = 0;
    void report(String msg) {
      currentProgress++;
      onProgress?.call(
        DeployExportProgress(
          total: totalItems,
          actual: currentProgress,
          mensaje: msg,
        ),
      );
    }

    var posicion = 1;

    Future<void> registrarScript({
      required String fileName,
      required String content,
      required String categoria,
    }) async {
      final filePath = '${targetDir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsString(content, encoding: utf8);
      final bytes = await file.length();

      exportedFiles.add(
        ExportedDeployFile(
          nombreArchivo: fileName,
          rutaCompleta: filePath,
          categoria: categoria,
          byteSize: bytes.toInt(),
        ),
      );
    }

    // 1. Reglas de Negocio (RN)
    for (final rn in ticket.reglasNegocio) {
      if (rn.trim().isEmpty) continue;
      final rnName = rn.trim();
      report('Consultando regla de negocio $rnName...');

      String scriptMerge;
      try {
        final proc = await sirwebService.obtenerProcedimiento(
          rnName,
          ambiente: dbOrigen,
        );
        scriptMerge = BackupService.buildDynamicScript(
          proc,
          dbOrigen,
          usuarioMayus,
        );
      } catch (e) {
        scriptMerge = _buildFallbackDynamicMerge(
          cdProcedimiento: rnName,
          version: ticket.version,
          usuario: usuarioMayus,
        );
      }

      final posStr = posicion.toString().padLeft(2, '0');
      final cleanName = sanitizeRuleName(rnName);
      final fileName =
          '$posStr-$usuario-$cleanName-$fechaYmd-V${ticket.version}.sql';
      await registrarScript(
        fileName: fileName,
        content: scriptMerge,
        categoria: 'RN',
      );
      posicion++;
    }

    // 2. Paquetes (PCK)
    for (final pck in ticket.paquetes) {
      if (pck.trim().isEmpty) continue;
      final pckName = pck.trim().toUpperCase();
      report('Consultando paquete $pckName...');
      final ddl = await _extraerFuentePaquete(pckName, dbOrigen);
      final fileName = '$pckName.sql';
      await registrarScript(
        fileName: fileName,
        content: ddl,
        categoria: 'PAQUETE',
      );
    }

    // 3. Funciones (FUN)
    for (final fun in ticket.funciones) {
      if (fun.trim().isEmpty) continue;
      final funName = fun.trim().toUpperCase();
      report('Consultando función $funName...');
      final dueno = await _resolverDueno(funName, 'FUNCTION', dbOrigen);
      final ddl = await _extraerFuenteObjeto(funName, 'FUNCTION', dbOrigen);
      final fileName = '$dueno.$funName.sql';
      await registrarScript(
        fileName: fileName,
        content: ddl,
        categoria: 'FUNCION',
      );
    }

    // 4. Scripts SQL Directos (SQL)
    for (final s in ticket.sql) {
      if (s.nombre.trim().isEmpty) continue;
      final scriptName = s.nombre.trim();
      report('Escribiendo script SQL $scriptName...');
      final posStr = posicion.toString().padLeft(2, '0');
      final fileName =
          '$posStr-$usuario-$scriptName-$fechaDdmmyyyy-V${ticket.version}.sql';
      var content = s.contenido.trim();
      if (!content.endsWith('/') && !content.endsWith(';')) {
        content = '$content\n/';
      }
      await registrarScript(
        fileName: fileName,
        content: '$content\n',
        categoria: 'SQL',
      );
      posicion++;
    }

    // 5. Reverse SQL (RSQL)
    for (final r in ticket.reverseSql) {
      if (r.nombre.trim().isEmpty) continue;
      final rName = r.nombre.trim();
      report('Generando Reverse SQL para $rName...');
      String dmlGenerado;
      try {
        dmlGenerado = await _generarRsqlDesdeYaml(
          yamlContent: r.contenido,
          ambiente: dbOrigen,
          owner: 'SIR',
          usuario: usuario,
        );
      } catch (e) {
        dmlGenerado = '-- Error al generar DML de RSQL $rName: $e\n';
      }

      final posStr = posicion.toString().padLeft(2, '0');
      final fileName =
          '$posStr-$usuario-${rName}Reverse$fechaDdmmyyyy-$fechaYmd-V${ticket.version}.sql';
      await registrarScript(
        fileName: fileName,
        content: dmlGenerado,
        categoria: 'RSQL',
      );
      posicion++;
    }

    // 6. Objetos / Types (OBJ)
    for (final obj in ticket.objetos) {
      if (obj.trim().isEmpty) continue;
      final objName = obj.trim().toUpperCase();
      report('Consultando objeto/type $objName...');
      final dueno = await _resolverDueno(objName, 'TYPE', dbOrigen);
      final ddl = await _extraerFuenteObjeto(objName, 'TYPE', dbOrigen);
      final fileName = '$dueno.$objName.sql';
      await registrarScript(
        fileName: fileName,
        content: ddl,
        categoria: 'OBJETO',
      );
    }

    // 7. Triggers (TRG)
    for (final trg in ticket.triggers) {
      if (trg.trim().isEmpty) continue;
      final trgName = trg.trim().toUpperCase();
      report('Consultando trigger $trgName...');
      final dueno = await _resolverDueno(trgName, 'TRIGGER', dbOrigen);
      final ddl = await _extraerFuenteObjeto(trgName, 'TRIGGER', dbOrigen);
      final fileName = '$dueno.$trgName.sql';
      await registrarScript(
        fileName: fileName,
        content: ddl,
        categoria: 'TRIGGER',
      );
    }

    // 8. Bloques Lógicos (BLK)
    for (final b in ticket.bloqueLogico) {
      if (b.nombre.trim().isEmpty) continue;
      final bName = b.nombre.trim();
      report('Escribiendo bloque lógico $bName...');
      final fileName =
          'block-$usuario-$bName$fechaDdmmyyyy-$fechaYmd-V${ticket.version}.sql';
      final wrapped = _wrapBlockLogic(b.contenido);
      await registrarScript(
        fileName: fileName,
        content: wrapped,
        categoria: 'BLOQUE_LOGICO',
      );
    }

    report('Generación de scripts hotfix completada.');
    return exportedFiles;
  }

  /// Crea la estructura de directorio local y genera los archivos base del ticket:
  /// - `index.txt` con la configuración completa generada por [DeployTicket.toIndexTxt]
  /// - Archivos SQL con el contenido guardado en los scripts del ticket (`sql`, `reverseSql`, `bloqueLogico`)
  /// - Archivos placeholder para los artefactos de texto (`reglasNegocio`, `paquetes`, `funciones`, `triggers`, `objetos`)
  ///
  /// La carpeta resultante se crea en `${rootDirectoryPath}${Platform.pathSeparator}${folderName}`.
  /// Si la carpeta ya existe, no se borra completamente para preservar posibles archivos existentes,
  /// pero se sobrescriben o crean los archivos correspondientes al ticket.
  Future<List<ExportedDeployFile>> crearDirectorioYArchivos({
    required DeployTicket ticket,
    required String rootDirectoryPath,
    required String folderName,
  }) async {
    final cleanFolder = folderName.trim().replaceAll(
      RegExp(r'[\\/:*?"<>|]+'),
      '',
    );
    final effectiveFolder = cleanFolder.isNotEmpty
        ? cleanFolder
        : ticket.suggestedFolderName;

    final targetDir = Directory(
      '${rootDirectoryPath.trim()}${Platform.pathSeparator}$effectiveFolder',
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final exportedFiles = <ExportedDeployFile>[];

    Future<void> escribirArchivo({
      required String nombreArchivo,
      required String contenido,
      required String categoria,
    }) async {
      final safeName = nombreArchivo.trim().replaceAll(
        RegExp(r'[\\/:*?"<>|]+'),
        '',
      );
      if (safeName.isEmpty) return;
      final filePath = '${targetDir.path}${Platform.pathSeparator}$safeName';
      final file = File(filePath);
      await file.writeAsString(contenido, encoding: utf8);
      final byteSize = await file.length();
      exportedFiles.add(
        ExportedDeployFile(
          nombreArchivo: safeName,
          rutaCompleta: filePath,
          categoria: categoria,
          byteSize: byteSize.toInt(),
        ),
      );
    }

    // 1. Archivo index.txt
    await escribirArchivo(
      nombreArchivo: 'index.txt',
      contenido: ticket.toIndexTxt(),
      categoria: 'INDEX',
    );

    // Helper para resolver el nombre de archivo respetando su extensión original
    String resolverNombre(String raw, {String defaultExtension = '.sql'}) {
      final trimmed = raw.trim();
      final lower = trimmed.toLowerCase();
      // Si ya tiene una extensión reconocida o formato con punto (.xxx)
      if (RegExp(r'\.[a-zA-Z0-9_]+$').hasMatch(lower)) {
        return trimmed;
      }
      final ext = defaultExtension.startsWith('.')
          ? defaultExtension
          : '.$defaultExtension';
      return '$trimmed$ext';
    }

    // 2. Scripts SQL personalizados
    for (final s in ticket.sql) {
      if (s.nombre.trim().isEmpty) continue;
      final fileName = resolverNombre(s.nombre, defaultExtension: '.sql');
      await escribirArchivo(
        nombreArchivo: fileName,
        contenido: s.contenido,
        categoria: 'SQL',
      );
    }

    // 3. Scripts de ingeniería inversa (RSQL)
    for (final r in ticket.reverseSql) {
      if (r.nombre.trim().isEmpty) continue;
      final fileName = resolverNombre(r.nombre, defaultExtension: '.yaml');
      await escribirArchivo(
        nombreArchivo: fileName,
        contenido: r.contenido,
        categoria: 'RSQL',
      );
    }

    // 4. Bloques Lógicos
    for (final b in ticket.bloqueLogico) {
      if (b.nombre.trim().isEmpty) continue;
      final fileName = resolverNombre(b.nombre, defaultExtension: '.sql');
      final content = b.contenido.trim().isNotEmpty
          ? _wrapBlockLogic(b.contenido)
          : '';
      await escribirArchivo(
        nombreArchivo: fileName,
        contenido: content,
        categoria: 'BLOQUE_LOGICO',
      );
    }

    // 5. Artefactos de lista (Reglas, Paquetes, Funciones, Triggers, Objetos)
    for (final rn in ticket.reglasNegocio) {
      if (rn.trim().isEmpty) continue;
      final fileName = resolverNombre(rn, defaultExtension: '.sql');
      // Solo crear si no fue generado previamente
      if (!exportedFiles.any(
        (f) => f.nombreArchivo.toLowerCase() == fileName.toLowerCase(),
      )) {
        await escribirArchivo(
          nombreArchivo: fileName,
          contenido: '-- Regla de Negocio: ${rn.trim()}\n',
          categoria: 'RN',
        );
      }
    }

    for (final pck in ticket.paquetes) {
      if (pck.trim().isEmpty) continue;
      final fileName = resolverNombre(pck, defaultExtension: '.sql');
      if (!exportedFiles.any(
        (f) => f.nombreArchivo.toLowerCase() == fileName.toLowerCase(),
      )) {
        await escribirArchivo(
          nombreArchivo: fileName,
          contenido: '-- Paquete: ${pck.trim()}\n',
          categoria: 'PAQUETE',
        );
      }
    }

    for (final fun in ticket.funciones) {
      if (fun.trim().isEmpty) continue;
      final fileName = resolverNombre(fun, defaultExtension: '.sql');
      if (!exportedFiles.any(
        (f) => f.nombreArchivo.toLowerCase() == fileName.toLowerCase(),
      )) {
        await escribirArchivo(
          nombreArchivo: fileName,
          contenido: '-- Función / Procedimiento: ${fun.trim()}\n',
          categoria: 'FUNCION',
        );
      }
    }

    for (final trg in ticket.triggers) {
      if (trg.trim().isEmpty) continue;
      final fileName = resolverNombre(trg, defaultExtension: '.sql');
      if (!exportedFiles.any(
        (f) => f.nombreArchivo.toLowerCase() == fileName.toLowerCase(),
      )) {
        await escribirArchivo(
          nombreArchivo: fileName,
          contenido: '-- Trigger: ${trg.trim()}\n',
          categoria: 'TRIGGER',
        );
      }
    }

    for (final obj in ticket.objetos) {
      if (obj.trim().isEmpty) continue;
      final fileName = resolverNombre(obj, defaultExtension: '.sql');
      if (!exportedFiles.any(
        (f) => f.nombreArchivo.toLowerCase() == fileName.toLowerCase(),
      )) {
        await escribirArchivo(
          nombreArchivo: fileName,
          contenido: '-- Objeto: ${obj.trim()}\n',
          categoria: 'OBJETO',
        );
      }
    }

    return exportedFiles;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Métodos auxiliares de extracción y generación
  // ─────────────────────────────────────────────────────────────────────────

  /// Resuelve el dueño del objeto en Oracle consultando SchemaService.getObjectInfo.
  Future<String> _resolverDueno(
    String objectName,
    String objectType,
    String ambiente,
  ) async {
    try {
      final info = await schemaService.getObjectInfo(
        objectName,
        objectType,
        ambiente: ambiente,
      );
      for (final e in info) {
        if (e.name.toUpperCase() == 'OWNER' && e.value.trim().isNotEmpty) {
          return e.value.trim().toUpperCase();
        }
      }
    } catch (_) {}

    // Intentar desde caché de SchemaMetadata
    final cached = schemaService.getCached(ambiente: ambiente);
    if (cached != null) {
      final found = cached.objects.firstWhere(
        (o) =>
            o.name.toUpperCase() == objectName.toUpperCase() &&
            o.type.toUpperCase() == objectType.toUpperCase(),
        orElse: () => (name: '', type: '', owner: ''),
      );
      if (found.owner.isNotEmpty) return found.owner.toUpperCase();
      if (cached.owner.isNotEmpty) return cached.owner.toUpperCase();
    }

    return 'SIR'; // Fallback por defecto en Sirweb
  }

  /// Extrae el DDL / código fuente de un objeto Oracle (PROCEDURE, FUNCTION, TRIGGER, TYPE).
  Future<String> _extraerFuenteObjeto(
    String objectName,
    String objectType,
    String ambiente,
  ) async {
    try {
      final result = await schemaService.getObjectSource(
        objectName,
        objectType,
        ambiente: ambiente,
      );
      final spec = result.spec.trim();
      final body = result.body?.trim();

      if (body != null && body.isNotEmpty) {
        return '$spec\n/\n\n$body\n/\n';
      }
      return spec.endsWith('/') ? spec : '$spec\n/\n';
    } catch (e) {
      return '-- Error al obtener DDL de $objectType $objectName desde $ambiente: $e\n';
    }
  }

  /// Extrae el paquete completo con especificación y cuerpo separados por `/`.
  Future<String> _extraerFuentePaquete(
    String packageName,
    String ambiente,
  ) async {
    try {
      final result = await schemaService.getObjectSource(
        packageName,
        'PACKAGE',
        ambiente: ambiente,
      );
      final spec = result.spec.trim();
      final body = (result.body ?? '').trim();

      final buffer = StringBuffer();
      if (spec.isNotEmpty) {
        buffer.writeln(spec);
        if (!spec.endsWith('/')) buffer.writeln('/');
      }
      if (body.isNotEmpty) {
        buffer.writeln();
        buffer.writeln(body);
        if (!body.endsWith('/')) buffer.writeln('/');
      }
      return buffer.toString();
    } catch (e) {
      return '-- Error al obtener DDL de PACKAGE $packageName desde $ambiente: $e\n';
    }
  }

  /// Envoltorio de bloques lógicos en BEGIN ... END; /
  String _wrapBlockLogic(String content) {
    var trimmed = content.trim();
    if (trimmed.isEmpty) return 'BEGIN\n  NULL;\nEND;\n/\n';

    final upper = trimmed.toUpperCase();
    if (upper.startsWith('BEGIN') ||
        upper.startsWith('DECLARE') ||
        upper.startsWith('MERGE') ||
        upper.startsWith('INSERT') ||
        upper.startsWith('UPDATE')) {
      if (!trimmed.endsWith('/')) {
        return '$trimmed\n/\n';
      }
      return '$trimmed\n';
    }

    return 'BEGIN\n$trimmed\nEND;\n/\n';
  }

  /// Genera DML a partir de una configuración YAML de Reverse SQL consultando la BD origen.
  Future<String> _generarRsqlDesdeYaml({
    required String yamlContent,
    required String ambiente,
    required String owner,
    required String usuario,
  }) async {
    final config = ReverseSqlConfig.parseYaml(yamlContent);
    final buffer = StringBuffer();
    buffer.writeln(
      '-- =============================================================================',
    );
    buffer.writeln(
      '-- Script generado a partir de configuración RSQL (Ingeniería Inversa)',
    );
    buffer.writeln(
      '-- Base de datos origen: $ambiente | Esquema: $owner | Usuario: $usuario',
    );
    buffer.writeln(
      '-- =============================================================================\n',
    );

    for (final table in config.tables) {
      if (table.name.trim().isEmpty) continue;
      final tableName = table.name.trim().toUpperCase();
      buffer.writeln(
        '-- Tabla: $tableName (DML: ${table.dml.name.toUpperCase()})',
      );

      // 1. Construir WHERE desde filters e ins
      final whereClauses = <String>[];
      table.filters.forEach((col, expr) {
        final colTrim = col.trim();
        final exprTrim = expr.trim();
        if (colTrim.isNotEmpty && exprTrim.isNotEmpty) {
          if (exprTrim.startsWith('=') ||
              exprTrim.startsWith('>') ||
              exprTrim.startsWith('<') ||
              exprTrim.toUpperCase().startsWith('LIKE') ||
              exprTrim.toUpperCase().startsWith('IS')) {
            whereClauses.add('$colTrim $exprTrim');
          } else {
            whereClauses.add("$colTrim = '$exprTrim'");
          }
        }
      });

      table.ins.forEach((col, inList) {
        final colTrim = col.trim();
        final inTrim = inList.trim();
        if (colTrim.isNotEmpty && inTrim.isNotEmpty) {
          whereClauses.add('$colTrim IN ($inTrim)');
        }
      });

      String query;
      if (table.sql != null && table.sql!.trim().isNotEmpty) {
        query = table.sql!.trim();
      } else {
        final wherePart = whereClauses.isNotEmpty
            ? ' WHERE ${whereClauses.join(' AND ')}'
            : '';
        query = 'SELECT * FROM $tableName$wherePart';
      }

      // 2. Ejecutar consulta sobre BD origen
      SqlQueryResult result;
      try {
        result = await sqlExecutorService.executeSelect(
          query,
          owner: owner,
          ambiente: ambiente,
          maxRows: 1000,
        );
      } catch (e) {
        buffer.writeln('-- Error consultando $tableName: $e');
        buffer.writeln('-- Query intentada: $query\n');
        continue;
      }

      if (result.rows.isEmpty) {
        buffer.writeln(
          '-- (No se encontraron filas coincidentes para $tableName)\n',
        );
        continue;
      }

      // 3. Identificar columnas a incluir
      final filterCols =
          (table.columns != null && table.columns!.trim().isNotEmpty)
          ? table.columns!
                .split(',')
                .map((c) => c.trim().toUpperCase())
                .where((c) => c.isNotEmpty)
                .toSet()
          : <String>{};
      final columnsToInclude = <int>[];
      for (var i = 0; i < result.columns.length; i++) {
        final colName = result.columns[i].name.toUpperCase();
        if (filterCols.isEmpty || filterCols.contains(colName)) {
          columnsToInclude.add(i);
        }
      }

      // Columnas filtradas en la configuración YAML
      final filterNames = <String>{
        ...table.filters.keys.map((k) => k.trim().toUpperCase()),
        ...table.ins.keys.map((k) => k.trim().toUpperCase()),
      };

      // Obtener o inferir Primary Keys de la tabla
      final isPkAdd = table.pkAdd ?? false;
      final ignoredPks =
          (table.ignorePk != null && table.ignorePk!.trim().isNotEmpty)
          ? table.ignorePk!
                .split(',')
                .map((c) => c.trim().toUpperCase())
                .where((c) => c.isNotEmpty)
                .toSet()
          : <String>{};

      List<String> rawPks = [];
      if (isPkAdd) {
        try {
          rawPks = await schemaService.getPrimaryKeyColumns(
            tableName,
            ambiente: ambiente,
          );
        } catch (_) {
          rawPks = [];
        }
      }

      final activePks = rawPks
          .map((k) => k.toUpperCase())
          .where((k) => !ignoredPks.contains(k))
          .toSet();

      // Columnas clave efectivas para el ON / WHERE:
      // Si pkAdd == false: solo los filtros especificados en el YAML (si los hay).
      // Si pkAdd == true: los filtros especificados + las Primary Keys faltantes de la tabla.
      final effectiveKeys = <String>{...filterNames};
      if (isPkAdd) {
        effectiveKeys.addAll(activePks);
      }

      // Si no hay ninguna columna clave ni filtro definido, usamos la primera columna disponible como fallback
      if (effectiveKeys.isEmpty && columnsToInclude.isNotEmpty) {
        effectiveKeys.add(
          result.columns[columnsToInclude.first].name.toUpperCase(),
        );
      }

      // 4. Generar sentencias según operación DML
      switch (table.dml) {
        case ReverseSqlDml.insert:
          for (final row in result.rows) {
            final colsStr = columnsToInclude
                .map((i) => result.columns[i].name.toUpperCase())
                .join(', ');
            final valsStr = columnsToInclude
                .map((i) => _formatSqlValue(row[i], result.columns[i].dataType))
                .join(', ');
            buffer.writeln(
              'INSERT INTO $tableName ($colsStr) VALUES ($valsStr);',
            );
          }
          break;

        case ReverseSqlDml.delete:
          final wherePart = whereClauses.isNotEmpty
              ? ' WHERE ${whereClauses.join(' AND ')}'
              : '';
          buffer.writeln('DELETE FROM $tableName$wherePart;');
          break;

        case ReverseSqlDml.update:
          // Separado de MERGE: genera sentencias UPDATE bajo las condiciones especificadas
          // Las Primary Keys y columnas de filtro NUNCA deben actualizarse en SET
          final setColIndices = columnsToInclude.where((i) {
            final colName = result.columns[i].name.toUpperCase();
            return !effectiveKeys.contains(colName) &&
                !activePks.contains(colName);
          }).toList();

          for (final row in result.rows) {
            final rowSetParts = setColIndices
                .map((i) {
                  final col = result.columns[i];
                  final colName = col.name.toUpperCase();
                  final valStr = _formatSqlValue(row[i], col.dataType);
                  return '$colName = $valStr';
                })
                .join(', ');

            // Condición WHERE:
            // Si pkAdd == false: usar únicamente los filtros configurados (whereClauses)
            // Si pkAdd == true: agregar en el WHERE las PKs faltantes de la fila
            final rowWhereClauses = <String>[...whereClauses];
            if (isPkAdd) {
              for (final pk in activePks) {
                if (!filterNames.contains(pk)) {
                  final pkColIdx = result.columns.indexWhere(
                    (c) => c.name.toUpperCase() == pk,
                  );
                  if (pkColIdx >= 0) {
                    final pkVal = _formatSqlValue(
                      row[pkColIdx],
                      result.columns[pkColIdx].dataType,
                    );
                    rowWhereClauses.add('$pk = $pkVal');
                  }
                }
              }
            }

            String whereStr;
            if (rowWhereClauses.isNotEmpty) {
              whereStr = rowWhereClauses.join(' AND ');
            } else {
              final pkColIndex = columnsToInclude.first;
              final pkCol = result.columns[pkColIndex];
              whereStr =
                  '${pkCol.name.toUpperCase()} = ${_formatSqlValue(row[pkColIndex], pkCol.dataType)}';
            }

            buffer.writeln(
              'UPDATE $tableName SET $rowSetParts WHERE $whereStr;',
            );
          }
          break;

        case ReverseSqlDml.merge:
          // Cláusula ON: sólo los filtros si pkAdd == false; filtros + PKs si pkAdd == true
          final onKeys = result.columns
              .map((c) => c.name.toUpperCase())
              .where((name) => effectiveKeys.contains(name))
              .toList();

          final onClause = onKeys.isNotEmpty
              ? onKeys.map((k) => 'T.$k = S.$k').join(' AND ')
              : 'T.${result.columns[columnsToInclude.first].name.toUpperCase()} = S.${result.columns[columnsToInclude.first].name.toUpperCase()}';

          // Las Primary Keys y columnas usadas en el ON NUNCA se actualizan en SET
          final updateCols = columnsToInclude
              .where((i) {
                final colName = result.columns[i].name.toUpperCase();
                return !effectiveKeys.contains(colName) &&
                    !activePks.contains(colName);
              })
              .map(
                (i) =>
                    'T.${result.columns[i].name.toUpperCase()} = S.${result.columns[i].name.toUpperCase()}',
              )
              .join(', ');

          for (final row in result.rows) {
            final selectCols = columnsToInclude
                .map(
                  (i) =>
                      '${_formatSqlValue(row[i], result.columns[i].dataType)} AS ${result.columns[i].name.toUpperCase()}',
                )
                .join(', ');
            final insertCols = columnsToInclude
                .map((i) => result.columns[i].name.toUpperCase())
                .join(', ');
            final insertVals = columnsToInclude
                .map((i) => 'S.${result.columns[i].name.toUpperCase()}')
                .join(', ');

            buffer.writeln('MERGE INTO $tableName T');
            buffer.writeln('USING (SELECT $selectCols FROM DUAL) S');
            buffer.writeln('ON ($onClause)');
            if (updateCols.isNotEmpty) {
              buffer.writeln('WHEN MATCHED THEN');
              buffer.writeln('  UPDATE SET $updateCols');
            }
            buffer.writeln('WHEN NOT MATCHED THEN');
            buffer.writeln('  INSERT ($insertCols)');
            buffer.writeln('  VALUES ($insertVals);');
          }
          break;
      }

      buffer.writeln();
    }

    buffer.writeln('COMMIT;');
    return buffer.toString();
  }

  /// Formatea un valor para SQL según su tipo de dato, fragmentando en CLOB
  /// para evitar el error ORA-01704 cuando el texto excede los 3000 caracteres.
  static String _formatSqlValue(dynamic val, String? dataType) {
    if (val == null) return 'NULL';
    final dt = (dataType ?? '').toUpperCase();

    if (dt.contains('NUMBER') || dt.contains('INT') || dt.contains('FLOAT')) {
      return val.toString();
    }

    if (dt.contains('DATE') || dt.contains('TIMESTAMP')) {
      return formatSqlDateOrTimestamp(val, dataType: dt);
    }

    final isClob = dt.contains('CLOB');
    return formatSqlStringOrClob(val.toString(), isClob: isClob);
  }

  /// Formatea una cadena para SQL. Si es tipo CLOB o mide más de 3000 caracteres,
  /// la divide en trozos de hasta 3000 caracteres unidos por ` || ` con `TO_CLOB('...')`
  /// para evitar el error `ORA-01704: literal de cadena demasiado largo`.
  static String formatSqlStringOrClob(
    String str, {
    bool isClob = false,
    int chunkSize = 3000,
  }) {
    // Si la cadena excede el tamaño de fragmento, fragmentar con TO_CLOB('...')
    if (str.length > chunkSize) {
      final parts = <String>[];
      for (var i = 0; i < str.length; i += chunkSize) {
        final end = (i + chunkSize < str.length) ? i + chunkSize : str.length;
        final chunk = str.substring(i, end).replaceAll("'", "''");
        parts.add("TO_CLOB('$chunk')");
      }
      return parts.join(' || ');
    }

    final safe = str.replaceAll("'", "''");
    // Si es CLOB de <= 3000 caracteres, envolver con TO_CLOB('...')
    if (isClob) {
      return "TO_CLOB('$safe')";
    }

    // Literal estándar entre comillas simples
    return "'$safe'";
  }

  /// Normaliza valores de fecha/hora (incluyendo ISO 8601 con 'T', zonas horarias o milisegundos)
  /// y genera `TO_DATE` o `TO_TIMESTAMP` con formato explícito para evitar ORA-01861.
  static String formatSqlDateOrTimestamp(dynamic value, {String? dataType}) {
    if (value == null) return 'NULL';
    var s = value.toString().trim();
    if (s.isEmpty) return 'NULL';

    s = s.replaceFirst('T', ' ');
    final zIdx = s.indexOf('Z');
    if (zIdx != -1) s = s.substring(0, zIdx);
    final tzIdx = RegExp(r'[+-]\d{2}:\d{2}$').firstMatch(s)?.start;
    if (tzIdx != null) s = s.substring(0, tzIdx);

    final dotIdx = s.indexOf('.');
    var datePart = (dotIdx != -1 ? s.substring(0, dotIdx) : s).trim();
    if (datePart.isEmpty) return 'NULL';

    String dOnly;
    String tOnly;
    final parts = datePart
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NULL';
    } else if (parts.length == 1) {
      if (parts[0].contains(':')) {
        return 'NULL';
      }
      dOnly = parts[0];
      tOnly = '00:00:00';
    } else {
      if (parts[0].contains(':') && !parts[1].contains(':')) {
        tOnly = parts[0];
        dOnly = parts[1];
      } else {
        dOnly = parts[0];
        tOnly = parts[1];
      }
    }

    if (!dOnly.contains('-') && !dOnly.contains('/')) {
      return 'NULL';
    }

    final isSlash = dOnly.contains('/');
    final formatMask = isSlash ? 'DD/MM/YYYY' : 'YYYY-MM-DD';
    final dtUpper = (dataType ?? '').toUpperCase();

    if (dtUpper.contains('TIMESTAMP')) {
      final frac = (dotIdx != -1 ? s.substring(dotIdx + 1) : '')
          .padRight(6, '0')
          .substring(0, 6);
      return "TO_TIMESTAMP('$dOnly $tOnly.$frac', '$formatMask HH24:MI:SS.FF6')";
    }
    return "TO_DATE('$dOnly $tOnly', '$formatMask HH24:MI:SS')";
  }

  /// Construye un script de MERGE para cuando no se puede consultar la BD de Procedimientos.
  static String _buildFallbackDynamicMerge({
    required String cdProcedimiento,
    required int version,
    required String usuario,
  }) {
    return '''DECLARE
  v_texto CLOB;
BEGIN
  v_texto := 'BEGIN NULL; END;';

  MERGE INTO SIR.PROCEDIMIENTODINAMICO T
  USING DUAL ON (T.CD_PROCEDIMIENTO = '$cdProcedimiento')
  WHEN MATCHED THEN UPDATE SET
    T.DE_TEXTO         = v_texto,
    T.ST_PROCEDIMIENTO = '1',
    T.IN_CONFIGURACION = 'P',
    T.CD_USUARIO       = '$usuario',
    T.FE_MODIFICACION  = SYSDATE
  WHEN NOT MATCHED THEN INSERT (
    VERSION, CD_PROCEDIMIENTO, ST_PROCEDIMIENTO,
    DE_TEXTO, IN_CONFIGURACION, CD_USUARIO, FE_MODIFICACION
  ) VALUES (
    $version, '$cdProcedimiento', '1',
    v_texto, 'P', '$usuario', SYSDATE
  );
  COMMIT;
END;
/
''';
  }

  /// Construye el script SQL de auditoría con los INSERT INTO PASEAMBIENTESCRIPT
  /// correspondientes a los scripts generados en el pase.
  static String _buildPaseAmbienteScriptSql({
    required DeployTicket ticket,
    required List<String> scriptsGenerados,
    required DateTime now,
    required String usuarioPase,
    required String usuarioAutoriza,
  }) {
    final buffer = StringBuffer();
    final fechaPaseStr =
        '${formatDateYmd(now).substring(0, 4)}-${formatDateYmd(now).substring(4, 6)}-${formatDateYmd(now).substring(6, 8)} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final url = ticket.url?.trim().isNotEmpty == true ? ticket.url!.trim() : '';

    buffer.writeln(
      '-- =============================================================================',
    );
    buffer.writeln('-- Script de Auditoría de Pases de Ambientes');
    buffer.writeln(
      '-- Solicitud: ${ticket.numeroSolicitud} (${ticket.tipoSolicitud}) | Versión: ${ticket.version}',
    );
    buffer.writeln(
      '-- =============================================================================\n',
    );

    for (final scriptName in scriptsGenerados) {
      final safeUrl = url.replaceAll("'", "''");
      buffer.writeln(
        "INSERT INTO PASEAMBIENTESCRIPT (Version,NM_SCRIPT,FE_ACTU,FE_PASE,CD_USUARIO_AUTORIZADOR,CD_USUARIO_PASE,ST_PASE,TP_SOLICITUD,NU_SOLICITUD,TX_ERROR,ID_PROCESO,HR_EJECUCION,NU_APROBACION_AZURE_DEVOP) "
        "VALUES (${ticket.version},'$scriptName',NULL,TO_DATE('$fechaPaseStr','YYYY-MM-DD HH24:MI:SS'),'$usuarioAutoriza','$usuarioPase','1','${capitalize(ticket.tipoSolicitud)}','${ticket.numeroSolicitud}',NULL,NULL,NULL,'$safeUrl');",
      );
    }

    buffer.writeln('\nCOMMIT;');
    return buffer.toString();
  }
}
