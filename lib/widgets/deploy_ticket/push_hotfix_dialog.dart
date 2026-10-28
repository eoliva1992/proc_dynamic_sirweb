import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/deploy_ticket.dart';
import '../../providers/procedimientos_provider.dart';
import '../../services/app_log.dart';
import '../../services/deploy_ticket_exporter_service.dart';
import '../../services/deploy_ticket_service.dart';
import '../../services/git_repository_config_service.dart';
import '../../services/git_service.dart';
import '../app_toast.dart';
import '../constellation_background.dart';
import '../floating_window.dart' show showFloatingDialog;

/// Diálogo interactivo para:
/// 1. Generar los scripts SQL directamente en `rutaDirectorioLocal` (sin `.xlsx` y sin `paseambientescript`).
/// 2. Confirmar commit y push de la rama hotfix al repositorio remoto con autorización.
/// 3. Actualizar el ticket en el backend guardando el enlace/referencia del hotfix.
class PushHotfixDialog extends StatefulWidget {
  final DeployTicket ticket;
  final void Function([DeployTicket? result])? onClose;

  const PushHotfixDialog({super.key, required this.ticket, this.onClose});

  /// Muestra el modal usando `showFloatingDialog` para asegurar que quede por encima
  /// de la ventana flotante de tickets.
  static Future<DeployTicket?> show(
    BuildContext context, {
    required DeployTicket ticket,
  }) {
    return showFloatingDialog<DeployTicket>(
      context,
      (ctx, close) => PushHotfixDialog(ticket: ticket, onClose: close),
    );
  }

  @override
  State<PushHotfixDialog> createState() => _PushHotfixDialogState();
}

class _PushHotfixDialogState extends State<PushHotfixDialog> {
  late TextEditingController _commitMsgCtrl;
  String _currentBranch = '';
  String _remoteUrl = '';
  String _localPath = '';
  GitAuthType _authType = GitAuthType.token;
  String _token = '';

  bool _loading = true;
  bool _executing = false;
  String _stepStatus = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final defaultCommit =
        'hotfix: pase #${widget.ticket.numeroSolicitud} (${widget.ticket.tipoSolicitud})';
    _commitMsgCtrl = TextEditingController(text: defaultCommit);
    _initContext();
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  void _closeDialog([DeployTicket? result]) {
    if (widget.onClose != null) {
      widget.onClose!(result);
    } else {
      Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _initContext() async {
    final config = await GitRepositoryConfigService().getConfig();

    final remote = widget.ticket.rutaRepositorio?.isNotEmpty == true
        ? widget.ticket.rutaRepositorio!
        : config.rutaRepositorio;

    final local = widget.ticket.rutaDirectorioLocal?.isNotEmpty == true
        ? widget.ticket.rutaDirectorioLocal!
        : config.rutaDirectorioLocal;

    String branch = '';
    if (local.isNotEmpty && Directory(local).existsSync()) {
      final git = GitService(workingDirectory: local);
      branch = (await git.getCurrentBranch()) ?? '';
    }

    if (branch.isEmpty) {
      branch = GitService.formatHotfixBranchName(
        numeroSolicitud: widget.ticket.numeroSolicitud,
      );
    }

    if (!mounted) return;
    setState(() {
      _remoteUrl = remote;
      _localPath = local;
      _currentBranch = branch;
      _authType = config.authType;
      _token = config.personalAccessToken;
      _loading = false;
    });
  }

  Future<void> _executeGenerateAndPush() async {
    final commitMsg = _commitMsgCtrl.text.trim();
    if (commitMsg.isEmpty) {
      AppToast.error('El mensaje de commit es obligatorio');
      return;
    }

    if (_localPath.isEmpty || !Directory(_localPath).existsSync()) {
      AppToast.error(
        'La carpeta local del proyecto no está configurada o no existe en disco',
      );
      return;
    }

    if (_remoteUrl.isEmpty) {
      AppToast.error('El enlace remoto al repositorio no está configurado');
      return;
    }

    setState(() {
      _executing = true;
      _errorMessage = null;
      _stepStatus = 'Extrayendo y generando scripts SQL de hotfix...';
    });

    try {
      // 1. Generar scripts directamente en la carpeta local de scripts (sin .xlsx ni paseambientescript)
      final exporter = DeployTicketExporterService.instance;
      final exported = await exporter.exportarScriptsHotfix(
        ticket: widget.ticket,
        targetDirectoryPath: _localPath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _stepStatus = p.mensaje;
            });
          }
        },
      );

      // 2. Comprobar que estemos en la rama adecuada o cambiar a ella
      final git = GitService(workingDirectory: _localPath);
      final activeBranch = await git.getCurrentBranch();

      if (activeBranch != _currentBranch) {
        setState(() => _stepStatus = 'Cambiando a rama $_currentBranch...');
        final branchExists = await git.branchExists(_currentBranch);
        if (branchExists) {
          final checkoutRes = await git.checkout(_currentBranch);
          if (!checkoutRes.isSuccess) {
            throw Exception(
              'Error al cambiar a rama $_currentBranch: ${checkoutRes.stderr}',
            );
          }
        } else {
          final checkoutRes = await git.createAndCheckoutBranch(_currentBranch);
          if (!checkoutRes.isSuccess) {
            throw Exception(
              'Error al crear rama $_currentBranch: ${checkoutRes.stderr}',
            );
          }
        }
      }

      // 3. Stage de los archivos generados (excluyendo cualquier .xlsx)
      setState(() => _stepStatus = 'Añadiendo archivos al commit (git add)...');
      final relativeFiles = <String>[];
      for (final f in exported) {
        if (f.nombreArchivo.toLowerCase().endsWith('.xlsx')) continue;
        final file = File(f.rutaCompleta);
        if (file.path.startsWith(_localPath)) {
          final rel = file.path
              .substring(_localPath.length)
              .replaceAll(RegExp(r'^[\\/]+'), '');
          relativeFiles.add(rel);
        } else {
          relativeFiles.add(f.rutaCompleta);
        }
      }

      if (relativeFiles.isNotEmpty) {
        final addRes = await git.addFiles(relativeFiles);
        if (!addRes.isSuccess) {
          await git.add('.');
        }
      } else {
        await git.add('.');
      }

      // 4. Commit
      setState(() => _stepStatus = 'Realizando commit en $_currentBranch...');
      final commitRes = await git.commit(commitMsg);
      if (!commitRes.isSuccess &&
          !commitRes.stdout.contains('nothing to commit')) {
        throw Exception('Error en commit: ${commitRes.output}');
      }

      // 5. Push al servidor remoto con autorización (Token PAT / SSH)
      setState(
        () => _stepStatus =
            'Haciendo push de $_currentBranch al servidor remoto...',
      );
      final pushRes = await git.push(
        branchName: _currentBranch,
        remoteUrl: _remoteUrl,
        authType: _authType,
        token: _token,
      );
      if (!pushRes.isSuccess) {
        throw Exception('Error en push remoto: ${pushRes.output}');
      }

      // 6. Actualizar ticket en el servidor con los enlaces del hotfix
      setState(
        () => _stepStatus = 'Guardando enlace de hotfix en el servidor...',
      );
      final activeUser =
          (procedimientosProvider.cdUsuario.trim().isNotEmpty
                  ? procedimientosProvider.cdUsuario.trim()
                  : DeployTicketService.currentUser)
              .toUpperCase();

      final updatedTicket = widget.ticket.copyWith(
        rutaRepositorio: _remoteUrl,
        rutaDirectorioLocal: _localPath,
        usuarioActualiza: activeUser,
      );

      final persistedTicket = await DeployTicketService.instance.save(
        updatedTicket,
      );

      if (!mounted) return;
      AppToast.success(
        'Push realizado con éxito en rama $_currentBranch (${exported.length} scripts)',
      );
      _closeDialog(persistedTicket);
    } catch (e) {
      AppLog.instance.error('Error en Push Hotfix: $e', source: 'PushHotfix');
      if (!mounted) return;
      setState(() {
        _executing = false;
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
    final cardBg = isDark ? const Color(0xFF252731) : const Color(0xFFF8FAFC);
    final inputBg = isDark ? const Color(0xFF1B1C22) : Colors.white;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 610,
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
              // Encabezado ConstellationHeader con gradiente verde esmeralda
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
                      const Color(0xFF059669), // Emerald-600
                      Color.lerp(
                            const Color(0xFF047857), // Emerald-700
                            isDark ? Colors.black : const Color(0xFF064E3B),
                            0.4,
                          ) ??
                          const Color(0xFF047857),
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
                        Icons.cloud_upload_rounded,
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
                            'Generar Scripts y Realizar Push',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rama: $_currentBranch | Ticket #${widget.ticket.numeroSolicitud}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFA7F3D0), // Emerald-200
                              fontWeight: FontWeight.w600,
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
                      onPressed: _executing ? null : () => _closeDialog(null),
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
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Resumen de artefactos a generar
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome_motion_rounded,
                                        size: 16,
                                        color: cs.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Artefactos a generar y subir al servidor:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '(excluyendo .xlsx)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (widget
                                          .ticket
                                          .reglasNegocio
                                          .isNotEmpty)
                                        _badge(
                                          'RN: ${widget.ticket.reglasNegocio.length}',
                                          Colors.blue,
                                        ),
                                      if (widget.ticket.paquetes.isNotEmpty)
                                        _badge(
                                          'PCK: ${widget.ticket.paquetes.length}',
                                          Colors.purple,
                                        ),
                                      if (widget.ticket.funciones.isNotEmpty)
                                        _badge(
                                          'FUN: ${widget.ticket.funciones.length}',
                                          Colors.teal,
                                        ),
                                      if (widget.ticket.sql.isNotEmpty)
                                        _badge(
                                          'SQL: ${widget.ticket.sql.length}',
                                          Colors.amber,
                                        ),
                                      if (widget.ticket.reverseSql.isNotEmpty)
                                        _badge(
                                          'RSQL: ${widget.ticket.reverseSql.length}',
                                          Colors.deepOrange,
                                        ),
                                      if (widget.ticket.objetos.isNotEmpty)
                                        _badge(
                                          'OBJ: ${widget.ticket.objetos.length}',
                                          Colors.indigo,
                                        ),
                                      if (widget.ticket.triggers.isNotEmpty)
                                        _badge(
                                          'TRG: ${widget.ticket.triggers.length}',
                                          Colors.cyan,
                                        ),
                                      if (widget.ticket.bloqueLogico.isNotEmpty)
                                        _badge(
                                          'BLK: ${widget.ticket.bloqueLogico.length}',
                                          Colors.pink,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Divider(height: 1, color: borderColor),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Carpeta local: $_localPath',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'Consolas, monospace',
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.cloud_outlined,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Servidor remoto: $_remoteUrl',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'Consolas, monospace',
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Autorización: ${_authType == GitAuthType.token ? "HTTPS (Token PAT)" : "SSH (Clave local)"}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Mensaje de Commit editable
                            Text(
                              'Mensaje de Commit',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _commitMsgCtrl,
                              enabled: !_executing,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: inputBg,
                                hintText: 'hotfix: descripción de cambios...',
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
                                  vertical: 10,
                                ),
                              ),
                            ),

                            if (_stepStatus.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _stepStatus,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.greenAccent.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (_errorMessage != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
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
                          ],
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
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _executing ? null : () => _closeDialog(null),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade700,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _executing ? null : _executeGenerateAndPush,
                      icon: _executing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: const Text('Generar Scripts y Hacer Push'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade700.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.shade500.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.shade300,
        ),
      ),
    );
  }
}
