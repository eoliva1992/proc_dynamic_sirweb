import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/deploy_ticket.dart';
import '../../services/deploy_ticket_exporter_service.dart';
import '../app_toast.dart';
import '../floating_window.dart' show showFloatingDialog;

/// Diálogo modal interactivo para exportar todos los artefactos de un Pase a Producción.
///
/// Permite al usuario seleccionar un directorio destino, supervisar el progreso en tiempo real
/// y abrir la carpeta generada una vez finalizado el proceso.
class DeployTicketExportProgressDialog extends StatefulWidget {
  final DeployTicket ticket;
  final void Function([List<ExportedDeployFile>? result])? onClose;

  const DeployTicketExportProgressDialog({
    super.key,
    required this.ticket,
    this.onClose,
  });

  /// Muestra el modal de exportación para un ticket específico.
  /// Se monta usando `showFloatingDialog` para asegurar que quede por encima de
  /// las ventanas flotantes en el sistema de ventanas de la aplicación.
  static Future<List<ExportedDeployFile>?> show(
    BuildContext context, {
    required DeployTicket ticket,
  }) {
    return showFloatingDialog<List<ExportedDeployFile>>(
      context,
      (ctx, close) =>
          DeployTicketExportProgressDialog(ticket: ticket, onClose: close),
    );
  }

  @override
  State<DeployTicketExportProgressDialog> createState() =>
      _DeployTicketExportProgressDialogState();
}

class _DeployTicketExportProgressDialogState
    extends State<DeployTicketExportProgressDialog> {
  bool _isExporting = false;
  String _currentStep = 'Esperando selección de directorio...';
  double _progress = 0.0;
  String? _targetDirectory;
  List<ExportedDeployFile>? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Iniciar automáticamente la solicitud del directorio después de construir la UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectFolderAndExport();
    });
  }

  void _closeDialog([List<ExportedDeployFile>? result]) {
    if (widget.onClose != null) {
      widget.onClose!(result);
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _selectFolderAndExport() async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle:
            'Selecciona la carpeta donde guardar los artefactos del pase',
      );

      if (selectedPath == null || selectedPath.trim().isEmpty) {
        if (mounted && _result == null) {
          _closeDialog();
        }
        return;
      }

      setState(() {
        _targetDirectory = selectedPath;
        _isExporting = true;
        _errorMessage = null;
        _progress = 0.05;
        _currentStep = 'Iniciando exportación en $selectedPath...';
      });

      final service = DeployTicketExporterService.instance;
      final result = await service.exportarTicket(
        ticket: widget.ticket,
        targetDirectoryPath: selectedPath,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _currentStep = progress.mensaje;
              _progress = progress.porcentaje;
            });
          }
        },
      );

      if (mounted) {
        // La carpeta final PaseScriptAmbiente{yyyymmdd} donde se guardaron los archivos
        final finalFolder = result.isNotEmpty
            ? File(result.first.rutaCompleta).parent.path
            : selectedPath;

        setState(() {
          _targetDirectory = finalFolder;
          _isExporting = false;
          _result = result;
          _progress = 1.0;
          _currentStep = '¡Exportación completada con éxito!';
        });

        AppToast.success(
          'Pase exportado con éxito (${result.length} archivos generados)',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = e.toString();
          _currentStep = 'Ocurrió un error al exportar';
        });
        AppToast.error('Error al exportar pase: $e');
      }
    }
  }

  void _openTargetFolder() {
    if (_targetDirectory != null) {
      try {
        if (Platform.isWindows) {
          Process.run('explorer.exe', [_targetDirectory!]);
        } else if (Platform.isMacOS) {
          Process.run('open', [_targetDirectory!]);
        } else if (Platform.isLinux) {
          Process.run('xdg-open', [_targetDirectory!]);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.drive_folder_upload_rounded,
                      color: cs.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exportar Pase de Producción',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Ticket: ${widget.ticket.numeroSolicitud.isEmpty ? "Sin N°" : widget.ticket.numeroSolicitud} '
                          '| BD: ${widget.ticket.database ?? "Desa"} '
                          '| Versión: ${widget.ticket.version}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isExporting)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => _closeDialog(_result),
                      tooltip: 'Cerrar',
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),

              // Progress status & indicator
              if (_isExporting) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentStep,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(_progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Generando scripts con nomenclatura oficial, extrayendo reglas de negocio, '
                  'paquetes, funciones, RSQL y construyendo el Excel oficial y script de auditoría...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ] else if (_result != null) ...[
                // Success state
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Archivos generados correctamente',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Carpeta: ${_targetDirectory ?? ""}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Summary counts
                Row(
                  children: [
                    _buildSummaryBadge(
                      'Scripts',
                      '${(_result!.length - 2).clamp(0, 9999)}',
                      Icons.code_rounded,
                      Colors.blue,
                      isDark,
                    ),
                    const SizedBox(width: 10),
                    _buildSummaryBadge(
                      'Planilla XLSX',
                      '1',
                      Icons.table_chart_rounded,
                      Colors.green.shade700,
                      isDark,
                    ),
                    const SizedBox(width: 10),
                    _buildSummaryBadge(
                      'Auditoría SQL',
                      '1',
                      Icons.playlist_add_check_circle_rounded,
                      Colors.amber.shade800,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // File list preview
                const Text(
                  'Archivos creados:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF161619)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _result!.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final file = _result![index];
                        final filename = file.nombreArchivo;
                        final isExcel = filename.endsWith('.xlsx');
                        final isScriptAuditoria = filename.startsWith(
                          'pase_script_',
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isExcel
                                    ? Icons.table_chart_rounded
                                    : isScriptAuditoria
                                    ? Icons.verified_rounded
                                    : Icons.description_outlined,
                                size: 16,
                                color: isExcel
                                    ? Colors.green
                                    : isScriptAuditoria
                                    ? Colors.amber.shade700
                                    : cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  filename,
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 11.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                // Error state
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Error durante la exportación',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.red.shade200
                                    : Colors.red.shade900,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ] else ...[
                // Idle state waiting for folder
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 48,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Selecciona una carpeta para iniciar la exportación',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _selectFolderAndExport,
                          icon: const Icon(Icons.folder_rounded, size: 18),
                          label: const Text('Elegir Carpeta Destino'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),
              // Footer Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_result != null) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Abrir Carpeta'),
                      onPressed: _openTargetFolder,
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Listo'),
                      onPressed: () => _closeDialog(_result),
                    ),
                  ] else if (_errorMessage != null) ...[
                    OutlinedButton(
                      child: const Text('Cerrar'),
                      onPressed: () => _closeDialog(null),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reintentar'),
                      onPressed: _selectFolderAndExport,
                    ),
                  ] else if (!_isExporting) ...[
                    TextButton(
                      child: const Text('Cancelar'),
                      onPressed: () => _closeDialog(null),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBadge(
    String label,
    String count,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
