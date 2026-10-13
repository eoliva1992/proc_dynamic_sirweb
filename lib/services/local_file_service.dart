import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../widgets/app_toast.dart';
import 'app_log.dart';
import 'backup_service.dart';

/// Servicio para abrir y guardar archivos locales en disco (.sql, .txt, etc.).
abstract final class LocalFileService {
  /// Abre un archivo local y retorna su ruta y contenido, o `null` si se cancela.
  static Future<({String path, String content})?> openFile({
    String dialogTitle = 'Abrir archivo',
    List<String> allowedExtensions = const ['sql', 'txt', 'pls', 'pkb', 'pks'],
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      final path = result?.files.single.path;
      if (path == null) return null;
      final file = File(path);
      final content = await file.readAsString();
      return (path: path, content: content);
    } on IOException catch (e) {
      AppToast.error('No se pudo leer el archivo: $e');
      return null;
    } catch (e) {
      AppToast.error('Error al abrir archivo: $e');
      return null;
    }
  }

  /// Guarda contenido en [currentPath] si existe y `saveAs` es false.
  /// Si no hay ruta o `saveAs` es true, muestra diálogo para elegir ubicación.
  /// Retorna la ruta donde se guardó, o `null` si se canceló.
  static Future<String?> saveFile({
    required String content,
    String? currentPath,
    bool saveAs = false,
    String defaultFileName = 'script.sql',
    String dialogTitle = 'Guardar archivo',
    List<String> allowedExtensions = const ['sql', 'txt', 'pls', 'pkb', 'pks'],
  }) async {
    try {
      final isNewOrChosenPath =
          saveAs || currentPath == null || currentPath.isEmpty;
      String? targetPath = currentPath;
      if (isNewOrChosenPath) {
        final initialName = (currentPath != null && currentPath.isNotEmpty)
            ? Uri.file(currentPath).pathSegments.last
            : defaultFileName;

        targetPath = await FilePicker.saveFile(
          dialogTitle: dialogTitle,
          fileName: initialName,
          type: FileType.custom,
          allowedExtensions: allowedExtensions,
        );
      }

      if (targetPath == null) return null;

      final file = File(targetPath);
      await file.writeAsString(content, flush: true);

      AppLog.instance.info(
        'Archivo guardado localmente: $targetPath',
        source: 'LocalFile',
      );

      final fileName = Uri.file(targetPath).pathSegments.last;
      if (isNewOrChosenPath) {
        AppToast.successWithAction(
          'Guardado en disco: $fileName',
          detail: targetPath,
          actionLabel: 'Abrir ubicación',
          onAction: () =>
              unawaited(BackupService.revealInExplorer(targetPath!)),
          duration: const Duration(seconds: 5),
        );
      } else {
        AppToast.success(
          'Guardado en disco: $fileName',
          duration: const Duration(seconds: 2),
        );
      }
      return targetPath;
    } on IOException catch (e) {
      AppToast.error('No se pudo guardar el archivo en disco: $e');
      return null;
    } catch (e) {
      AppToast.error('Error al guardar archivo: $e');
      return null;
    }
  }

  /// Abre la ubicación del archivo o carpeta en el explorador de archivos del sistema.
  static Future<bool> revealInExplorer(String path) =>
      BackupService.revealInExplorer(path);
}
