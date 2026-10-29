import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/deploy_ticket.dart';
import '../../providers/procedimientos_provider.dart';
import '../../services/app_log.dart';
import '../../services/deploy_ticket_service.dart';
import '../../services/git_repository_config_service.dart';
import '../../services/git_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;
import 'git_terminal_console.dart';

/// Diálogo interactivo para crear una rama Hotfix y enlazarla con el ticket y el repositorio.
class CreateHotfixBranchDialog extends StatefulWidget {
  final DeployTicket ticket;
  final void Function([DeployTicket? result])? onClose;

  const CreateHotfixBranchDialog({
    super.key,
    required this.ticket,
    this.onClose,
  });

  /// Muestra el diálogo usando `showFloatingDialog` para que quede en el overlay superior.
  static Future<DeployTicket?> show(
    BuildContext context, {
    required DeployTicket ticket,
  }) {
    return showFloatingDialog<DeployTicket>(
      context,
      (ctx, close) => CreateHotfixBranchDialog(ticket: ticket, onClose: close),
    );
  }

  @override
  State<CreateHotfixBranchDialog> createState() =>
      _CreateHotfixBranchDialogState();
}

class _CreateHotfixBranchDialogState extends State<CreateHotfixBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _branchCtrl;
  late TextEditingController _repoCtrl;
  late TextEditingController _localCtrl;

  bool _loading = true;
  bool _submitting = false;
  bool _completed = false;
  DeployTicket? _completedTicket;
  String? _statusMessage;
  String? _errorMessage;

  final List<GitCommandLog> _commandLogs = [];

  @override
  void initState() {
    super.initState();
    final defaultBranch = GitService.formatHotfixBranchName(
      numeroSolicitud: widget.ticket.numeroSolicitud,
    );
    _branchCtrl = TextEditingController(text: defaultBranch);
    _repoCtrl = TextEditingController();
    _localCtrl = TextEditingController();

    _loadConfig();
  }

  @override
  void dispose() {
    _branchCtrl.dispose();
    _repoCtrl.dispose();
    _localCtrl.dispose();
    super.dispose();
  }

  void _closeDialog([DeployTicket? result]) {
    if (widget.onClose != null) {
      widget.onClose!(result);
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _loadConfig() async {
    final config = await GitRepositoryConfigService().getConfig();
    if (!mounted) return;

    final repoUrl = widget.ticket.rutaRepositorio?.isNotEmpty == true
        ? widget.ticket.rutaRepositorio!
        : config.rutaRepositorio;

    final localPath = widget.ticket.rutaDirectorioLocal?.isNotEmpty == true
        ? widget.ticket.rutaDirectorioLocal!
        : config.rutaDirectorioLocal;

    setState(() {
      _repoCtrl.text = repoUrl;
      _localCtrl.text = localPath;
      _loading = false;
    });
  }

  Future<void> _pickLocalDirectory() async {
    final initial = _localCtrl.text.isNotEmpty ? _localCtrl.text : null;
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle:
          'Seleccionar carpeta local donde se encuentra el proyecto clonado',
      initialDirectory: initial,
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() {
        _localCtrl.text = selected.trim();
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final branchName = _branchCtrl.text.trim();
    final repoUrl = _repoCtrl.text.trim();
    final localPath = _localCtrl.text.trim();

    if (!Directory(localPath).existsSync()) {
      AppToast.error('La carpeta local del proyecto no existe en disco');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _statusMessage = 'Verificando repositorio Git local...';
      _commandLogs.clear();
    });

    try {
      final git = GitService(
        workingDirectory: localPath,
        onCommandLog: (log) {
          if (mounted) {
            setState(() {
              _commandLogs.add(log);
            });
          }
        },
      );
      final isRepo = await git.isGitRepository();
      if (!isRepo) {
        throw Exception(
          'La carpeta local especificada no contiene un repositorio Git inicializado (.git).',
        );
      }

      final currentConfig = await GitRepositoryConfigService().getConfig();

      // Sincronizar URL remota si fue suministrada
      if (repoUrl.isNotEmpty) {
        setState(() => _statusMessage = 'Sincronizando remoto origin...');
        final syncRes = await git.syncRemoteOrigin(
          repoUrl,
          description: 'Sincronizando URL remota origin ($repoUrl)',
        );
        if (!syncRes.isSuccess) {
          throw Exception(
            'Error al sincronizar remoto origin ($repoUrl): ${syncRes.stderr}',
          );
        }
      }

      // Paso 1 crítico: Posicionarse en la rama base (master/main)
      final baseBranch = await git.resolveDefaultBaseBranch();
      setState(
        () => _statusMessage = 'Posicionando en rama base $baseBranch...',
      );
      final checkoutBase = await git.checkout(
        baseBranch,
        description: 'Cambiando a rama base $baseBranch para sincronización',
      );
      if (!checkoutBase.isSuccess) {
        throw Exception(
          'Error al cambiar a la rama base $baseBranch: ${checkoutBase.stderr}',
        );
      }

      // Paso 2 crítico: git pull de master/main con autorización configurada
      // REGLA ESTRICTA: Hasta que master no esté actualizado, no avanzar a crear o comprobar rama hotfix.
      setState(
        () => _statusMessage =
            'Actualizando $baseBranch desde el repositorio remoto (git pull)...',
      );
      final pullRes = await git.pull(
        branch: baseBranch,
        remoteUrl: repoUrl.isNotEmpty ? repoUrl : currentConfig.rutaRepositorio,
        authType: currentConfig.authType,
        token: currentConfig.personalAccessToken,
        description:
            'Realizando actualización a la rama $baseBranch desde repositorio remoto (git pull)',
      );
      if (!pullRes.isSuccess) {
        throw Exception(
          'No se pudo actualizar la rama base local ($baseBranch) desde el repositorio remoto.\n'
          'Detalle Git: ${pullRes.output.isNotEmpty ? pullRes.output : pullRes.stderr}\n\n'
          'La operación se canceló para no bifurcar desde una base desactualizada.',
        );
      }

      // Paso 3: Solo habiendo actualizado la base con éxito, comprobar / crear rama hotfix
      final exists = await git.branchExists(branchName);
      if (exists) {
        setState(
          () => _statusMessage = 'Cambiando a rama existente $branchName...',
        );
        final checkoutRes = await git.checkout(
          branchName,
          description: 'Cambiando a rama hotfix existente $branchName',
        );
        if (!checkoutRes.isSuccess) {
          throw Exception(
            'Error al cambiar a la rama existente $branchName: ${checkoutRes.stderr}',
          );
        }
      } else {
        // Crear y posicionarse en la nueva rama hotfix desde el master/main actualizado
        setState(
          () => _statusMessage =
              'Creando rama hotfix $branchName desde $baseBranch...',
        );
        final createRes = await git.createAndCheckoutBranch(
          branchName,
          startPoint: baseBranch,
          description:
              'Creando y posicionando en nueva rama hotfix $branchName desde $baseBranch',
        );
        if (!createRes.isSuccess) {
          throw Exception(
            'Error al crear rama $branchName: ${createRes.stderr}',
          );
        }
      }

      // Paso 4: Guardar en configuración global
      await GitRepositoryConfigService().saveConfig(
        rutaRepositorio: repoUrl.isNotEmpty
            ? repoUrl
            : currentConfig.rutaRepositorio,
        rutaDirectorioLocal: localPath,
        authType: currentConfig.authType,
        personalAccessToken: currentConfig.personalAccessToken,
      );

      // Paso 5: Determinar usuario activo y persistir ticket en backend
      final activeUser =
          (procedimientosProvider.cdUsuario.trim().isNotEmpty
                  ? procedimientosProvider.cdUsuario.trim()
                  : DeployTicketService.currentUser)
              .toUpperCase();

      setState(
        () => _statusMessage = 'Enlazando hotfix al ticket en el servidor...',
      );
      final updatedTicket = widget.ticket.copyWith(
        rutaRepositorio: repoUrl,
        rutaDirectorioLocal: localPath,
        usuarioActualiza: activeUser,
      );

      final persistedTicket = await DeployTicketService.instance.save(
        updatedTicket,
      );

      if (!mounted) return;
      AppToast.success('Rama hotfix $branchName enlazada y activada con éxito');
      setState(() {
        _submitting = false;
        _completed = true;
        _completedTicket = persistedTicket;
        _statusMessage =
            '¡Rama hotfix $branchName creada y enlazada correctamente!';
      });
    } catch (e) {
      AppLog.instance.error(
        'Error al crear hotfix: $e',
        source: 'HotfixDialog',
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF1E1F25) : Colors.white;
    final headerBg = isDark ? const Color(0xFF26262B) : const Color(0xFFF6F8FA);
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;
    final inputBg = isDark ? const Color(0xFF1B1C22) : Colors.white;
    final cardBg = isDark ? const Color(0xFF252731) : const Color(0xFFF8FAFC);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 590,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? borderColor
                  : cs.outlineVariant.withValues(alpha: 0.7),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.22),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado ConstellationHeader con gradiente ámbar/dorado
              ConstellationHeader(
                height: 64,
                onDark: true,
                lineColor: Colors.white.withValues(alpha: 0.25),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFD97706), // Amber-600
                      Color.lerp(
                            const Color(0xFFB45309), // Amber-700
                            isDark ? Colors.black : const Color(0xFF78350F),
                            0.35,
                          ) ??
                          const Color(0xFFB45309),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.6,
                        ),
                      ),
                      child: const Icon(
                        Icons.alt_route_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Crear / Enlazar Rama Hotfix',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ticket #${widget.ticket.numeroSolicitud} — Sincroniza local con remoto y crea hotfix',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Colors.white70,
                      hoverColor: Colors.white24,
                      tooltip: 'Cerrar',
                      onPressed: _submitting
                          ? null
                          : () => _closeDialog(_completedTicket),
                    ),
                  ],
                ),
              ),

              // Contenido
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _loading
                      ? const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tarjeta informativa del flujo
                              if (_completed)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.green.shade600.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '¡Rama Hotfix Creada y Enlazada Exitosamente!',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                                color: Colors.green,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'La base master/main fue sincronizada y la rama hotfix está activa en tu repositorio local. Puedes revisar el log de comandos abajo y presionar "Listo" para continuar.',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark
                                                    ? Colors.white70
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: Colors.amber.shade700,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Se actualizará la rama base local (master/main) desde el remoto mediante pull y se creará la rama aislada para este ticket sin afectar master.',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            height: 1.35,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                              // Campo: Rama Hotfix
                              Text(
                                'Nombre de la Rama Hotfix',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Rama de trabajo aislada (la rama hotfix ya se asume actualizada)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _branchCtrl,
                                enabled: !_submitting,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Consolas, monospace',
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  prefixIcon: const Icon(
                                    Icons.alt_route_rounded,
                                    size: 20,
                                  ),
                                  hintText: 'hf_12345_261027',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El nombre de la rama es obligatorio';
                                  }
                                  if (value.contains(' ')) {
                                    return 'El nombre de la rama no puede contener espacios';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              // Campo: Directorio Local de Scripts (rutaDirectorioLocal)
                              Text(
                                'Directorio Local en Disco (rutaDirectorioLocal)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Carpeta en tu PC donde está el repositorio clonado',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _localCtrl,
                                enabled: !_submitting,
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  prefixIcon: const Icon(
                                    Icons.folder_open_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.drive_folder_upload_rounded,
                                    ),
                                    tooltip: 'Seleccionar carpeta local...',
                                    onPressed: _submitting
                                        ? null
                                        : _pickLocalDirectory,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El directorio local es requerido';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              // Campo: URL Remota (rutaRepositorio)
                              Text(
                                'Enlace Remoto al Servidor (rutaRepositorio)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'URL del servidor Git para el push (Azure DevOps, GitHub, GitLab)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _repoCtrl,
                                enabled: !_submitting,
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  prefixIcon: const Icon(
                                    Icons.cloud_outlined,
                                    size: 20,
                                  ),
                                  hintText:
                                      'https://dev.azure.com/... o git@...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El enlace remoto es requerido';
                                  }
                                  return null;
                                },
                              ),

                              if (_statusMessage != null) ...[
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    if (_submitting) ...[
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ] else if (_completed) ...[
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        _statusMessage!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _completed
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: _completed
                                              ? Colors.green
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              if (_errorMessage != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade900.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.shade700.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: Colors.red.shade400,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: Colors.red.shade300,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Mini-terminal de comandos Git enviados
                              if (_commandLogs.isNotEmpty || _submitting) ...[
                                const SizedBox(height: 16),
                                GitTerminalConsole(
                                  logs: _commandLogs,
                                  onClear: _submitting
                                      ? null
                                      : () => setState(
                                          () => _commandLogs.clear(),
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(
                    top: BorderSide(color: borderColor, width: 0.8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_completed) ...[
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _submitting
                            ? null
                            : () => _closeDialog(null),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Crear / Activar Rama'),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _closeDialog(_completedTicket),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Listo'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
