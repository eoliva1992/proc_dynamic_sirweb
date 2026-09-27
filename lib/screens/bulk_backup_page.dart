import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../models/bulk_backup_item.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../services/backup_service.dart';
import '../services/bulk_backup_service.dart';
import '../services/bulk_backup_selection_service.dart';
import '../services/schema_service.dart';
import '../services/sirweb_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/object_source_page.dart';
import '../widgets/app_toast.dart';
import '../widgets/constellation_background.dart';
import '../widgets/floating_window.dart';

/// Abre el backup masivo como ventana flotante: arrastrable, redimensionable,
/// minimizable y con los mismos controles nativos que el comparador de
/// esquema (`showSchemaObjectDiff`).
VoidCallback showBulkBackupWindow(BuildContext context, {required String ambiente}) {
  return showFloatingWindow(
    context,
    (close) => BulkBackupPage(ambiente: ambiente, onClose: close),
  );
}

class BulkBackupPage extends StatefulWidget {
  final String ambiente;

  /// Cierra la ventana flotante. Si es `null` se hace `Navigator.pop`.
  final VoidCallback? onClose;

  const BulkBackupPage({super.key, required this.ambiente, this.onClose});

  @override
  State<BulkBackupPage> createState() => _BulkBackupPageState();
}

class _BulkBackupPageState extends State<BulkBackupPage> with TickerProviderStateMixin {
  static const double _kMinW = 760;
  static const double _kHeaderH = 44;

  late String _ambiente;
  late Future<SchemaMetadata> _metadata;
  final _searchController = TextEditingController();
  final _selected = <BulkBackupItem>{};
  var _config = const BulkBackupConfig();
  var _category = 'all';
  bool _running = false;
  bool _refreshing = false;
  bool _cancelRequested = false;
  String _phase = 'Generando';
  int _completed = 0;
  int _total = 0;
  String _currentName = '';
  List<String> _failures = const [];
  bool _showCompactSelected = false;
  final _favoriteIds = <String>{};
  final _selectionService = BulkBackupSelectionService();
  final _dynamicService = SirwebService();
  var _dynamicProcedures = <Procedimiento>[];
  int _dynamicLoadId = 0;

  // ── Geometría de la ventana flotante ──────────────────────────────────────
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  double? _restoreW;
  double? _restoreH;
  Offset _restorePos = Offset.zero;
  Duration _anim = Duration.zero;
  late final AnimationController _syncIconController;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _syncIconController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _shimmerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _ambiente = widget.ambiente;
    _metadata = SchemaService.instance.getMetadata(ambiente: _ambiente);
    procedimientosProvider.setAmbiente(_ambiente);
    unawaited(
      _loadDynamicProcedures().catchError((error) {
        if (mounted) {
          AppToast.error('No se pudieron cargar los procedimientos dinámicos: $error');
        }
      }),
    );
    _loadFavoriteIds();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _loadFavoriteIds() async {
    final ids = await _selectionService.getFavoriteIds();
    if (mounted) {
      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(ids);
      });
    }
  }

  Future<void> _loadDynamicProcedures() async {
    final loadId = ++_dynamicLoadId;
    final procedures = await _dynamicService.listarTodosProcedimientos(
      estado: null,
      ambiente: _ambiente,
    );
    if (!mounted || loadId != _dynamicLoadId) return;
    setState(() => _dynamicProcedures = procedures);
  }

  @override
  void dispose() {
    FloatingWindowSlots.release(_slot);
    _searchController.dispose();
    _syncIconController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_maximized) {
        _winW = _restoreW;
        _winH = _restoreH;
        _position = _restorePos;
        _maximized = false;
      } else {
        _restoreW = _winW;
        _restoreH = _winH;
        _restorePos = _position;
        _position = Offset.zero;
        _maximized = true;
      }
    });
  }

  void _toggleMinimized() {
    if (_running) return;
    setState(() {
      _anim = const Duration(milliseconds: 180);
      if (_minimized) {
        FloatingWindowSlots.release(_slot);
        _slot = null;
        _minimized = false;
      } else {
        _slot = FloatingWindowSlots.take();
        _minimized = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _close() {
    FloatingWindowSlots.release(_slot);
    _slot = null;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _changeAmbiente(String value) async {
    if (value == _ambiente || _running || _refreshing) return;
    procedimientosProvider.setAmbiente(value);
    final metadataFuture = SchemaService.instance.getMetadata(ambiente: value);
    setState(() {
      _refreshing = true;
      _ambiente = value;
      _selected.clear();
      _category = 'all';
      _searchController.clear();
      _dynamicProcedures = [];
      _metadata = metadataFuture;
    });
    try {
      // El schema se refleja vía FutureBuilder; esperamos ambas cargas para
      // forzar un rebuild que también muestre todas las reglas dinámicas.
      await Future.wait([
        metadataFuture,
        _loadDynamicProcedures(),
      ]);
    } catch (_) {
      // El error de metadata ya lo muestra el FutureBuilder del catálogo.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _refreshAmbiente() async {
    if (_running || _refreshing) return;
    setState(() {
      _refreshing = true;
      _selected.clear();
      _category = 'all';
      _dynamicProcedures = [];
      _metadata = SchemaService.instance.refreshAmbiente(_ambiente);
    });
    try {
      await Future.wait([
        _metadata,
        _loadDynamicProcedures(),
      ]);
      if (mounted) AppToast.success('Ambiente $_ambiente actualizado');
    } catch (error) {
      if (mounted) AppToast.error('No se pudo actualizar el ambiente: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<BulkBackupItem> _schemaItems(SchemaMetadata metadata) {
    return [
      ...metadata.tables.map(
        (name) => BulkBackupItem(
          name: name,
          type: 'TABLE',
          owner: metadata.tableOwners[name] ?? metadata.owner,
          source: BulkBackupSource.schema,
        ),
      ),
      ...metadata.views.map(
        (name) => BulkBackupItem(
          name: name,
          type: 'VIEW',
          owner: metadata.viewOwners[name] ?? metadata.owner,
          source: BulkBackupSource.schema,
        ),
      ),
      ...metadata.objects.map(
        (object) => BulkBackupItem(
          name: object.name,
          type: object.type,
          owner: object.owner.isEmpty ? metadata.owner : object.owner,
          source: BulkBackupSource.schema,
        ),
      ),
    ];
  }

  List<BulkBackupItem> _dynamicItems() {
    return _dynamicProcedures
        .map(
          (procedure) => BulkBackupItem(
            name: procedure.cdProcedimiento,
            type: 'PROCEDURE_DYNAMIC',
            source: BulkBackupSource.dynamicProcedure,
            procedimiento: procedure,
          ),
        )
        .toList();
  }

  List<BulkBackupItem> _visibleItems(SchemaMetadata metadata) {
    final query = _searchController.text.trim().toUpperCase();
    final all = [..._schemaItems(metadata), ..._dynamicItems()];
    return all
        .where(
          (item) =>
                (_category == 'all' ||
                  (_category == 'favorites'
                    ? _favoriteIds.contains(item.id)
                    : item.category == _category)) &&
              (query.isEmpty || item.name.toUpperCase().contains(query)),
        )
        .toList();
  }

  Future<void> _toggleSelectedFavorites() async {
    if (_selected.isEmpty) {
      AppToast.warning('Seleccioná al menos un objeto para marcarlo como favorito');
      return;
    }
    final add = !_selected.every((item) => _favoriteIds.contains(item.id));
    await _selectionService.setFavoriteItems(_selected, favorite: add);
    if (!mounted) return;
    setState(() {
      if (add) {
        _favoriteIds.addAll(_selected.map((item) => item.id));
      } else {
        _favoriteIds.removeAll(_selected.map((item) => item.id));
      }
    });
    AppToast.success(add ? 'Objetos agregados a favoritos' : 'Objetos quitados de favoritos');
  }

  Future<void> _toggleItemFavorite(BulkBackupItem item) async {
    final add = !_favoriteIds.contains(item.id);
    await _selectionService.setFavoriteItems([item], favorite: add);
    if (!mounted) return;
    setState(() {
      if (add) {
        _favoriteIds.add(item.id);
      } else {
        _favoriteIds.remove(item.id);
      }
    });
  }

  Future<void> _runBackup(SchemaMetadata metadata) async {
    if (_selected.isEmpty) {
      AppToast.warning('Seleccioná al menos un objeto');
      return;
    }
    if (!_config.includeSpec &&
        !_config.includeBody &&
        !_config.includeTableComments &&
        !_config.includeGrants &&
        !_config.includeSynonyms) {
      AppToast.warning('Seleccioná al menos un componente del backup');
      return;
    }
    final basePath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Elegir carpeta para el backup masivo',
    );
    if (basePath == null || !mounted) return;

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final executionDirectory = Directory(
      '$basePath${Platform.pathSeparator}${BulkBackupService.safeFileName(_ambiente)}_$stamp',
    );
    final items = _selected.toList();
    setState(() {
      _running = true;
      _cancelRequested = false;
      _phase = 'Generando';
      _completed = 0;
      _total = items.length;
      _currentName = '';
      _failures = const [];
    });

    final scripts = <String, String>{};
    final failures = <String>[];
    for (var index = 0; index < items.length; index++) {
      if (_cancelRequested) break;
      final item = items[index];
      if (mounted) setState(() => _currentName = item.name);
      try {
        if (item.source == BulkBackupSource.dynamicProcedure) {
          scripts[item.id] = BulkBackupService.buildDynamicScript(
            item.procedimiento!,
            _ambiente,
            procedimientosProvider.cdUsuario,
          );
        } else {
          final source = item.type == 'TABLE'
              ? await _tableScript(item)
              : await _schemaScript(item);
          scripts[item.id] = source;
        }
      } catch (error) {
        failures.add('${item.name}: $error');
      }
      if (mounted) setState(() => _completed = index + 1);
    }

    if (mounted && !_cancelRequested) {
      setState(() {
        _phase = 'Guardando';
        _completed = 0;
        _total = scripts.length;
      });
    }

    final result = await BulkBackupService.writeAll(
      directory: executionDirectory,
      ambiente: _ambiente,
      items: items.where((item) => scripts.containsKey(item.id)).toList(),
      scripts: scripts,
      isCancelled: () => _cancelRequested,
      onProgress: (completed, total, name) {
        if (mounted) {
          setState(() {
            _completed = completed;
            _total = total;
            _currentName = name;
          });
        }
      },
    );
    if (!mounted) return;
    final wasCancelled = _cancelRequested;
    final totalFailures = [...failures, ...result.failures.map((f) => '${f.name}: ${f.error}')];
    setState(() {
      _running = false;
      _cancelRequested = false;
      _failures = totalFailures;
    });
    if (wasCancelled) {
      AppToast.warning('${result.written.length} backups generados antes de cancelar');
      return;
    }
    if (totalFailures.isEmpty) {
      AppToast.successWithAction(
        '${result.written.length} backups generados',
        detail: result.directory,
        actionLabel: 'Abrir ubicación',
        onAction: () => unawaited(BackupService.revealInExplorer(result.directory)),
      );
    } else {
      AppToast.warning(
        '${result.written.length} generados; ${totalFailures.length} con error',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<String> _schemaScript(BulkBackupItem item) async {
    final source = await SchemaService.instance.getObjectSource(
      item.name,
      item.type,
      ambiente: _ambiente,
    );
    final grants = _config.includeGrants
        ? await SchemaService.instance.getObjectPrivileges(item.name, ambiente: _ambiente)
        : const <({String grantee, String privilege, bool grantable, String grantor})>[];
    final synonyms = _config.includeSynonyms
        ? await SchemaService.instance.getSynonyms(item.name, ambiente: _ambiente)
        : const <({String synonymName, bool isPublic, String owner})>[];
    return BulkBackupService.buildSchemaScript(
      item: item,
      ambiente: _ambiente,
      spec: source.spec,
      body: source.body,
      grants: grants,
      synonyms: synonyms,
      config: _config,
    );
  }

  Future<String> _tableScript(BulkBackupItem item) async {
    final ddl = await SchemaService.instance.getTableDdl(item.name, ambiente: _ambiente);
    return BulkBackupService.buildSchemaScript(
      item: item,
      ambiente: _ambiente,
      spec: ddl.createTable,
      tableComments: ddl.comments,
      tableGrants: ddl.grants,
      config: _config,
    );
  }

  void _cancelBackup() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
  }

  Future<void> _editConfig() async {
    var next = _config;
    await showFloatingDialog<void>(
      context,
      (dialogContext, close) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const ConstellationDialogTitle(
            padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
            borderRadius: BorderRadius.zero,
            child: Text('Configuración del backup'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _check('Especificación / DDL', next.includeSpec, (value) => setDialogState(() => next = BulkBackupConfig(includeSpec: value, includeBody: next.includeBody, includeTableComments: next.includeTableComments, includeGrants: next.includeGrants, includeSynonyms: next.includeSynonyms))),
              _check('Cuerpo de package/type', next.includeBody, (value) => setDialogState(() => next = BulkBackupConfig(includeSpec: next.includeSpec, includeBody: value, includeTableComments: next.includeTableComments, includeGrants: next.includeGrants, includeSynonyms: next.includeSynonyms))),
              _check('Comentarios de tabla', next.includeTableComments, (value) => setDialogState(() => next = BulkBackupConfig(includeSpec: next.includeSpec, includeBody: next.includeBody, includeTableComments: value, includeGrants: next.includeGrants, includeSynonyms: next.includeSynonyms))),
              _check('Grants', next.includeGrants, (value) => setDialogState(() => next = BulkBackupConfig(includeSpec: next.includeSpec, includeBody: next.includeBody, includeTableComments: next.includeTableComments, includeGrants: value, includeSynonyms: next.includeSynonyms))),
              _check('Sinónimos públicos', next.includeSynonyms, (value) => setDialogState(() => next = BulkBackupConfig(includeSpec: next.includeSpec, includeBody: next.includeBody, includeTableComments: next.includeTableComments, includeGrants: next.includeGrants, includeSynonyms: value))),
            ],
          ),
          actions: [
            TextButton(onPressed: close, child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                setState(() => _config = next);
                close();
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askListName({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final name = await showFloatingDialog<String>(
      context,
      (dialogContext, close) => AlertDialog(
        title: const Text('Guardar lista de backup'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la lista',
            hintText: 'Ej. Objetos críticos',
          ),
          onSubmitted: (value) => close(value.trim()),
        ),
        actions: [
          TextButton(onPressed: close, child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => close(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  List<BulkBackupItem> _catalogItems(SchemaMetadata metadata) => [
        ..._schemaItems(metadata),
        ..._dynamicItems(),
      ];

  Future<void> _applySavedList(BulkBackupSelectionList list) async {
    final metadata = await _metadata;
    final catalog = _catalogItems(metadata);
    final byId = {for (final item in catalog) item.id: item};
    final resolved = <BulkBackupItem>[];
    final missing = <String>[];
    for (final reference in list.items) {
      final item = byId[reference.id];
      if (item == null) {
        missing.add('${reference.type}: ${reference.name}');
      } else {
        resolved.add(item);
      }
    }
    if (!mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(resolved);
      _config = list.config;
    });
    if (missing.isNotEmpty) {
      AppToast.warning(
        'Lista cargada: ${resolved.length} objetos; ${missing.length} no disponibles',
        duration: const Duration(seconds: 5),
      );
    } else {
      AppToast.success('${resolved.length} objetos cargados desde "${list.name}"');
    }
  }

  Future<void> _saveSelectionList() async {
    final name = await _askListName();
    if (name == null) return;
    await _selectionService.saveList(
      BulkBackupSelectionList(
        name: name,
        savedAt: DateTime.now().toUtc(),
        savedFromAmbiente: _ambiente,
        items: _selected,
        config: _config,
      ),
    );
    if (mounted) AppToast.success('Lista "$name" guardada');
  }

  Future<void> _loadSavedList() async {
    final lists = await _selectionService.getLists();
    if (!mounted) return;
    if (lists.isEmpty) {
      AppToast.warning('No hay listas guardadas');
      return;
    }
    final selected = await showFloatingDialog<BulkBackupSelectionList>(
      context,
      (dialogContext, close) => AlertDialog(
        title: const Text('Cargar lista guardada'),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: lists.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final list = lists[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.playlist_play_outlined),
                title: Text(list.name, overflow: TextOverflow.ellipsis),
                subtitle: Text('${list.items.length} objetos · ${list.savedFromAmbiente}'),
                onTap: () => close(list),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: close, child: const Text('Cancelar'))],
      ),
    );
    if (selected != null) await _applySavedList(selected);
  }

  Future<void> _exportSelectionList() async {
    final name = await _askListName(initial: 'Backup $_ambiente');
    if (name == null) return;
    final list = BulkBackupSelectionList(
      name: name,
      savedAt: DateTime.now().toUtc(),
      savedFromAmbiente: _ambiente,
      items: _selected,
      config: _config,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: 'Exportar lista de backup',
      fileName: '${BulkBackupService.safeFileName(name)}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null) return;
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonDecode(BulkBackupSelectionService.encode(list))),
      flush: true,
    );
    if (mounted) AppToast.success('Lista exportada');
  }

  Future<void> _importSelectionList() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Cargar lista de backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final list = BulkBackupSelectionService.decode(await File(path).readAsString());
      await _applySavedList(list);
    } on FormatException catch (error) {
      if (mounted) AppToast.warning('No se pudo cargar la lista: ${error.message}');
    } on IOException {
      if (mounted) AppToast.warning('No se pudo leer el archivo seleccionado');
    }
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_configDescription(label)),
      value: value,
      onChanged: (value) => onChanged(value ?? false),
    );
  }

  String _configDescription(String label) {
    return switch (label) {
      'Especificación / DDL' => 'Define la estructura del objeto',
      'Cuerpo de package/type' => 'Incluye la implementación del código',
      'Comentarios de tabla' => 'Conserva comentarios y documentación',
      'Grants' => 'Incluye permisos otorgados',
      'Sinónimos públicos' => 'Incluye alias públicos del objeto',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18);

    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.72).clamp(_kMinW, 1100.0);
      _winH ??= (size.height * 0.78).clamp(480.0, 820.0);
    }
    if (_winW! > size.width) _winW = size.width;
    if (_winH! > size.height) _winH = size.height;

    final double w, h, left, top;
    if (_minimized) {
      w = FloatingWindowSlots.barW;
      h = FloatingWindowSlots.barH;
      final (l, t) = FloatingWindowSlots.offsetFor(_slot ?? 0, size);
      left = l;
      top = t;
    } else {
      w = _winW!;
      h = _winH!;
      left = ((size.width - w) / 2 + _position.dx).clamp(0.0, (size.width - w).clamp(0.0, double.infinity));
      top = ((size.height - h) / 2 + _position.dy).clamp(0.0, (size.height - h).clamp(0.0, double.infinity));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleMaximized,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: !_minimized,
        canRequestFocus: !_minimized,
        descendantsAreFocusable: !_minimized,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: _anim,
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: w,
              height: h,
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(_maximized ? 6 : (_minimized ? 8 : 12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                        blurRadius: _minimized ? 16 : 40,
                        offset: Offset(0, _minimized ? 4 : 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      width: _winW,
                      height: _winH,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Column(
                              children: [
                                const SizedBox(height: _kHeaderH),
                                Expanded(child: _buildCatalog(context)),
                              ],
                            ),
                          ),
                          Positioned(left: 0, top: 0, width: w, child: _buildHeader(context, isDark, cs)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 5,
                top: top + 44,
                width: 10,
                height: (h - 54).clamp(0.0, double.infinity),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(_kMinW, size.width - 40);
                    }),
                  ),
                ),
              ),
            if (!_maximized && !_minimized)
              Positioned(
                left: left + 16,
                top: top + h - 5,
                width: (w - 32).clamp(0.0, double.infinity),
                height: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winH = (_winH! + d.delta.dy).clamp(480.0, size.height - 40);
                    }),
                  ),
                ),
              ),
            if (!_maximized && !_minimized)
              Positioned(
                left: left + w - 18,
                top: top + h - 18,
                width: 22,
                height: 22,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _anim = Duration.zero;
                      _winW = (_winW! + d.delta.dx).clamp(_kMinW, size.width - 40);
                      _winH = (_winH! + d.delta.dy).clamp(480.0, size.height - 40);
                    }),
                    child: CustomPaint(painter: WindowGripPainter(gripColor)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Barra de título (arrastrable) ─────────────────────────────────────────

  Widget _buildHeader(BuildContext context, bool isDark, ColorScheme cs) {
    final divColor = cs.outlineVariant;
    return MouseRegion(
      cursor: (_maximized || _minimized) ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (_maximized || _minimized)
            ? null
            : (d) => setState(() {
                _anim = Duration.zero;
                _position += d.delta;
              }),
        child: ConstellationHeader(
          height: _kHeaderH,
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
            border: _minimized ? null : Border(bottom: BorderSide(color: divColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
                  child: Row(
                    children: [
                      const Icon(Icons.backup_outlined, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Backup masivo',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _headerBadge(context, _ambiente),
                      // La barra minimizada mide 300px: los badges extra no entran.
                      if (!_minimized) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: _configSummary(),
                          child: _headerBadge(context, '${_selected.length} seleccionados'),
                        ),
                        if (_favoriteIds.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _headerBadge(
                            context,
                            '${_favoriteIds.length} ★',
                            color: Colors.amber.withValues(alpha: 0.18),
                            textColor: const Color(0xFF8A6100),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (!_running)
                WindowButton.titleBar(
                  icon: _minimized ? Icons.expand_less_rounded : Icons.remove_rounded,
                  tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                  onTap: _toggleMinimized,
                ),
              WindowButton.titleBar(
                icon: _maximized ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                tooltip: _maximized ? 'Restaurar tamaño  (F11)' : 'Maximizar  (F11)',
                size: 13,
                onTap: () {
                  if (_minimized) {
                    _toggleMinimized();
                  } else {
                    _toggleMaximized();
                  }
                },
              ),
              WindowButton.titleBar(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar  (Esc)',
                isClose: true,
                size: 16,
                onTap: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBadge(BuildContext context, String label, {Color? color, Color? textColor}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? (isDark ? const Color(0xFF222B3D) : const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (textColor ?? cs.primary).withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: textColor ?? (isDark ? Colors.white : const Color(0xFF1E293B)),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _configSummary() {
    final enabled = <String>[];
    if (_config.includeSpec) enabled.add('DDL');
    if (_config.includeBody) enabled.add('body');
    if (_config.includeTableComments) enabled.add('comentarios');
    if (_config.includeGrants) enabled.add('grants');
    if (_config.includeSynonyms) enabled.add('sinónimos');
    return enabled.isEmpty ? 'sin componentes' : enabled.join(', ');
  }

  Widget _buildCatalog(BuildContext context) {
    return FutureBuilder<SchemaMetadata>(
      key: ValueKey(_ambiente),
      future: _metadata,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('No se pudo cargar el esquema: ${snapshot.error}'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = _visibleItems(snapshot.data!);
        final all = [..._schemaItems(snapshot.data!), ..._dynamicItems()];
        final categories = {
          'all': 'Todos',
          'favorites': 'Favoritos',
          ...{for (final item in all) item.category: item.category},
        };
        final categoryCounts = <String, int>{'all': all.length};
        categoryCounts['favorites'] = all.where((item) => _favoriteIds.contains(item.id)).length;
        for (final item in all) {
          categoryCounts[item.category] = (categoryCounts[item.category] ?? 0) + 1;
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            return Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: (_running || _failures.isNotEmpty)
                      ? _buildProgressBanner(context)
                      : const SizedBox(width: double.infinity),
                ),
                Expanded(
                  child: compact
                      ? _buildCompactCatalog(context, items, categories, categoryCounts)
                      : _buildWideCatalog(context, items, categories, categoryCounts),
                ),
                _buildBottomBar(context, compact: compact),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWideCatalog(
    BuildContext context,
    List<BulkBackupItem> items,
    Map<String, String> categories,
    Map<String, int> categoryCounts,
  ) {
    return Row(
      children: [
        SizedBox(width: 220, child: _buildCategories(categories, categoryCounts)),
        Expanded(child: _buildObjectList(context, items)),
        SizedBox(width: 280, child: _selectedPanel()),
      ],
    );
  }

  Widget _buildCompactCatalog(
    BuildContext context,
    List<BulkBackupItem> items,
    Map<String, String> categories,
    Map<String, int> categoryCounts,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(child: AmbienteSelector(value: _ambiente, onChanged: _changeAmbiente)),
              IconButton(
                onPressed: (_running || _refreshing) ? null : _refreshAmbiente,
                tooltip: 'Actualizar ambiente',
                icon: _refreshing
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 40, child: _buildCategories(categories, categoryCounts, horizontal: true))),
            ],
          ),
        ),
        Expanded(child: _buildObjectList(context, items)),
        if (_showCompactSelected) SizedBox(height: 200, child: _selectedPanel()),
      ],
    );
  }

  Widget _buildProgressBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _total == 0 ? 0.0 : (_completed / _total).clamp(0.0, 1.0);
    final isSuccess = _failures.isEmpty;

    final bannerBg = isSuccess
        ? (isDark ? const Color(0xFF132030) : const Color(0xFFEDF5FD))
        : (isDark ? const Color(0xFF2C1518) : const Color(0xFFFDEBEC));
    final bannerBorder = isSuccess
        ? (isDark ? const Color(0xFF1E3A5F) : const Color(0xFFBCD8F6))
        : (isDark ? const Color(0xFF5C242A) : const Color(0xFFF5B5BA));
    final fg = isSuccess
        ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0))
        : (isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828));
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bannerBg,
        border: Border(bottom: BorderSide(color: bannerBorder, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _running
                      ? RotationTransition(
                          key: const ValueKey('running'),
                          turns: _syncIconController,
                          child: Icon(Icons.sync_rounded, size: 16, color: fg),
                        )
                      : Icon(
                          isSuccess ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                          key: const ValueKey('done'),
                          size: 16,
                          color: fg,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _running ? '$_phase de objetos' : (isSuccess ? 'Completado' : 'Finalizado con errores'),
                          style: textTheme.labelMedium?.copyWith(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (_running) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: fg.withValues(alpha: isDark ? 0.2 : 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_completed / $_total (${(progress * 100).toInt()}%)',
                              style: textTheme.labelSmall?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _running
                          ? (_currentName.isNotEmpty ? _currentName : 'Preparando elementos...')
                          : '${_failures.length} objeto(s) no pudieron procesarse',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_running && _failures.isNotEmpty)
                Tooltip(
                  message: _failures.take(5).join('\n'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${_failures.length} fallos',
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (_running) ...[
                const SizedBox(width: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _cancelBackup,
                    hoverColor: cs.error.withValues(alpha: 0.1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.error.withValues(alpha: isDark ? 0.18 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.error.withValues(alpha: isDark ? 0.5 : 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 14, color: cs.error),
                          const SizedBox(width: 4),
                          Text(
                            'Cancelar',
                            style: textTheme.labelMedium?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 10),
            // Track de la barra con resplandor y profundidad
            Container(
              height: 7,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0C1322) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                  width: 0.8,
                ),
                boxShadow: isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                          spreadRadius: -1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, _) {
                    return Stack(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: val.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? const [
                                          Color(0xFF00E5FF),
                                          Color(0xFF3B82F6),
                                          Color(0xFF8B5CF6),
                                          Color(0xFFD946EF),
                                        ]
                                      : const [
                                          Color(0xFF0284C7),
                                          Color(0xFF2563EB),
                                          Color(0xFF7C3AED),
                                          Color(0xFFC026D3),
                                        ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isDark ? const Color(0xFF38BDF8) : const Color(0xFF2563EB))
                                        .withValues(alpha: 0.7),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 0),
                                  ),
                                  BoxShadow(
                                    color: (isDark ? const Color(0xFF8B5CF6) : const Color(0xFF7C3AED))
                                        .withValues(alpha: 0.45),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 0),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Destello luminoso animado (shimmer) que viaja continuamente sobre la barra
                        if (val > 0.03)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: val.clamp(0.0, 1.0),
                                child: AnimatedBuilder(
                                  animation: _shimmerController,
                                  builder: (context, child) {
                                    final shimmerPos = _shimmerController.value;
                                    return Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: LinearGradient(
                                          begin: Alignment(shimmerPos * 3.0 - 1.5, 0),
                                          end: Alignment(shimmerPos * 3.0 - 0.5, 0),
                                          colors: [
                                            Colors.white.withValues(alpha: 0.0),
                                            Colors.white.withValues(alpha: isDark ? 0.65 : 0.45),
                                            Colors.white.withValues(alpha: 0.0),
                                          ],
                                          stops: const [0.0, 0.5, 1.0],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, {required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 860;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141820) : const Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Badge de seleccionados con diseño pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _selected.isNotEmpty
                      ? cs.primary.withValues(alpha: isDark ? 0.2 : 0.12)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selected.isNotEmpty
                        ? cs.primary.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selected.isNotEmpty ? Icons.check_circle_rounded : Icons.checklist_rounded,
                      size: 15,
                      color: _selected.isNotEmpty ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_selected.length} seleccionados',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _selected.isNotEmpty ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!isCompact)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _selected.isEmpty
                              ? 'Elegí objetos del catálogo para incluir en la copia'
                              : _configSummary(),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              if (compact) ...[
                TextButton.icon(
                  onPressed: () => setState(() => _showCompactSelected = !_showCompactSelected),
                  icon: Icon(_showCompactSelected ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 16),
                  label: const Text('Revisar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Botón listas con tooltip
              MenuAnchor(
                alignmentOffset: const Offset(0, 4),
                menuChildren: [
                  MenuItemButton(
                    onPressed: _running ? null : _saveSelectionList,
                    leadingIcon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    child: const Text('Guardar selección actual'),
                  ),
                  MenuItemButton(
                    onPressed: _running ? null : _loadSavedList,
                    leadingIcon: const Icon(Icons.bookmarks_outlined, size: 16),
                    child: const Text('Abrir lista guardada'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: _running ? null : _exportSelectionList,
                    leadingIcon: const Icon(Icons.file_upload_outlined, size: 16),
                    child: const Text('Exportar a JSON'),
                  ),
                  MenuItemButton(
                    onPressed: _running ? null : _importSelectionList,
                    leadingIcon: const Icon(Icons.file_download_outlined, size: 16),
                    child: const Text('Importar desde JSON'),
                  ),
                ],
                builder: (context, controller, child) => Tooltip(
                  message: 'Listas reutilizables',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => controller.isOpen ? controller.close() : controller.open(),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Icon(Icons.bookmarks_outlined, size: 17, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Favoritos batch
              Tooltip(
                message: _selected.isNotEmpty && _selected.every((item) => _favoriteIds.contains(item.id))
                    ? 'Quitar seleccionados de favoritos'
                    : 'Marcar seleccionados como favoritos',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _running ? null : _toggleSelectedFavorites,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Icon(
                      _selected.isNotEmpty && _selected.every((item) => _favoriteIds.contains(item.id))
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 17,
                      color: _selected.isNotEmpty && _selected.every((item) => _favoriteIds.contains(item.id))
                          ? Colors.amber
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Configuración de contenido
              Tooltip(
                message: 'Configurar contenido del backup',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _running ? null : _editConfig,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Icon(Icons.tune_rounded, size: 17, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Botón principal de generar backup con gradiente
              Container(
                decoration: BoxDecoration(
                  gradient: (_running || _selected.isEmpty)
                      ? null
                      : LinearGradient(
                          colors: isDark
                              ? const [Color(0xFF38BDF8), Color(0xFF6366F1)]
                              : const [Color(0xFF0284C7), Color(0xFF4F46E5)],
                        ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: (_running || _selected.isEmpty)
                      ? null
                      : [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF6366F1) : const Color(0xFF0284C7)).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: ElevatedButton.icon(
                  onPressed: (_running || _selected.isEmpty) ? null : () => _metadata.then(_runBackup),
                  icon: Icon(
                    _running ? Icons.hourglass_top_rounded : Icons.cloud_download_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _running ? 'Procesando...' : 'Generar backup',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_running || _selected.isEmpty) ? null : Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: isDark ? const Color(0xFF1E2638) : const Color(0xFFE2E8F0),
                    disabledForegroundColor: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _typeColor(String type) => type == 'PROCEDURE_DYNAMIC' ? const Color(0xFF6B21A8) : (kTypeColors[type] ?? const Color(0xFF6B7280));

  IconData _typeIcon(String type) => type == 'PROCEDURE_DYNAMIC' ? Icons.bolt_rounded : (kTypeIcons[type] ?? Icons.code_rounded);

  Widget _categoryTile(String key, Map<String, String> categories, Map<String, int> categoryCounts) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = categoryCounts[key] ?? 0;
    final selected = _category == key;
    final isFavorites = key == 'favorites';
    final isAll = key == 'all';

    final activeColor = isFavorites ? Colors.amber : cs.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _category = key),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? activeColor.withValues(alpha: 0.16)
                    : activeColor.withValues(alpha: 0.10))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: isDark ? 0.45 : 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: isDark ? 0.25 : 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  isAll
                      ? Icons.grid_view_rounded
                      : isFavorites
                          ? Icons.star_rounded
                          : Icons.folder_rounded,
                  size: 15,
                  color: selected
                      ? activeColor
                      : (isFavorites && count > 0 ? Colors.amber : cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _categoryLabel(categories[key]!),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
                        : cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor.withValues(alpha: isDark ? 0.3 : 0.18)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? activeColor : cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 10,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(
    Map<String, String> categories,
    Map<String, int> categoryCounts, {
    bool horizontal = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    const quickKeys = ['all', 'favorites'];
    final quick = quickKeys.where(categories.containsKey);
    final rest = categories.keys.where((key) => !quickKeys.contains(key));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (horizontal) {
      return ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...quick.map((key) => _categoryTile(key, categories, categoryCounts)),
          ...rest.map((key) => _categoryTile(key, categories, categoryCounts)),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC),
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(child: AmbienteSelector(value: _ambiente, onChanged: _changeAmbiente)),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Actualizar ambiente',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: (_running || _refreshing) ? null : _refreshAmbiente,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C2230) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: _refreshing
                          ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.refresh_rounded, size: 16, color: cs.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _sectionLabel('VISTA RÁPIDA'),
                ...quick.map((key) => _categoryTile(key, categories, categoryCounts)),
                _sectionLabel('TIPOS DE OBJETO'),
                ...rest.map((key) => _categoryTile(key, categories, categoryCounts)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String value) {
    return switch (value) {
      'procedure-dynamic' => 'Procedimientos dinámicos',
      'procedures' => 'Procedimientos',
      'functions' => 'Funciones',
      'packages' => 'Paquetes',
      'types' => 'Types',
      'tables' => 'Tablas',
      'views' => 'Vistas',
      'favorites' => 'Favoritos',
      _ => value == 'all' ? 'Todos los objetos' : value,
    };
  }

  Widget _buildObjectList(BuildContext context, List<BulkBackupItem> items) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Buscador estilizado con botón de acciones de selección
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141923) : const Color(0xFFFAFBFC),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1C2230) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    hintText: 'Filtrar por nombre de objeto...',
                    hintStyle: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.primary),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: _searchController.clear,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.primary, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MenuAnchor(
                alignmentOffset: const Offset(0, 4),
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => setState(() => _selected.addAll(items)),
                    leadingIcon: const Icon(Icons.done_all_rounded, size: 16),
                    child: const Text('Seleccionar visibles'),
                  ),
                  MenuItemButton(
                    onPressed: () => setState(() => _selected.removeAll(items)),
                    leadingIcon: const Icon(Icons.remove_done_rounded, size: 16),
                    child: const Text('Deseleccionar visibles'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: () => setState(_selected.clear),
                    leadingIcon: const Icon(Icons.clear_all_rounded, size: 16),
                    child: const Text('Limpiar toda la selección'),
                  ),
                ],
                builder: (context, controller, child) => Tooltip(
                  message: 'Acciones de selección masiva',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => controller.isOpen ? controller.close() : controller.open(),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C2230) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Icon(Icons.checklist_rtl_rounded, size: 18, color: cs.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Sub-barra con selector "Seleccionar todo" visible y contadores de objetos
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          color: isDark ? const Color(0xFF10141D) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              if (items.isNotEmpty) ...[
                Checkbox(
                  value: items.every((item) => _selected.contains(item))
                      ? true
                      : (items.any((item) => _selected.contains(item)) ? null : false),
                  tristate: true,
                  activeColor: cs.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: _running
                      ? null
                      : (bool? val) {
                          setState(() {
                            if (val == true) {
                              _selected.addAll(items);
                            } else {
                              _selected.removeAll(items);
                            }
                          });
                        },
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _running
                      ? null
                      : () {
                          setState(() {
                            final allSelected = items.every((item) => _selected.contains(item));
                            if (allSelected) {
                              _selected.removeAll(items);
                            } else {
                              _selected.addAll(items);
                            }
                          });
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      items.every((item) => _selected.contains(item))
                          ? 'Deseleccionar todo'
                          : 'Seleccionar todo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${items.length})',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ] else
                Text(
                  '0 objetos encontrados',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              if (_selected.isNotEmpty) ...[
                Text(
                  '${_selected.length} seleccionados',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _running ? null : () => setState(_selected.clear),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Limpiar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.error,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(
                  icon: _searchController.text.isEmpty && _category == 'favorites'
                      ? Icons.star_border_rounded
                      : Icons.search_off_rounded,
                  message: _searchController.text.isNotEmpty
                      ? 'Sin resultados para "${_searchController.text}"'
                      : _category == 'favorites'
                          ? 'Marcá objetos con la estrella para verlos acá'
                          : 'No hay objetos en esta categoría',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final color = _typeColor(item.type);
                    final isFavorite = _favoriteIds.contains(item.id);
                    final isSelected = _selected.contains(item);
                    return Draggable<BulkBackupItem>(
                      data: item,
                      maxSimultaneousDrags: _running ? 0 : 1,
                      feedback: _dragFeedback(item, color, cs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _running
                              ? null
                              : () => setState(() => isSelected ? _selected.remove(item) : _selected.add(item)),
                            child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                      ? cs.primary.withValues(alpha: 0.16)
                                      : cs.primary.withValues(alpha: 0.08))
                                  : (isDark
                                      ? const Color(0xFF161B26)
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary.withValues(alpha: isDark ? 0.45 : 0.35)
                                    : (isDark
                                        ? const Color(0xFF222838)
                                        : const Color(0xFFE5E7EB)),
                                width: isSelected ? 1.2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: cs.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: _running
                                      ? null
                                      : (value) => setState(() => value == true ? _selected.add(item) : _selected.remove(item)),
                                ),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(_typeIcon(item.type), size: 16, color: color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Tooltip(
                                        message: item.name,
                                        child: Text(
                                          item.name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.type,
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                          if (item.owner.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Icon(Icons.shield_outlined, size: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                item.owner,
                                                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _running ? null : () => _toggleItemFavorite(item),
                                  tooltip: isFavorite ? 'Quitar de favoritos' : 'Agregar a favoritos',
                                  icon: Icon(
                                    isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 18,
                                    color: isFavorite ? Colors.amber : cs.outline.withValues(alpha: 0.6),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                              ],
                            ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _dragFeedback(BulkBackupItem item, Color color, ColorScheme cs) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.backup_outlined, size: 16, color: color),
              const SizedBox(width: 8),
              Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 15, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(icon, size: 26, color: cs.primary.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedPanel() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<BulkBackupItem>(
      onAcceptWithDetails: (details) {
        if (_running) return;
        setState(() => _selected.add(details.data));
      },
      builder: (context, candidateData, rejectedData) {
        final isDropActive = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isDropActive
                ? cs.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : (isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC)),
            border: Border(
              left: BorderSide(
                color: isDropActive ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                width: isDropActive ? 2 : 1,
              ),
            ),
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del panel lateral
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Por respaldar (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                if (_selected.isNotEmpty)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _running ? null : () => setState(_selected.clear),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        'Vaciar',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Organizados automáticamente por categoría.',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: _selected.isEmpty
                ? _buildEmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Seleccioná objetos de la lista central para agregarlos aquí',
                  )
                : Builder(
                    builder: (context) {
                      final grouped = <String, List<BulkBackupItem>>{};
                      for (final item in _selected) {
                        grouped.putIfAbsent(item.category, () => []).add(item);
                      }
                      final sortedKeys = grouped.keys.toList()..sort();
                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        children: [
                          for (final key in sortedKeys) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                              child: Row(
                                children: [
                                  Text(
                                    _categoryLabel(key).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${grouped[key]!.length}',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...grouped[key]!.map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1B212D) : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF262E3D) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    leading: Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(top: 2),
                                      decoration: BoxDecoration(
                                        color: _typeColor(item.type),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    minLeadingWidth: 10,
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: _favoriteIds.contains(item.id)
                                        ? const Text('★ favorito', style: TextStyle(fontSize: 9.5, color: Colors.amber, fontWeight: FontWeight.w600))
                                        : null,
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 15),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                      onPressed: _running ? null : () => setState(() => _selected.remove(item)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
          ),
        );
      },
    );
  }
}
