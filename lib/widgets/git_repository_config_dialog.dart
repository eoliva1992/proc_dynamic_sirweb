import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/git_repository_config_service.dart';
import '../services/git_service.dart';
import 'app_toast.dart';
import 'constellation_background.dart';
import 'floating_window.dart' show showFloatingDialog;

/// Diálogo modal para configurar la URL remota del repositorio, ruta local y credenciales de push.
class GitRepositoryConfigDialog extends StatefulWidget {
  final VoidCallback? onConfigChanged;
  final void Function([void])? onClose;

  const GitRepositoryConfigDialog({
    super.key,
    this.onConfigChanged,
    this.onClose,
  });

  /// Muestra el diálogo usando `showFloatingDialog` para asegurar que siempre
  /// se renderice por encima de cualquier ventana flotante.
  static Future<void> show(
    BuildContext context, {
    VoidCallback? onConfigChanged,
  }) {
    return showFloatingDialog<void>(
      context,
      (ctx, close) => GitRepositoryConfigDialog(
        onConfigChanged: onConfigChanged,
        onClose: close,
      ),
    );
  }

  @override
  State<GitRepositoryConfigDialog> createState() =>
      _GitRepositoryConfigDialogState();
}

class _GitRepositoryConfigDialogState extends State<GitRepositoryConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _remoteUrlCtrl;
  late TextEditingController _localCtrl;
  late TextEditingController _tokenCtrl;

  GitAuthType _authType = GitAuthType.token;
  bool _obscureToken = true;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCheckingGit = false;
  String? _gitValidationStatus;
  bool _isGitValid = false;

  // Estado para la comprobación en vivo del Personal Access Token / remoto
  bool _isTestingToken = false;
  GitRemoteValidationResult? _tokenTestResult;

  @override
  void initState() {
    super.initState();
    _remoteUrlCtrl = TextEditingController();
    _localCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _remoteUrlCtrl.dispose();
    _localCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _closeDialog() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadCurrentConfig() async {
    final config = await GitRepositoryConfigService().getConfig();
    if (!mounted) return;
    setState(() {
      _remoteUrlCtrl.text = config.rutaRepositorio;
      _localCtrl.text = config.rutaDirectorioLocal;
      _authType = config.authType;
      _tokenCtrl.text = config.personalAccessToken;
      _isLoading = false;
    });

    if (config.rutaDirectorioLocal.isNotEmpty) {
      _validateRepository(config.rutaDirectorioLocal);
    }
  }

  Future<void> _validateRepository(String path) async {
    if (path.trim().isEmpty) {
      setState(() {
        _gitValidationStatus = null;
        _isGitValid = false;
      });
      return;
    }

    setState(() => _isCheckingGit = true);
    final gitService = GitService(workingDirectory: path.trim());
    final isRepo = await gitService.isGitRepository();
    String? currentBranch;
    if (isRepo) {
      currentBranch = await gitService.getCurrentBranch();
    }

    if (!mounted) return;
    setState(() {
      _isCheckingGit = false;
      _isGitValid = isRepo;
      if (isRepo) {
        _gitValidationStatus =
            'Repositorio local válido (Rama actual: ${currentBranch ?? 'desconocida'})';
      } else {
        _gitValidationStatus =
            'La carpeta local no contiene un repositorio Git inicializado (.git)';
      }
    });
  }

  Future<void> _pickLocalDirectory() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle:
          'Seleccionar carpeta local del proyecto / repositorio clonado',
    );
    if (selected != null && selected.trim().isNotEmpty) {
      setState(() {
        _localCtrl.text = selected.trim();
      });
      _validateRepository(selected.trim());
    }
  }

  /// Comprueba en vivo el Personal Access Token y la URL remota mediante `git ls-remote`
  Future<void> _testRemoteAccessToken() async {
    final remoteUrl = _remoteUrlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    if (remoteUrl.isEmpty) {
      AppToast.warning(
        'Ingresa la URL remota del repositorio antes de comprobar',
      );
      return;
    }

    if (token.isEmpty) {
      AppToast.warning('Ingresa el Personal Access Token (PAT) para comprobar');
      return;
    }

    setState(() {
      _isTestingToken = true;
      _tokenTestResult = null;
    });

    try {
      final result = await GitService.validateRemoteAccessToken(
        remoteUrl: remoteUrl,
        personalAccessToken: token,
      );

      if (!mounted) return;
      setState(() {
        _tokenTestResult = result;
      });

      if (result.isValid) {
        AppToast.success('Token y conexión al repositorio verificados');
      } else {
        AppToast.error('Fallo de autenticación: ${result.message}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tokenTestResult = GitRemoteValidationResult(
          isValid: false,
          message: 'Error inesperado al probar conexión: $e',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isTestingToken = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    final remoteUrl = _remoteUrlCtrl.text.trim();
    final localPath = _localCtrl.text.trim();

    if (localPath.isNotEmpty && !Directory(localPath).existsSync()) {
      AppToast.error('La ruta local en disco no existe');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await GitRepositoryConfigService().saveConfig(
        rutaRepositorio: remoteUrl,
        rutaDirectorioLocal: localPath,
        authType: _authType,
        personalAccessToken: _tokenCtrl.text.trim(),
      );

      if (!mounted) return;
      AppToast.success('Configuración de repositorio Git guardada');
      widget.onConfigChanged?.call();
      _closeDialog();
    } catch (e) {
      if (!mounted) return;
      AppToast.error('Error al guardar configuración: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          width: 620,
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
              // Encabezado ConstellationHeader con gradiente temático
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
                      cs.primary,
                      Color.lerp(
                            cs.primary,
                            isDark ? Colors.black : const Color(0xFF003D73),
                            0.45,
                          ) ??
                          cs.primary,
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
                        Icons.settings_suggest_rounded,
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
                            'Configuración de Repositorio Remoto y Git Push',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Enlace remoto al servidor, directorio local y autorización',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.85),
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
                      onPressed: _closeDialog,
                    ),
                  ],
                ),
              ),

              // Contenido
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _isLoading
                      ? const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Sección: Rutas
                              Text(
                                'RUTAS DE REPOSITORIO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Campo: URL Remota (rutaRepositorio)
                              Text(
                                'Enlace Remoto al Servidor (rutaRepositorio)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'URL del repositorio remoto (Azure DevOps, GitLab, GitHub, etc.)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _remoteUrlCtrl,
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  hintText:
                                      'https://dev.azure.com/org/project/_git/repo o git@github.com:...',
                                  prefixIcon: const Icon(
                                    Icons.cloud_outlined,
                                    size: 20,
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
                                    return 'El enlace remoto al servidor es requerido para push';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              // Campo: Ruta Local (rutaDirectorioLocal)
                              Text(
                                'Directorio Local en Disco (rutaDirectorioLocal)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Carpeta en tu PC donde está clonado el repositorio y donde se generan los scripts',
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
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: inputBg,
                                  hintText: 'C:\\Proyectos\\MiProyectoGit',
                                  prefixIcon: const Icon(
                                    Icons.folder_open_rounded,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.drive_folder_upload_rounded,
                                    ),
                                    tooltip: 'Seleccionar carpeta local...',
                                    onPressed: _pickLocalDirectory,
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
                                onChanged: (val) => _validateRepository(val),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El directorio local es requerido';
                                  }
                                  return null;
                                },
                              ),

                              // Estado de validación del repo local
                              if (_isCheckingGit) ...[
                                const SizedBox(height: 6),
                                const Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Validando repositorio local...',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ] else if (_gitValidationStatus != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      _isGitValid
                                          ? Icons.check_circle_rounded
                                          : Icons.info_outline_rounded,
                                      size: 14,
                                      color: _isGitValid
                                          ? Colors.greenAccent.shade700
                                          : Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _gitValidationStatus!,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: _isGitValid
                                              ? Colors.greenAccent.shade700
                                              : Colors.amber.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 20),
                              Divider(color: borderColor, height: 1),
                              const SizedBox(height: 16),

                              // Sección: Autorización
                              Text(
                                'AUTORIZACIÓN PARA PUSH REMOTO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Segmented Button Auth Type
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => setState(
                                          () => _authType = GitAuthType.token,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                _authType == GitAuthType.token
                                                ? cs.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.key_rounded,
                                                size: 16,
                                                color:
                                                    _authType ==
                                                        GitAuthType.token
                                                    ? Colors.white
                                                    : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'HTTPS con Token / PAT',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      _authType ==
                                                          GitAuthType.token
                                                      ? Colors.white
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.black87),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => setState(
                                          () => _authType = GitAuthType.ssh,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _authType == GitAuthType.ssh
                                                ? cs.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.terminal_rounded,
                                                size: 16,
                                                color:
                                                    _authType == GitAuthType.ssh
                                                    ? Colors.white
                                                    : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'SSH (Clave local)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      _authType ==
                                                          GitAuthType.ssh
                                                      ? Colors.white
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.black87),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),

                              if (_authType == GitAuthType.token) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Personal Access Token (PAT)',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Token con permisos Code (Read & Write).',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Botón para probar token en vivo
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        side: BorderSide(
                                          color: _tokenTestResult == null
                                              ? borderColor
                                              : (_tokenTestResult!.isValid
                                                    ? Colors
                                                          .greenAccent
                                                          .shade700
                                                    : Colors
                                                          .redAccent
                                                          .shade700),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _isTestingToken
                                          ? null
                                          : _testRemoteAccessToken,
                                      icon: _isTestingToken
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              _tokenTestResult == null
                                                  ? Icons.network_check_rounded
                                                  : (_tokenTestResult!.isValid
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons
                                                              .error_outline_rounded),
                                              size: 16,
                                              color: _tokenTestResult == null
                                                  ? cs.primary
                                                  : (_tokenTestResult!.isValid
                                                        ? Colors
                                                              .greenAccent
                                                              .shade700
                                                        : Colors
                                                              .redAccent
                                                              .shade700),
                                            ),
                                      label: Text(
                                        _isTestingToken
                                            ? 'Comprobando...'
                                            : (_tokenTestResult == null
                                                  ? 'Comprobar Token'
                                                  : (_tokenTestResult!.isValid
                                                        ? 'Token Válido'
                                                        : 'Reintentar')),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: _tokenTestResult == null
                                              ? (isDark
                                                    ? Colors.white70
                                                    : Colors.black87)
                                              : (_tokenTestResult!.isValid
                                                    ? Colors
                                                          .greenAccent
                                                          .shade700
                                                    : Colors
                                                          .redAccent
                                                          .shade700),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _tokenCtrl,
                                  obscureText: _obscureToken,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontFamily: 'Consolas, monospace',
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: inputBg,
                                    hintText: 'ghp_... o token Azure DevOps',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureToken
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscureToken = !_obscureToken,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: borderColor,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: borderColor,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                  ),
                                  onChanged: (_) {
                                    if (_tokenTestResult != null) {
                                      setState(() => _tokenTestResult = null);
                                    }
                                  },
                                ),
                                if (_tokenTestResult != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _tokenTestResult!.isValid
                                          ? Colors.greenAccent.shade700
                                                .withValues(alpha: 0.12)
                                          : Colors.redAccent.shade700
                                                .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _tokenTestResult!.isValid
                                            ? Colors.greenAccent.shade700
                                                  .withValues(alpha: 0.4)
                                            : Colors.redAccent.shade700
                                                  .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _tokenTestResult!.isValid
                                              ? Icons.check_circle_rounded
                                              : Icons.warning_amber_rounded,
                                          size: 16,
                                          color: _tokenTestResult!.isValid
                                              ? Colors.greenAccent.shade700
                                              : Colors.redAccent.shade400,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _tokenTestResult!.message,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: _tokenTestResult!.isValid
                                                  ? (isDark
                                                        ? Colors
                                                              .greenAccent
                                                              .shade100
                                                        : Colors.green.shade800)
                                                  : (isDark
                                                        ? Colors
                                                              .redAccent
                                                              .shade100
                                                        : Colors.red.shade800),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: Colors.blueAccent.shade200,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Para SSH, el cliente utilizará la clave privada configurada en tu usuario del sistema (~/.ssh/id_rsa o agente SSH) en modo no interactivo.',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
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
              ),

              // Footer con botones
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
                      onPressed: _closeDialog,
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveConfig,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Guardar Configuración'),
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
}
