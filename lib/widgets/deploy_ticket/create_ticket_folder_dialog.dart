import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/deploy_ticket.dart';
import '../../services/app_log.dart';
import '../../services/deploy_ticket_exporter_service.dart';
import '../app_toast.dart';
import '../floating_window.dart' show showFloatingDialog;

/// Clave de SharedPreferences para recordar el último directorio raíz seleccionado.
const String _kLastExportRootDirKey = 'deploy_ticket_last_export_root_dir';

/// Diálogo modal interactivo para configurar y crear la carpeta local de un ticket
/// de despliegue junto con sus archivos (`index.txt` y scripts SQL asociados).
class CreateTicketFolderDialog extends StatefulWidget {
  final DeployTicket ticket;
  final void Function([String? folderPathResult])? onClose;

  const CreateTicketFolderDialog({
    super.key,
    required this.ticket,
    this.onClose,
  });

  /// Muestra el modal utilizando [showFloatingDialog].
  /// Retorna la ruta absoluta del directorio creado si la operación fue exitosa, o null si se canceló.
  static Future<String?> show(
    BuildContext context, {
    required DeployTicket ticket,
  }) {
    return showFloatingDialog<String>(
      context,
      (ctx, close) => CreateTicketFolderDialog(ticket: ticket, onClose: close),
    );
  }

  @override
  State<CreateTicketFolderDialog> createState() => _CreateTicketFolderDialogState();
}

class _CreateTicketFolderDialogState extends State<CreateTicketFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _folderNameCtrl;
  late TextEditingController _rootDirCtrl;

  bool _loading = true;
  bool _creating = false;
  String? _createdFolderPath;
  List<ExportedDeployFile>? _createdFiles;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Nomenclatura sugerida: {numero de ticket azure o tipo de solicitud}_{numero de solicitud}
    _folderNameCtrl = TextEditingController(text: widget.ticket.suggestedFolderName);
    _rootDirCtrl = TextEditingController();

    _loadLastRootDir();
  }

  @override
  void dispose() {
    _folderNameCtrl.dispose();
    _rootDirCtrl.dispose();
    super.dispose();
  }

  void _closeDialog([String? result]) {
    if (widget.onClose != null) {
      widget.onClose!(result);
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _loadLastRootDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var lastDir = prefs.getString(_kLastExportRootDirKey) ?? '';

      // Si no hay preferencia guardada previa, intentar con la ruta del ticket si existe
      if (lastDir.isEmpty &&
          widget.ticket.rutaDirectorioLocal != null &&
          widget.ticket.rutaDirectorioLocal!.trim().isNotEmpty) {
        final ticketDir = Directory(widget.ticket.rutaDirectorioLocal!.trim());
        lastDir = ticketDir.parent.path;
      }

      if (mounted) {
        setState(() {
          _rootDirCtrl.text = lastDir;
          _loading = false;
        });
      }
    } catch (e) {
      AppLog.instance.warning(
        'No se pudo leer la última ruta de exportación de SharedPreferences: $e',
        source: 'CreateTicketFolderDialog',
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveLastRootDir(String rootDir) async {
    if (rootDir.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastExportRootDirKey, rootDir.trim());
    } catch (_) {}
  }

  Future<void> _pickDirectory() async {
    try {
      final current = _rootDirCtrl.text.trim();
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Selecciona el directorio raíz donde se creará la carpeta',
        initialDirectory: current.isNotEmpty ? current : null,
      );

      if (selected != null && selected.trim().isNotEmpty && mounted) {
        setState(() {
          _rootDirCtrl.text = selected.trim();
        });
        await _saveLastRootDir(selected.trim());
      }
    } catch (e) {
      AppToast.error('Error al seleccionar directorio: $e');
    }
  }

  Future<void> _pasteDirectoryFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty && mounted) {
        setState(() {
          _rootDirCtrl.text = text;
        });
        await _saveLastRootDir(text);
        AppToast.info('Ruta pegada desde el portapapeles');
      }
    } catch (_) {}
  }

  String get _computedTargetPath {
    final root = _rootDirCtrl.text.trim();
    final folder = _folderNameCtrl.text.trim();
    if (root.isEmpty) return folder.isNotEmpty ? folder : '';
    if (folder.isEmpty) return root;
    return '$root${Platform.pathSeparator}$folder';
  }

  Future<void> _createFolderAndFiles() async {
    if (!_formKey.currentState!.validate()) return;

    final rootDir = _rootDirCtrl.text.trim();
    final folderName = _folderNameCtrl.text.trim();

    setState(() {
      _creating = true;
      _errorMessage = null;
    });

    try {
      final service = DeployTicketExporterService.instance;
      final files = await service.crearDirectorioYArchivos(
        ticket: widget.ticket,
        rootDirectoryPath: rootDir,
        folderName: folderName,
      );

      await _saveLastRootDir(rootDir);

      final fullTarget = '$rootDir${Platform.pathSeparator}$folderName';

      if (mounted) {
        setState(() {
          _creating = false;
          _createdFolderPath = fullTarget;
          _createdFiles = files;
        });

        AppToast.success(
          'Carpeta y ${files.length} archivos generados con éxito',
        );
      }
    } catch (e) {
      AppLog.instance.error(
        'Error al crear directorio y archivos: $e',
        source: 'CreateTicketFolderDialog',
      );
      if (mounted) {
        setState(() {
          _creating = false;
          _errorMessage = e.toString();
        });
        AppToast.error('Error al crear directorio: $e');
      }
    }
  }

  Future<void> _openCreatedFolder() async {
    final folder = _createdFolderPath ?? _computedTargetPath;
    if (folder.isEmpty) return;

    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [folder]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [folder]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folder]);
      }
    } catch (e) {
      AppToast.error('No se pudo abrir el explorador de archivos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E222B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF333B4D) : const Color(0xFFD6DBE5);
    final inputBg = isDark ? const Color(0xFF161922) : const Color(0xFFF7F8FA);
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 620,
          constraints: const BoxConstraints(maxHeight: 680),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _loading
                ? const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cabecera
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF252B37) : const Color(0xFFF1F4F9),
                          border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.create_new_folder_rounded,
                                color: Colors.tealAccent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Crear Directorio y Archivos del Ticket',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.ticket.numeroSolicitud.isNotEmpty
                                        ? 'Pase #${widget.ticket.numeroSolicitud} — ${widget.ticket.tipoSolicitud}'
                                        : 'Ticket sin número asignado',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Cerrar',
                              onPressed: () => _closeDialog(_createdFolderPath),
                            ),
                          ],
                        ),
                      ),

                      // Contenido del formulario
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Nombre de la carpeta
                                const Text(
                                  'Nombre de la Carpeta',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Nomenclatura sugerida: {ticket azure o tipo solicitud}_{número solicitud}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _folderNameCtrl,
                                  enabled: !_creating && _createdFolderPath == null,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                                    suffixIcon: IconButton(
                                      tooltip: 'Restablecer nombre recomendado',
                                      icon: const Icon(Icons.restore_rounded, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _folderNameCtrl.text = widget.ticket.suggestedFolderName;
                                        });
                                      },
                                    ),
                                    filled: true,
                                    fillColor: inputBg,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Ingresa un nombre para la carpeta';
                                    }
                                    if (v.contains(RegExp(r'[\\/:*?"<>|]'))) {
                                      return 'El nombre no puede contener caracteres como \\ / : * ? " < > |';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 18),

                                // Directorio raíz donde se guardará
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Directorio Raíz de Destino',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: _pasteDirectoryFromClipboard,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.content_paste_rounded,
                                              size: 13,
                                              color: primaryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pegar ruta',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: primaryColor,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Se recordará automáticamente esta carpeta para próximas operaciones.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _rootDirCtrl,
                                        enabled: !_creating && _createdFolderPath == null,
                                        onChanged: (val) {
                                          setState(() {});
                                          _saveLastRootDir(val);
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'C:\\Pases o /home/...',
                                          prefixIcon: const Icon(Icons.drive_file_move_outlined, size: 18),
                                          filled: true,
                                          fillColor: inputBg,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 11,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: borderColor),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: borderColor),
                                          ),
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Selecciona o pega el directorio raíz de destino';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                                      label: const Text('Examinar', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: (!_creating && _createdFolderPath == null)
                                          ? _pickDirectory
                                          : null,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Previsualización de la ruta completa
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF14171E)
                                        : const Color(0xFFF3F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: borderColor.withValues(alpha: 0.6),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.route_rounded,
                                            size: 14,
                                            color: isDark ? Colors.cyanAccent : Colors.teal,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Ruta resultante:',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        _computedTargetPath.isNotEmpty
                                            ? _computedTargetPath
                                            : '(Especifica el directorio raíz y el nombre de la carpeta)',
                                        style: TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 11.5,
                                          color: _computedTargetPath.isNotEmpty
                                              ? (isDark ? Colors.cyanAccent : Colors.teal.shade800)
                                              : (isDark ? Colors.white38 : Colors.black38),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Archivos a generar
                                _buildSummarySection(isDark, borderColor),

                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                if (_createdFolderPath != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '¡Directorio y ${_createdFiles?.length ?? 0} archivos generados con éxito!',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                  color: Colors.greenAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _createdFolderPath!,
                                          style: const TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Barra inferior de botones
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF222732) : const Color(0xFFF7F8FA),
                          border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_createdFolderPath != null) ...[
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open_rounded, size: 16),
                                label: const Text('Abrir Carpeta', style: TextStyle(fontSize: 12)),
                                onPressed: _openCreatedFolder,
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => _closeDialog(_createdFolderPath),
                                child: const Text('Listo', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ),
                            ] else ...[
                              TextButton(
                                onPressed: _creating ? null : () => _closeDialog(),
                                child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                icon: _creating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.check_rounded, size: 16),
                                label: Text(
                                  _creating ? 'Creando...' : 'Crear Directorio y Archivos',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: _creating ? null : _createFolderAndFiles,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection(bool isDark, Color borderColor) {
    final t = widget.ticket;
    final totalScripts = t.sql.length +
        t.reverseSql.length +
        t.bloqueLogico.length +
        t.reglasNegocio.length +
        t.paquetes.length +
        t.funciones.length +
        t.triggers.length +
        t.objetos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1F2A) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 6),
              const Text(
                'Archivos que se generarán:',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${totalScripts + 1} archivos en total',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildBadge('index.txt', Colors.blueAccent),
              if (t.sql.isNotEmpty) _buildBadge('${t.sql.length} SQL', Colors.indigoAccent),
              if (t.reverseSql.isNotEmpty) _buildBadge('${t.reverseSql.length} RSQL', Colors.purpleAccent),
              if (t.bloqueLogico.isNotEmpty) _buildBadge('${t.bloqueLogico.length} BLK', Colors.orangeAccent),
              if (t.reglasNegocio.isNotEmpty) _buildBadge('${t.reglasNegocio.length} RN', Colors.greenAccent),
              if (t.paquetes.isNotEmpty) _buildBadge('${t.paquetes.length} PCK', Colors.cyanAccent),
              if (t.funciones.isNotEmpty) _buildBadge('${t.funciones.length} FUN', Colors.tealAccent),
              if (t.triggers.isNotEmpty) _buildBadge('${t.triggers.length} TRG', Colors.redAccent),
              if (t.objetos.isNotEmpty) _buildBadge('${t.objetos.length} OBJ', Colors.amberAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
