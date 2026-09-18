import 'dart:io';

import '../models/bulk_backup_item.dart';
import '../models/procedimiento.dart';
import 'app_log.dart';
import 'backup_service.dart';

typedef BulkBackupProgress =
    void Function(int completed, int total, String name);

typedef BulkBackupResult = ({
  String directory,
  List<String> written,
  List<({String name, String error})> failures,
});

abstract final class BulkBackupService {
  static String safeFileName(String value) {
    final normalized = _removeAccents(
      value.trim(),
    ).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return normalized.isEmpty ? 'object' : normalized;
  }

  static String _removeAccents(String value) => value
      .replaceAllMapped(
        RegExp('[ÀÁÂÃÄÅàáâãäå]'),
        (match) => switch (match.group(0)) {
          'À' || 'Á' || 'Â' || 'Ã' || 'Ä' || 'Å' => 'A',
          _ => 'a',
        },
      )
      .replaceAllMapped(
        RegExp('[ÈÉÊËèéêë]'),
        (match) => switch (match.group(0)) {
          'È' || 'É' || 'Ê' || 'Ë' => 'E',
          _ => 'e',
        },
      )
      .replaceAllMapped(
        RegExp('[ÌÍÎÏìíîï]'),
        (match) => switch (match.group(0)) {
          'Ì' || 'Í' || 'Î' || 'Ï' => 'I',
          _ => 'i',
        },
      )
      .replaceAllMapped(
        RegExp('[ÒÓÔÕÖØòóôõöø]'),
        (match) => switch (match.group(0)) {
          'Ò' || 'Ó' || 'Ô' || 'Õ' || 'Ö' || 'Ø' => 'O',
          _ => 'o',
        },
      )
      .replaceAllMapped(
        RegExp('[ÙÚÛÜùúûü]'),
        (match) => switch (match.group(0)) {
          'Ù' || 'Ú' || 'Û' || 'Ü' => 'U',
          _ => 'u',
        },
      )
      .replaceAll('Ñ', 'N')
      .replaceAll('ñ', 'n');

  static String categoryFor(BulkBackupItem item) => item.category;

  static String buildDynamicScript(
    Procedimiento procedure,
    String ambiente,
    String cdUsuario,
  ) => BackupService.buildDynamicScript(procedure, ambiente, cdUsuario);

  static String buildSchemaScript({
    required BulkBackupItem item,
    required String ambiente,
    required String spec,
    String? body,
    String? tableComments,
    String? tableGrants,
    List<({String grantee, String privilege, bool grantable, String grantor})>
        grants =
        const [],
    List<({String synonymName, bool isPublic, String owner})> synonyms =
        const [],
    BulkBackupConfig config = const BulkBackupConfig(),
  }) {
    final parts = <String>[];
    if (config.includeSpec && spec.trim().isNotEmpty) {
      parts.add('${spec.trim()}\n/');
    }
    if (config.includeBody && body != null && body.trim().isNotEmpty) {
      parts.add('${body.trim()}\n/');
    }
    if (config.includeTableComments &&
        tableComments != null &&
        tableComments.trim().isNotEmpty) {
      parts.add('${tableComments.trim()}\n/');
    }
    if (config.includeGrants) {
      if (tableGrants != null && tableGrants.trim().isNotEmpty) {
        parts.add('${tableGrants.trim()}\n/');
      } else {
        for (final grant in grants) {
          final grantable = grant.grantable ? ' WITH GRANT OPTION' : '';
          parts.add(
            'GRANT ${grant.privilege} ON ${item.owner.isEmpty ? '' : '${item.owner}.'}${item.name} TO ${grant.grantee}$grantable;\n/',
          );
        }
      }
    }
    if (config.includeSynonyms) {
      for (final synonym in synonyms.where((s) => s.isPublic)) {
        final owner = synonym.owner.isEmpty ? item.owner : synonym.owner;
        final ref = owner.isEmpty ? item.name : '$owner.${item.name}';
        parts.add(
          'CREATE OR REPLACE PUBLIC SYNONYM ${synonym.synonymName} FOR $ref;\n/',
        );
      }
    }
    return BackupService.buildSchemaScript(
      objectName: item.name,
      objectType: item.type,
      ambiente: ambiente,
      source: parts.join('\n\n'),
    );
  }

  static Future<BulkBackupResult> writeAll({
    required Directory directory,
    required String ambiente,
    required List<BulkBackupItem> items,
    required Map<String, String> scripts,
    BulkBackupProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final written = <String>[];
    final failures = <({String name, String error})>[];
    await directory.create(recursive: true);

    for (var index = 0; index < items.length; index++) {
      if (isCancelled?.call() ?? false) break;
      final item = items[index];
      onProgress?.call(index, items.length, item.name);
      try {
        final script = scripts[item.id];
        if (script == null) {
          throw StateError('No se generó el script');
        }
        final targetDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}${item.category}',
        );
        await targetDirectory.create(recursive: true);
        final file = File(
          '${targetDirectory.path}${Platform.pathSeparator}${safeFileName(item.name)}_${item.type.toLowerCase()}.sql',
        );
        await file.writeAsString(script, flush: true);
        written.add(file.path);
        AppLog.instance.transaction(
          'Backup ${item.name} (${item.type})',
          source: 'BulkBackup',
          datos: {'Ambiente': ambiente, 'Archivo': file.path},
        );
      } catch (error) {
        failures.add((name: item.name, error: error.toString()));
      }
      onProgress?.call(index + 1, items.length, item.name);
    }

    return (directory: directory.path, written: written, failures: failures);
  }
}
