import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/batch_transfer_result.dart';
import '../models/bulk_backup_item.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../services/backup_service.dart';
import '../services/batch_transfer_service.dart';
import '../services/bulk_backup_selection_service.dart';
import '../services/bulk_backup_service.dart';
import '../services/schema_service.dart';
import '../services/sirweb_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/constellation_background.dart';
import '../widgets/floating_window.dart';
import '../widgets/object_source_page.dart';

/// Abre el módulo de transferencia por lote como ventana flotante.
VoidCallback showBatchTransferWindow(
  BuildContext context, {
  required String ambiente,
}) {
  return showFloatingWindow(
    context,
    (close) => BatchTransferPage(ambiente: ambiente, onClose: close),
  );
}

enum _Phase { selecting, confirming, running }

class BatchTransferPage extends StatefulWidget {
  final String ambiente;
  final VoidCallback? onClose;

  const BatchTransferPage({super.key, required this.ambiente, this.onClose});

  @override
  State<BatchTransferPage> createState() => _BatchTransferPageState();
}

class _BatchTransferPageState extends State<BatchTransferPage>
    with TickerProviderStateMixin {
  static const double _kMinW = 820;
  static const double _kHeaderH = 44;

  late String _sourceAmbiente;
  late Future<SchemaMetadata> _metadata;
  final _searchController = TextEditingController();
  final _selected = <BulkBackupItem>{};
  var _category = 'all';
  final _targetAmbientes = <String>{};
  var _transferGrants = false;
  var _transferSynonyms = false;
  var _phase = _Phase.selecting;

  bool _loadingDynamic = false;
  int _dynamicLoadId = 0;
  final _dynamicService = SirwebService();
  var _dynamicProcedures = <Procedimiento>[];
  SchemaMetadata? _lastMetadata;
  bool _refreshingObjects = false;

  final _service = BatchTransferService();
  bool _running = false;
  bool _cancelRequested = false;
  String _currentName = '';
  final _results = <BatchTransferResult>[];
  int _totalPairs = 0;
  String? _lastBackupDirectory;

  // Estado para el resumen interactivo de confirmación
  final _confirmSearchController = TextEditingController();
  String _confirmCategoryFilter = 'all';

  // Servicio de plantillas/listas reutilizables
  final _selectionService = BulkBackupSelectionService();

  // Estado para el filtrado en la fase de ejecución
  final _executionSearchController = TextEditingController();
  String _executionTargetFilter = 'all';

  // ── Geometría de ventana flotante ──────────────────────────────────────────
  Offset _position = Offset.zero;
  double? _winW;
  double? _winH;
  bool _maximized = false;
  bool _minimized = false;
  int? _slot;
  Duration _anim = Duration.zero;

  late final AnimationController _syncIconController;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _syncIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _sourceAmbiente = widget.ambiente;
    _metadata = SchemaService.instance.getMetadata(ambiente: _sourceAmbiente);
    procedimientosProvider.setAmbiente(_sourceAmbiente);
    unawaited(_loadDynamicProcedures());
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _syncIconController.dispose();
    _shimmerController.dispose();
    _searchController.dispose();
    _confirmSearchController.dispose();
    _executionSearchController.dispose();
    FloatingWindowSlots.release(_slot);
    super.dispose();
  }

  Future<void> _loadDynamicProcedures() async {
    final loadId = ++_dynamicLoadId;
    setState(() => _loadingDynamic = true);
    try {
      final procedures = await _dynamicService.listarTodosProcedimientos(
        estado: null,
        ambiente: _sourceAmbiente,
      );
      if (!mounted || loadId != _dynamicLoadId) return;
      setState(() => _dynamicProcedures = procedures);
    } catch (error) {
      if (mounted) {
        AppToast.error(
          'No se pudieron cargar los procedimientos dinámicos: $error',
        );
      }
    } finally {
      if (mounted && loadId == _dynamicLoadId) {
        setState(() => _loadingDynamic = false);
      }
    }
  }

  Future<void> _changeSource(String value) async {
    if (value == _sourceAmbiente) return;
    setState(() {
      _sourceAmbiente = value;
      _selected.clear();
      _targetAmbientes.remove(value);
      _category = 'all';
      _searchController.clear();
      _dynamicProcedures = [];
      _metadata = SchemaService.instance.getMetadata(ambiente: value);
    });
    procedimientosProvider.setAmbiente(value);
    await _loadDynamicProcedures();
  }

  // Las tablas no admiten CREATE OR REPLACE en Oracle: quedan fuera de este módulo.
  List<BulkBackupItem> _schemaItems(SchemaMetadata metadata) => [
    ...metadata.views.map(
      (name) => BulkBackupItem(
        name: name.trim(),
        type: 'VIEW',
        owner: (metadata.viewOwners[name] ?? metadata.owner).trim(),
        source: BulkBackupSource.schema,
      ),
    ),
    ...metadata.objects.map(
      (object) => BulkBackupItem(
        name: object.name.trim(),
        type: object.type.trim(),
        owner: (object.owner.isEmpty ? metadata.owner : object.owner).trim(),
        source: BulkBackupSource.schema,
      ),
    ),
  ];

  List<BulkBackupItem> _dynamicItems() => _dynamicProcedures
      .map(
        (procedure) => BulkBackupItem(
          name: procedure.cdProcedimiento.trim(),
          type: 'PROCEDURE_DYNAMIC',
          source: BulkBackupSource.dynamicProcedure,
          procedimiento: procedure,
        ),
      )
      .toList();

  List<BulkBackupItem> _visibleItems(SchemaMetadata metadata) {
    final query = _searchController.text.trim().toUpperCase();
    final all = [..._schemaItems(metadata), ..._dynamicItems()];
    return all
        .where(
          (item) =>
              (_category == 'all' ||
                  (_category == 'selected'
                      ? _selected.contains(item)
                      : item.category == _category)) &&
              (query.isEmpty || item.name.toUpperCase().contains(query)),
        )
        .toList();
  }

  // Universo de coincidencia para el pegado de nombres: categoría activa, sin filtro de búsqueda.
  List<BulkBackupItem> _categoryPool() {
    final metadata = _lastMetadata;
    if (metadata == null) return const [];
    final all = [..._schemaItems(metadata), ..._dynamicItems()];
    return all
        .where(
          (item) =>
              _category == 'all' ||
              _category == 'selected' ||
              item.category == _category,
        )
        .toList();
  }

  Future<void> _refreshObjects() async {
    if (_refreshingObjects || _running) return;
    setState(() {
      _refreshingObjects = true;
      _metadata = SchemaService.instance.refreshAmbiente(_sourceAmbiente);
    });
    try {
      await Future.wait([_metadata, _loadDynamicProcedures()]);
      if (mounted) {
        AppToast.success('Catálogo de $_sourceAmbiente actualizado');
      }
    } catch (error) {
      if (mounted) {
        AppToast.error('No se pudo actualizar el catálogo: $error');
      }
    } finally {
      if (mounted) setState(() => _refreshingObjects = false);
    }
  }

  Future<void> _pasteNamesDialog() async {
    // 1. Asegurar que metadata esté disponible (si aún está cargando o es null)
    SchemaMetadata? metadata = _lastMetadata;
    if (metadata == null) {
      try {
        metadata = await _metadata;
        _lastMetadata = metadata;
      } catch (_) {}
    }
    metadata ??= SchemaService.instance.getCached(ambiente: _sourceAmbiente);

    // 2. Si los procedimientos dinámicos aún están cargando, esperar a que finalice
    if (_loadingDynamic) {
      while (_loadingDynamic && mounted) {
        await Future.delayed(const Duration(milliseconds: 60));
      }
    } else if (_dynamicProcedures.isEmpty) {
      await _loadDynamicProcedures();
    }

    final activePool = _categoryPool();
    final allPool = [
      if (metadata != null) ..._schemaItems(metadata),
      ..._dynamicItems(),
    ];

    final categoryLabels = {
      'procedure-dynamic': 'Reglas dinámicas',
      'views': 'Vistas',
      'procedures': 'Procedimientos',
      'functions': 'Funciones',
      'packages': 'Paquetes',
      'types': 'Types',
    };
    final currentCatLabel = _category == 'all'
        ? 'Todos los objetos'
        : (categoryLabels[_category] ?? _category);

    if (!mounted) return;
    final selectedMatches = await showFloatingDialog<List<BulkBackupItem>>(
      context,
      (dialogContext, close) => _PasteNamesDialogContent(
        sourceAmbiente: _sourceAmbiente,
        categoryLabel: currentCatLabel,
        activeCategory: _category,
        activePool: activePool,
        allPool: allPool,
        close: close,
      ),
    );

    if (selectedMatches == null || selectedMatches.isEmpty) return;
    if (!mounted) return;
    setState(() => _selected.addAll(selectedMatches));
    AppToast.success(
      '${selectedMatches.length} elementos agregados a la selección',
    );
  }

  Future<void> _saveSelectionList() async {
    if (_selected.isEmpty) {
      AppToast.warning('Seleccioná al menos un objeto para guardar la lista');
      return;
    }
    final name = await _askListName();
    if (name == null) return;
    await _selectionService.saveList(
      BulkBackupSelectionList(
        name: name,
        savedAt: DateTime.now().toUtc(),
        savedFromAmbiente: _sourceAmbiente,
        items: _selected.toList(),
        config: const BulkBackupConfig(),
      ),
    );
    if (mounted) AppToast.success('Lista "$name" guardada');
  }

  Future<void> _loadSavedList() async {
    final lists = await _selectionService.getLists();
    if (!mounted) return;
    if (lists.isEmpty) {
      AppToast.warning('No hay listas guardadas en el sistema');
      return;
    }
    final selected = await showFloatingDialog<BulkBackupSelectionList>(
      context,
      (dialogContext, close) => AlertDialog(
        title: const Text('Cargar lista guardada'),
        content: SizedBox(
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: lists.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final list = lists[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(list.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${list.items.length} objetos · Guardado desde ${list.savedFromAmbiente}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => close(list),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected != null) {
      await _applySavedList(selected);
    }
  }

  Future<void> _applySavedList(BulkBackupSelectionList list) async {
    SchemaMetadata? metadata = _lastMetadata;
    if (metadata == null) {
      try {
        metadata = await _metadata;
        _lastMetadata = metadata;
      } catch (_) {}
    }
    metadata ??= SchemaService.instance.getCached(ambiente: _sourceAmbiente);

    final catalog = [
      if (metadata != null) ..._schemaItems(metadata),
      ..._dynamicItems(),
    ];
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
      _selected.addAll(resolved);
    });
    if (missing.isNotEmpty) {
      AppToast.warning(
        'Lista "${list.name}": ${resolved.length} agregados; ${missing.length} no disponibles en $_sourceAmbiente',
        duration: const Duration(seconds: 5),
      );
    } else {
      AppToast.success(
        '${resolved.length} objetos cargados desde "${list.name}"',
      );
    }
  }

  Future<String?> _askListName({String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final name = await showFloatingDialog<String>(
      context,
      (dialogContext, close) => AlertDialog(
        title: const Text('Guardar lista de transferencia'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la lista',
            hintText: 'Ej. Reglas críticas',
          ),
          onSubmitted: (value) => close(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => close(null),
            child: const Text('Cancelar'),
          ),
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

  void _toggleItem(BulkBackupItem item, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selected.add(item);
      } else {
        _selected.remove(item);
      }
    });
  }

  void _continueToConfirm() {
    if (_selected.isEmpty) {
      AppToast.warning('Seleccioná al menos un elemento para transferir');
      return;
    }
    setState(() => _phase = _Phase.confirming);
  }

  void _backToSelection() => setState(() => _phase = _Phase.selecting);

  void _resetToNewTransfer() {
    setState(() {
      _phase = _Phase.selecting;
      _results.clear();
      _running = false;
      _cancelRequested = false;
      _currentName = '';
      _lastBackupDirectory = null;
    });
  }

  Future<void> _start({required bool withBackup}) async {
    if (_targetAmbientes.isEmpty) {
      AppToast.warning('Seleccioná al menos un ambiente destino');
      return;
    }
    String? backupDir;
    if (withBackup) {
      final backup = await _backupTargets();
      if (!backup.ok) {
        AppToast.errorWithDetail(
          'No se pudo completar el respaldo previo: la transferencia fue cancelada',
          backup.failures.join('\n'),
          source: 'Transferencia',
        );
        return;
      }
      backupDir = backup.directory;
      if (backupDir != null) {
        AppToast.successWithAction(
          'Respaldo previo generado con éxito',
          detail: backupDir,
          actionLabel: 'Abrir ubicación',
          onAction: () => unawaited(BackupService.revealInExplorer(backupDir!)),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _lastBackupDirectory = backupDir;
      _phase = _Phase.running;
      _running = true;
      _cancelRequested = false;
      _results.clear();
      _totalPairs = _selected.length * _targetAmbientes.length;
    });

    await _service.run(
      items: _selected.toList(),
      sourceAmbiente: _sourceAmbiente,
      targetAmbientes: _targetAmbientes.toList(),
      cdUsuario: procedimientosProvider.cdUsuario,
      transferGrants: _transferGrants,
      transferSynonyms: _transferSynonyms,
      isCancelled: () => _cancelRequested,
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _currentName = '${result.item.name} → ${result.targetAmbiente}';
          final index = _results.indexWhere((r) => r.key == result.key);
          if (index >= 0) {
            _results[index] = result;
          } else {
            _results.add(result);
          }
        });
      },
    );

    if (!mounted) return;
    final finishedList = _results.where((r) => !r.isRunning).toList();
    final errors = finishedList.where((r) => r.isError).length;
    final success = finishedList.where((r) => r.isSuccess).length;
    setState(() => _running = false);

    if (_cancelRequested) {
      AppToast.warning(
        'Transferencia cancelada por el usuario ($success completados)',
      );
    } else if (errors == 0) {
      AppToast.success(
        'Transferencia finalizada: $success elementos actualizados',
      );
    } else {
      AppToast.warning(
        'Transferencia finalizada: $success exitosos, $errors con error',
      );
    }
  }

  Future<({bool ok, String? directory, List<String> failures})>
  _backupTargets() async {
    final basePath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Carpeta para respaldos previos de seguridad',
    );
    if (basePath == null) {
      return (
        ok: false,
        directory: null,
        failures: const ['Operación cancelada por el usuario'],
      );
    }

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final failures = <String>[];
    String? lastDirectory;

    for (final target in _targetAmbientes) {
      final safeTarget = target.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetDir = Directory(
        '$basePath/PRE_TRANSFER_${safeTarget}_$stamp',
      );
      final scripts = <String, String>{};
      final existingItems = <BulkBackupItem>[];

      for (final item in _selected) {
        try {
          if (item.source == BulkBackupSource.dynamicProcedure) {
            final proc = await _dynamicService.obtenerProcedimiento(
              item.name,
              ambiente: target,
            );
            scripts[item.id] = BulkBackupService.buildDynamicScript(
              proc,
              target,
              procedimientosProvider.cdUsuario,
            );
            existingItems.add(item);
          } else {
            final source = await SchemaService.instance.getObjectSource(
              item.name,
              item.type,
              ambiente: target,
            );
            if (source.spec.isNotEmpty) {
              scripts[item.id] = BulkBackupService.buildSchemaScript(
                item: item,
                ambiente: target,
                spec: source.spec,
                body: source.body,
              );
              existingItems.add(item);
            }
          }
        } catch (_) {
          // El objeto no existía en el destino: no es error de backup
        }
      }

      if (scripts.isNotEmpty) {
        final writeResult = await BulkBackupService.writeAll(
          directory: targetDir,
          ambiente: target,
          items: existingItems,
          scripts: scripts,
        );
        lastDirectory = writeResult.directory;
        for (final fail in writeResult.failures) {
          failures.add('$target - ${fail.name}: ${fail.error}');
        }
      }
    }

    return (ok: failures.isEmpty, directory: lastDirectory, failures: failures);
  }

  void _cancel() {
    if (_running) {
      setState(() => _cancelRequested = true);
    }
  }

  void _close() {
    if (_running) {
      AppToast.warning(
        'Hay una transferencia en curso. Cancelala primero antes de cerrar.',
      );
      return;
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _toggleMinimized() {
    setState(() {
      _anim = const Duration(milliseconds: 220);
      if (_minimized) {
        _minimized = false;
        FloatingWindowSlots.release(_slot);
        _slot = null;
      } else {
        _minimized = true;
        _slot = FloatingWindowSlots.take();
      }
    });
  }

  void _toggleMaximized() {
    setState(() {
      _anim = const Duration(milliseconds: 200);
      _maximized = !_maximized;
    });
  }

  Color _typeColor(String type) => type == 'PROCEDURE_DYNAMIC'
      ? const Color(0xFF9333EA)
      : (kTypeColors[type] ?? const Color(0xFF6B7280));

  IconData _typeIcon(String type) => type == 'PROCEDURE_DYNAMIC'
      ? Icons.bolt_rounded
      : (kTypeIcons[type] ?? Icons.code_rounded);

  // ── Build principal con marco de ventana flotante ──────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final gripColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.18,
    );

    if (_maximized) {
      _winW = (size.width - 48).clamp(320.0, size.width);
      _winH = (size.height - 48).clamp(280.0, size.height);
    } else {
      _winW ??= (size.width * 0.78).clamp(_kMinW, 1140.0);
      _winH ??= (size.height * 0.82).clamp(520.0, 840.0);
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
      left = ((size.width - w) / 2 + _position.dx).clamp(
        0.0,
        (size.width - w).clamp(0.0, double.infinity),
      );
      top = ((size.height - h) / 2 + _position.dy).clamp(
        0.0,
        (size.height - h).clamp(0.0, double.infinity),
      );
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
                    borderRadius: BorderRadius.circular(
                      _maximized ? 6 : (_minimized ? 8 : 12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.5 : 0.18,
                        ),
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
                                _buildStepBreadcrumbs(context, isDark, cs),
                                Expanded(
                                  child: _buildBody(context, isDark, cs),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            width: w,
                            child: _buildHeader(context, isDark, cs),
                          ),
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
                      _winW = (_winW! + d.delta.dx).clamp(
                        _kMinW,
                        size.width - 40,
                      );
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
                      _winH = (_winH! + d.delta.dy).clamp(
                        520.0,
                        size.height - 40,
                      );
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
                      _winW = (_winW! + d.delta.dx).clamp(
                        _kMinW,
                        size.width - 40,
                      );
                      _winH = (_winH! + d.delta.dy).clamp(
                        520.0,
                        size.height - 40,
                      );
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

  // ── Barra de título arrastrable con controles nativos ──────────────────────

  Widget _buildHeader(BuildContext context, bool isDark, ColorScheme cs) {
    final divColor = cs.outlineVariant.withValues(alpha: 0.6);
    final sourceColor = AmbienteSelector.colorForAmbiente(_sourceAmbiente);

    return MouseRegion(
      cursor: (_maximized || _minimized)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.grab,
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
            border: _minimized
                ? null
                : Border(bottom: BorderSide(color: divColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _minimized ? _toggleMinimized : _toggleMaximized,
                  child: Row(
                    children: [
                      Icon(Icons.move_up_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Transferencia por lote',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _headerBadge(
                        context,
                        _minimized
                            ? _sourceAmbiente
                            : 'Origen: $_sourceAmbiente',
                        color: sourceColor.withValues(
                          alpha: isDark ? 0.22 : 0.12,
                        ),
                        textColor: sourceColor,
                      ),
                      if (!_minimized) ...[
                        const SizedBox(width: 6),
                        _headerBadge(
                          context,
                          '${_selected.length} seleccionados',
                          color: _selected.isNotEmpty
                              ? cs.primary.withValues(
                                  alpha: isDark ? 0.22 : 0.12,
                                )
                              : null,
                          textColor: _selected.isNotEmpty ? cs.primary : null,
                        ),
                        if (_targetAmbientes.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: _headerBadge(
                              context,
                              '→ ${_targetAmbientes.join(', ')}',
                              color: Colors.blue.withValues(
                                alpha: isDark ? 0.22 : 0.12,
                              ),
                              textColor: Colors.blue,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (!_running)
                WindowButton.titleBar(
                  icon: _minimized
                      ? Icons.expand_less_rounded
                      : Icons.remove_rounded,
                  tooltip: _minimized ? 'Restaurar' : 'Minimizar',
                  onTap: _toggleMinimized,
                ),
              WindowButton.titleBar(
                icon: _maximized
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                tooltip: _maximized
                    ? 'Restaurar tamaño (F11)'
                    : 'Maximizar (F11)',
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
                tooltip: 'Cerrar (Esc)',
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

  Widget _headerBadge(
    BuildContext context,
    String label, {
    Color? color,
    Color? textColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            color ??
            (isDark ? const Color(0xFF222B3D) : const Color(0xFFE2E8F0)),
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

  // ── Barra de pasos interactiva (Breadcrumbs) ───────────────────────────────

  Widget _buildStepBreadcrumbs(
    BuildContext context,
    bool isDark,
    ColorScheme cs,
  ) {
    if (_minimized) return const SizedBox.shrink();

    Widget stepItem({
      required _Phase phase,
      required String number,
      required String title,
      required IconData icon,
    }) {
      final active = _phase == phase;
      final completed = _phase.index > phase.index;
      final color = active
          ? cs.primary
          : (completed
                ? Colors.teal
                : cs.onSurfaceVariant.withValues(alpha: 0.6));

      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: (_running || active)
            ? null
            : () {
                if (phase == _Phase.selecting) {
                  _backToSelection();
                } else if (phase == _Phase.confirming && _selected.isNotEmpty) {
                  setState(() => _phase = _Phase.confirming);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? cs.primary
                      : (completed
                            ? Colors.teal.withValues(alpha: 0.2)
                            : cs.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              )),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: completed
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.teal,
                      )
                    : Text(
                        number,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : color,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            stepItem(
              phase: _Phase.selecting,
              number: '1',
              title: 'Selección de objetos',
              icon: Icons.checklist_rounded,
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            stepItem(
              phase: _Phase.confirming,
              number: '2',
              title: 'Destinos y confirmación',
              icon: Icons.alt_route_rounded,
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            stepItem(
              phase: _Phase.running,
              number: '3',
              title: 'Ejecución y registro por lote',
              icon: Icons.terminal_rounded,
            ),
            if (_phase == _Phase.running) ...[
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _running
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _running
                        ? Colors.blue.withValues(alpha: 0.4)
                        : Colors.green.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_running)
                      RotationTransition(
                        turns: _syncIconController,
                        child: const Icon(
                          Icons.sync_rounded,
                          size: 12,
                          color: Colors.blue,
                        ),
                      )
                    else
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: Colors.green,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _running ? 'Procesando lote...' : 'Lote completado',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _running ? Colors.blue : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, ColorScheme cs) {
    return switch (_phase) {
      _Phase.selecting => _buildSelection(context, isDark, cs),
      _Phase.confirming => _buildConfirm(context, isDark, cs),
      _Phase.running => _buildExecution(context, isDark, cs),
    };
  }

  // ── Fase 1: Catálogo y selección ───────────────────────────────────────────

  Widget _buildSelection(BuildContext context, bool isDark, ColorScheme cs) {
    return FutureBuilder<SchemaMetadata>(
      key: ValueKey(_sourceAmbiente),
      future: _metadata,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: Colors.red,
                ),
                const SizedBox(height: 8),
                Text(
                  'No se pudo cargar el esquema de $_sourceAmbiente: ${snapshot.error}',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _metadata = SchemaService.instance.getMetadata(
                      ambiente: _sourceAmbiente,
                    );
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cargando catálogo de $_sourceAmbiente...',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final items = _visibleItems(snapshot.data!);
        _lastMetadata = snapshot.data!;
        final all = [..._schemaItems(snapshot.data!), ..._dynamicItems()];
        final categories = {
          'all': 'Todos los objetos',
          'procedure-dynamic': 'Reglas dinámicas',
          'views': 'Vistas',
          'procedures': 'Procedimientos',
          'functions': 'Funciones',
          'packages': 'Paquetes',
          'types': 'Types',
        };

        final categoryCounts = <String, int>{
          'all': all.length,
          'procedure-dynamic': _dynamicProcedures.length,
          'views': snapshot.data!.views.length,
          'procedures': snapshot.data!.objects
              .where((o) => o.type == 'PROCEDURE')
              .length,
          'functions': snapshot.data!.objects
              .where((o) => o.type == 'FUNCTION')
              .length,
          'packages': snapshot.data!.objects
              .where((o) => o.type == 'PACKAGE')
              .length,
          'types': snapshot.data!.objects.where((o) => o.type == 'TYPE').length,
        };

        final selectedCounts = <String, int>{
          'all': _selected.length,
          'selected': _selected.length,
          'procedure-dynamic': _selected
              .where((i) => i.category == 'procedure-dynamic')
              .length,
          'views': _selected.where((i) => i.category == 'views').length,
          'procedures': _selected
              .where((i) => i.category == 'procedures')
              .length,
          'functions': _selected.where((i) => i.category == 'functions').length,
          'packages': _selected.where((i) => i.category == 'packages').length,
          'types': _selected.where((i) => i.category == 'types').length,
        };

        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: _buildCategoriesSidebar(
                      categories,
                      categoryCounts,
                      selectedCounts,
                      isDark,
                      cs,
                    ),
                  ),
                  Expanded(child: _buildObjectList(context, items, isDark, cs)),
                ],
              ),
            ),
            _buildSelectionBottomBar(context, isDark, cs),
          ],
        );
      },
    );
  }

  Widget _buildCategoriesSidebar(
    Map<String, String> categories,
    Map<String, int> categoryCounts,
    Map<String, int> selectedCounts,
    bool isDark,
    ColorScheme cs,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC),
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AMBIENTE ORIGEN',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    if (_loadingDynamic || _refreshingObjects)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    Tooltip(
                      message: 'Actualizar catálogo',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: (_refreshingObjects || _running)
                            ? null
                            : _refreshObjects,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: (_refreshingObjects || _running)
                                ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AmbienteSelector(
                  value: _sourceAmbiente,
                  onChanged: _changeSource,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _sidebarSectionLabel('VISTA GENERAL', cs),
                _sidebarCategoryTile(
                  'all',
                  categories['all']!,
                  categoryCounts['all'] ?? 0,
                  Icons.grid_view_rounded,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['all'] ?? 0,
                ),
                _sidebarCategoryTile(
                  'selected',
                  'Solo seleccionados',
                  _selected.length,
                  Icons.check_circle_rounded,
                  isDark,
                  cs,
                  selectedCount: _selected.length,
                  isSpecialSelectionTile: true,
                ),
                _sidebarSectionLabel('REGLAS DE NEGOCIO', cs),
                _sidebarCategoryTile(
                  'procedure-dynamic',
                  categories['procedure-dynamic']!,
                  categoryCounts['procedure-dynamic'] ?? 0,
                  Icons.bolt_rounded,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['procedure-dynamic'] ?? 0,
                ),
                _sidebarSectionLabel('OBJETOS DE ESQUEMA', cs),
                _sidebarCategoryTile(
                  'views',
                  categories['views']!,
                  categoryCounts['views'] ?? 0,
                  Icons.visibility_outlined,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['views'] ?? 0,
                ),
                _sidebarCategoryTile(
                  'procedures',
                  categories['procedures']!,
                  categoryCounts['procedures'] ?? 0,
                  Icons.code_rounded,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['procedures'] ?? 0,
                ),
                _sidebarCategoryTile(
                  'functions',
                  categories['functions']!,
                  categoryCounts['functions'] ?? 0,
                  Icons.functions_rounded,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['functions'] ?? 0,
                ),
                _sidebarCategoryTile(
                  'packages',
                  categories['packages']!,
                  categoryCounts['packages'] ?? 0,
                  Icons.inventory_2_outlined,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['packages'] ?? 0,
                ),
                _sidebarCategoryTile(
                  'types',
                  categories['types']!,
                  categoryCounts['types'] ?? 0,
                  Icons.data_object_outlined,
                  isDark,
                  cs,
                  selectedCount: selectedCounts['types'] ?? 0,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tablas excluidas por restricción DDL en Oracle',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarSectionLabel(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
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
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarCategoryTile(
    String key,
    String label,
    int count,
    IconData icon,
    bool isDark,
    ColorScheme cs, {
    int selectedCount = 0,
    bool isSpecialSelectionTile = false,
  }) {
    final selected = _category == key;
    final activeColor = isSpecialSelectionTile ? Colors.teal : cs.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _category = key),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: isDark ? 0.18 : 0.10)
                : (isSpecialSelectionTile && selectedCount > 0
                      ? Colors.teal.withValues(alpha: isDark ? 0.10 : 0.06)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: isDark ? 0.45 : 0.3)
                  : (isSpecialSelectionTile && selectedCount > 0
                        ? Colors.teal.withValues(alpha: isDark ? 0.25 : 0.2)
                        : Colors.transparent),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? activeColor
                    : (isSpecialSelectionTile && selectedCount > 0
                          ? Colors.teal
                          : cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ||
                            (isSpecialSelectionTile && selectedCount > 0)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: selected
                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
                        : (isSpecialSelectionTile && selectedCount > 0
                              ? (isDark
                                    ? Colors.teal.shade300
                                    : Colors.teal.shade800)
                              : cs.onSurfaceVariant),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selectedCount > 0 &&
                  !isSpecialSelectionTile &&
                  key != 'all') ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: isDark ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_rounded,
                        size: 10,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$selectedCount',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: isDark ? 0.3 : 0.18)
                      : (isSpecialSelectionTile && selectedCount > 0
                            ? Colors.teal.withValues(alpha: isDark ? 0.3 : 0.18)
                            : cs.surfaceContainerHighest.withValues(
                                alpha: 0.6,
                              )),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? activeColor
                        : (isSpecialSelectionTile && selectedCount > 0
                              ? Colors.teal
                              : cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObjectList(
    BuildContext context,
    List<BulkBackupItem> items,
    bool isDark,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        // Buscador superior
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141923) : const Color(0xFFFAFBFC),
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    hintText: 'Filtrar por nombre de regla u objeto...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: _searchController.clear,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: _category == 'selected'
                    ? 'Ver todos los objetos de la categoría'
                    : 'Filtrar para ver solo los seleccionados (${_selected.length})',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      _category = _category == 'selected' ? 'all' : 'selected';
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _category == 'selected'
                          ? Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12)
                          : (isDark ? const Color(0xFF1C2230) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _category == 'selected'
                            ? Colors.teal
                            : cs.outlineVariant.withValues(alpha: 0.5),
                        width: _category == 'selected' ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _category == 'selected'
                              ? Icons.check_circle_rounded
                              : Icons.checklist_rounded,
                          size: 15,
                          color: _category == 'selected'
                              ? Colors.teal
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Solo seleccionados',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _category == 'selected'
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _category == 'selected'
                                ? Colors.teal
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _category == 'selected'
                                ? Colors.teal
                                : cs.surfaceContainerHighest.withValues(
                                    alpha: 0.8,
                                  ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_selected.length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _category == 'selected'
                                  ? Colors.white
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => setState(() => _selected.addAll(items)),
                    leadingIcon: const Icon(Icons.done_all_rounded, size: 16),
                    child: const Text('Seleccionar visibles'),
                  ),
                  MenuItemButton(
                    onPressed: () => setState(() => _selected.removeAll(items)),
                    leadingIcon: const Icon(
                      Icons.remove_done_rounded,
                      size: 16,
                    ),
                    child: const Text('Deseleccionar visibles'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: _pasteNamesDialog,
                    leadingIcon: const Icon(
                      Icons.playlist_add_rounded,
                      size: 16,
                    ),
                    child: const Text('Pegar lista de nombres...'),
                  ),
                  MenuItemButton(
                    onPressed: _saveSelectionList,
                    leadingIcon: const Icon(
                      Icons.bookmark_add_outlined,
                      size: 16,
                    ),
                    child: const Text('Guardar selección como lista...'),
                  ),
                  MenuItemButton(
                    onPressed: _loadSavedList,
                    leadingIcon: const Icon(Icons.bookmarks_outlined, size: 16),
                    child: const Text('Cargar lista guardada...'),
                  ),
                  const Divider(height: 1),
                  MenuItemButton(
                    onPressed: () => setState(_selected.clear),
                    leadingIcon: const Icon(Icons.clear_all_rounded, size: 16),
                    child: const Text('Limpiar selección'),
                  ),
                ],
                builder: (context, controller, child) => Tooltip(
                  message: 'Acciones de selección',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C2230) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Icon(
                        Icons.checklist_rtl_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sub-barra con selector tristate
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          color: isDark ? const Color(0xFF10141D) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              if (items.isNotEmpty) ...[
                Checkbox(
                  value: items.every((i) => _selected.contains(i))
                      ? true
                      : (items.any((i) => _selected.contains(i))
                            ? null
                            : false),
                  tristate: true,
                  activeColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) {
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
                  onTap: () {
                    setState(() {
                      if (items.every((i) => _selected.contains(i))) {
                        _selected.removeAll(items);
                      } else {
                        _selected.addAll(items);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      items.every((i) => _selected.contains(i))
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
                  '(${items.length} disponibles)',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ] else
                Text(
                  '0 elementos encontrados',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              const Spacer(),
              if (_selected.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setState(_selected.clear),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'Limpiar selección (${_selected.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Lista de objetos
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 36,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchController.text.isNotEmpty
                            ? 'No se encontraron objetos para "${_searchController.text}"'
                            : 'No hay elementos en esta categoría',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final color = _typeColor(item.type);
                    final isSelected = _selected.contains(item);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _toggleItem(item, !isSelected),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primary.withValues(
                                      alpha: isDark ? 0.16 : 0.08,
                                    )
                                  : (isDark
                                        ? const Color(0xFF161B26)
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary.withValues(
                                        alpha: isDark ? 0.45 : 0.35,
                                      )
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) => _toggleItem(item, v),
                                ),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                      alpha: isDark ? 0.22 : 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    _typeIcon(item.type),
                                    size: 15,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1E293B),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: isDark ? 0.18 : 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.source ==
                                                      BulkBackupSource
                                                          .dynamicProcedure
                                                  ? 'PROCEDIMIENTO DINÁMICO'
                                                  : item.type,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                          if (item.owner.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '• ${item.owner}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant
                                                    .withValues(alpha: 0.8),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

  Widget _buildSelectionBottomBar(
    BuildContext context,
    bool isDark,
    ColorScheme cs,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141820) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    _selected.isNotEmpty
                        ? Icons.check_circle_rounded
                        : Icons.checklist_rounded,
                    size: 14,
                    color: _selected.isNotEmpty
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${_selected.length} seleccionados para transferir',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _selected.isNotEmpty
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: _selected.isEmpty
                  ? null
                  : LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF38BDF8), Color(0xFF6366F1)]
                          : const [Color(0xFF0284C7), Color(0xFF4F46E5)],
                    ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: _selected.isEmpty
                  ? null
                  : [
                      BoxShadow(
                        color:
                            (isDark
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF0284C7))
                                .withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ElevatedButton.icon(
              onPressed: _selected.isEmpty ? null : _continueToConfirm,
              icon: const Icon(Icons.arrow_forward_rounded, size: 15),
              label: const Text(
                'Configurar destinos',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty ? null : Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: isDark
                    ? const Color(0xFF1E2638)
                    : const Color(0xFFE2E8F0),
                disabledForegroundColor: isDark
                    ? const Color(0xFF475569)
                    : const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fase 2: Confirmación y configuración de destinos ────────────────────────

  Widget _buildConfirm(BuildContext context, bool isDark, ColorScheme cs) {
    final targets = AmbienteSelector.ambientes
        .where((a) => a != _sourceAmbiente)
        .toList();
    final dynamicCount = _selected
        .where((i) => i.source == BulkBackupSource.dynamicProcedure)
        .length;
    final schemaCount = _selected.length - dynamicCount;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card 1: Resumen de origen y elementos seleccionados
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B26) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Resumen de elementos a replicar',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              _headerBadge(
                                context,
                                'Origen: $_sourceAmbiente',
                                color: AmbienteSelector.colorForAmbiente(
                                  _sourceAmbiente,
                                ).withValues(alpha: 0.18),
                                textColor: AmbienteSelector.colorForAmbiente(
                                  _sourceAmbiente,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _countChip(
                                'Total a transferir',
                                '${_selected.length}',
                                cs.primary,
                                isDark,
                              ),
                              _countChip(
                                'Reglas de negocio',
                                '$dynamicCount',
                                const Color(0xFF9333EA),
                                isDark,
                              ),
                              _countChip(
                                'Objetos de esquema',
                                '$schemaCount',
                                Colors.teal,
                                isDark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildSelectedItemsList(isDark, cs),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Card 2: Selección de ambientes destino
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B26) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.alt_route_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Ambientes destino',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(seleccioná uno o varios)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => setState(
                                  () => _targetAmbientes.addAll(targets),
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text(
                                  'Marcar todos',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: () =>
                                    setState(_targetAmbientes.clear),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text(
                                  'Desmarcar todos',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: targets.map((target) {
                              final selected = _targetAmbientes.contains(
                                target,
                              );
                              final envColor =
                                  AmbienteSelector.colorForAmbiente(target);
                              final icon = AmbienteSelector.iconForAmbiente(
                                target,
                              );

                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() {
                                  if (selected) {
                                    _targetAmbientes.remove(target);
                                  } else {
                                    _targetAmbientes.add(target);
                                  }
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? envColor.withValues(
                                            alpha: isDark ? 0.22 : 0.12,
                                          )
                                        : (isDark
                                              ? const Color(0xFF1A2232)
                                              : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected
                                          ? envColor
                                          : cs.outlineVariant.withValues(
                                              alpha: 0.5,
                                            ),
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        icon,
                                        size: 16,
                                        color: selected
                                            ? envColor
                                            : cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        target,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: selected
                                              ? envColor
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                      if (target == 'Prod') ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'CRÍTICO',
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 6),
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons
                                                  .radio_button_unchecked_rounded,
                                        size: 14,
                                        color: selected
                                            ? envColor
                                            : cs.outlineVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (_targetAmbientes.contains('Prod')) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(
                                  alpha: isDark ? 0.16 : 0.08,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Atención: Se transferirá a Producción (Prod). Se recomienda generar un respaldo previo.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
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
                    const SizedBox(height: 14),

                    // Card 3: Opciones avanzadas de esquema (Grants / Sinónimos)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B26) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Opciones avanzadas para objetos de esquema',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _transferGrants,
                            onChanged: (v) =>
                                setState(() => _transferGrants = v ?? false),
                            title: const Text(
                              'Replicar GRANTs',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Lee los privilegios asignados al objeto en $_sourceAmbiente y los otorga en los destinos',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _transferSynonyms,
                            onChanged: (v) =>
                                setState(() => _transferSynonyms = v ?? false),
                            title: const Text(
                              'Replicar sinónimos',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              'Recrea sinónimos públicos y privados del objeto en cada ambiente destino',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Card 4: Seguridad y Respaldo previo
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1B231A)
                            : const Color(0xFFF1FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.withValues(
                            alpha: isDark ? 0.4 : 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 22,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Respaldo previo de seguridad recomendado',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Podés generar una copia .sql de lo que exista actualmente en los destinos antes de sobrescribirlo. '
                                  'Si el respaldo de algún elemento falla, la transferencia completa se cancela automáticamente.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? const Color(0xFFB4E3BA)
                                        : const Color(0xFF166534),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Barra inferior de confirmación
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141820) : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _backToSelection,
                icon: const Icon(Icons.arrow_back_rounded, size: 15),
                label: const Text('Volver a selección'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _targetAmbientes.isEmpty
                    ? null
                    : () => _start(withBackup: false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                child: const Text('Transferir sin respaldo'),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  gradient: _targetAmbientes.isEmpty
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                        ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _targetAmbientes.isEmpty
                      ? null
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF059669,
                            ).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _targetAmbientes.isEmpty
                      ? null
                      : () => _start(withBackup: true),
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text(
                    'Respaldar y transferir',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _targetAmbientes.isEmpty
                        ? null
                        : Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Lista completa (agrupada por categoría) de lo seleccionado, con búsqueda, filtro por categoría y opción de quitar ítems.
  Widget _buildSelectedItemsList(bool isDark, ColorScheme cs) {
    if (_selected.isEmpty) return const SizedBox.shrink();

    final query = _confirmSearchController.text.trim().toUpperCase();

    // Filtrar ítems según búsqueda y categoría seleccionada en el resumen
    final filtered = _selected.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toUpperCase().contains(query) ||
          item.owner.toUpperCase().contains(query);
      final matchesCat =
          _confirmCategoryFilter == 'all' ||
          item.category == _confirmCategoryFilter;
      return matchesQuery && matchesCat;
    }).toList();

    final grouped = <String, List<BulkBackupItem>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    final categoryLabels = {
      'procedure-dynamic': 'Reglas dinámicas',
      'views': 'Vistas',
      'procedures': 'Procedimientos',
      'functions': 'Funciones',
      'packages': 'Paquetes',
      'types': 'Types',
    };

    // Conteo por categoría sobre el universo total seleccionado
    final totalByCat = <String, int>{};
    for (final item in _selected) {
      totalByCat[item.category] = (totalByCat[item.category] ?? 0) + 1;
    }

    final availableCats = totalByCat.keys.toList()
      ..sort(
        (a, b) => (categoryLabels[a] ?? a).compareTo(categoryLabels[b] ?? b),
      );

    final orderedKeys = grouped.keys.toList()
      ..sort(
        (a, b) => (categoryLabels[a] ?? a).compareTo(categoryLabels[b] ?? b),
      );

    return Container(
      constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10141D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de filtro superior del resumen
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141923) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _confirmSearchController,
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1C2230)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        hintText: 'Filtrar selección por nombre...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 15,
                          color: cs.primary,
                        ),
                        suffixIcon: _confirmSearchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 14),
                                onPressed: () {
                                  _confirmSearchController.clear();
                                  setState(() {});
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: cs.primary, width: 1.2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (_confirmCategoryFilter != 'all') {
                        _selected.removeWhere(
                          (item) => item.category == _confirmCategoryFilter,
                        );
                      } else {
                        _selected.clear();
                      }
                    });
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 14),
                  label: Text(
                    _confirmCategoryFilter != 'all'
                        ? 'Quitar categoría'
                        : 'Limpiar todo',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),

          // Pills de categoría horizontales
          if (availableCats.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterPill(
                      label: 'Todos',
                      count: _selected.length,
                      isSelected: _confirmCategoryFilter == 'all',
                      color: cs.primary,
                      onTap: () =>
                          setState(() => _confirmCategoryFilter = 'all'),
                      isDark: isDark,
                    ),
                    for (final cat in availableCats) ...[
                      const SizedBox(width: 6),
                      _filterPill(
                        label: categoryLabels[cat] ?? cat,
                        count: totalByCat[cat] ?? 0,
                        isSelected: _confirmCategoryFilter == cat,
                        color: cat == 'procedure-dynamic'
                            ? const Color(0xFF9333EA)
                            : Colors.teal,
                        onTap: () =>
                            setState(() => _confirmCategoryFilter = cat),
                        isDark: isDark,
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Lista de ítems agrupados
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hay elementos que coincidan con el filtro actual.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final key in orderedKeys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                          child: Row(
                            children: [
                              Text(
                                '${categoryLabels[key] ?? key} (${grouped[key]!.length})'
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => setState(() {
                                  _selected.removeWhere(
                                    (i) => grouped[key]!.contains(i),
                                  );
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    'Quitar grupo',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: cs.error,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final item in grouped[key]!)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF161B26)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _typeIcon(item.type),
                                      size: 14,
                                      color: _typeColor(item.type),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Consolas',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.owner.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          item.owner,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    IconButton(
                                      onPressed: () => setState(
                                        () => _selected.remove(item),
                                      ),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                      ),
                                      tooltip: 'Quitar de la selección',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
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
          ),
        ],
      ),
    );
  }

  Widget _filterPill({
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : null,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countChip(String label, String value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Fase 3: Ejecución y Logs Separados (Éxito vs Errores) ───────────────────

  bool _matchesExecutionFilter(BatchTransferResult r) {
    final query = _executionSearchController.text.trim().toUpperCase();
    final matchesQuery =
        query.isEmpty ||
        r.item.name.toUpperCase().contains(query) ||
        r.item.owner.toUpperCase().contains(query) ||
        (r.message != null && r.message!.toUpperCase().contains(query));
    final matchesTarget =
        _executionTargetFilter == 'all' ||
        r.targetAmbiente == _executionTargetFilter;
    return matchesQuery && matchesTarget;
  }

  Future<void> _retryFailedItems() async {
    if (_running) return;
    final failed = _results.where((r) => r.isError).toList();
    if (failed.isEmpty) {
      AppToast.warning('No hay elementos fallidos para reintentar');
      return;
    }

    final pairsToRetry = failed
        .map((r) => (item: r.item, targetAmbiente: r.targetAmbiente))
        .toList();

    setState(() {
      _running = true;
      _cancelRequested = false;
      _totalPairs = pairsToRetry.length;
      _results.removeWhere((r) => r.isError);
    });

    try {
      await _service.runPairs(
        pairs: pairsToRetry,
        sourceAmbiente: _sourceAmbiente,
        cdUsuario: 'BATCH_RETRY',
        transferGrants: _transferGrants,
        transferSynonyms: _transferSynonyms,
        isCancelled: () => _cancelRequested,
        onResult: (result) {
          setState(() {
            _currentName = '${result.item.name} → ${result.targetAmbiente}';
            final index = _results.indexWhere((r) => r.key == result.key);
            if (index >= 0) {
              _results[index] = result;
            } else {
              _results.add(result);
            }
          });
        },
      );
    } catch (e) {
      AppToast.error('Error durante el reintento: $e');
    } finally {
      if (mounted) {
        setState(() => _running = false);
        final remainingErrors = _results.where((r) => r.isError).length;
        if (remainingErrors == 0) {
          AppToast.success('¡Todos los reintentos finalizaron con éxito!');
        } else {
          AppToast.warning(
            'Reintento finalizado con $remainingErrors errores restantes',
          );
        }
      }
    }
  }

  String _generateMarkdownReport({bool onlyErrors = false}) {
    final buffer = StringBuffer();
    buffer.writeln('# Reporte de Transferencia por Lote');
    buffer.writeln('- **Origen:** `$_sourceAmbiente`');
    buffer.writeln('- **Destinos:** `${_targetAmbientes.join(', ')}`');
    buffer.writeln(
      '- **Fecha:** ${DateTime.now().toLocal().toString().split('.').first}',
    );
    final completed = _results.where((r) => !r.isRunning).toList();
    final succ = completed.where((r) => r.isSuccess).length;
    final err = completed.where((r) => r.isError).length;
    buffer.writeln(
      '- **Totales:** ${completed.length} transferencias evaluadas ($succ exitosas, $err con error)',
    );
    buffer.writeln();

    if (err > 0) {
      buffer.writeln('## ❌ Errores / Fallas de compilación ($err)');
      for (final r in completed.where((r) => r.isError)) {
        buffer.writeln(
          '### ${r.item.name} (${r.item.type}) → ${r.targetAmbiente}',
        );
        if (r.item.owner.isNotEmpty) {
          buffer.writeln('**Owner:** `${r.item.owner}`  ');
        }
        if (r.message != null && r.message!.trim().isNotEmpty) {
          buffer.writeln('```sql');
          buffer.writeln(r.message!.trim());
          buffer.writeln('```');
        }
        buffer.writeln();
      }
    }

    if (!onlyErrors && succ > 0) {
      buffer.writeln('## ✅ Transferencias Exitosas ($succ)');
      for (final r in completed.where((r) => r.isSuccess)) {
        buffer.writeln(
          '- **${r.item.name}** (`${r.item.type}`) → **${r.targetAmbiente}**',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _generateCsvReport() {
    final buffer = StringBuffer();
    buffer.writeln(
      '"Objeto","Tipo","Propietario","Origen","Destino","Estado","Mensaje"',
    );
    for (final r in _results.where((r) => !r.isRunning)) {
      final obj = r.item.name.replaceAll('"', '""');
      final type = r.item.type.replaceAll('"', '""');
      final owner = r.item.owner.replaceAll('"', '""');
      final target = r.targetAmbiente.replaceAll('"', '""');
      final status = r.isSuccess ? 'EXITO' : 'ERROR';
      final msg = (r.message ?? '').replaceAll('"', '""').replaceAll('\n', ' ');
      buffer.writeln(
        '"$obj","$type","$owner","$_sourceAmbiente","$target","$status","$msg"',
      );
    }
    return buffer.toString();
  }

  Future<void> _saveCsvFile() async {
    final csv = _generateCsvReport();
    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar reporte CSV de transferencias',
      fileName:
          'transferencia_${_sourceAmbiente}_${DateTime.now().millisecondsSinceEpoch}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path != null) {
      await File(path).writeAsString(csv);
      AppToast.success('Reporte CSV guardado en: $path');
    }
  }

  Widget _buildExecution(BuildContext context, bool isDark, ColorScheme cs) {
    final completedItems = _results.where((r) => !r.isRunning).toList();
    final successes = completedItems.where((r) => r.isSuccess).toList();
    final errors = completedItems.where((r) => r.isError).toList();
    final filteredSuccesses = successes.where(_matchesExecutionFilter).toList();
    final filteredErrors = errors.where(_matchesExecutionFilter).toList();
    final progress = _totalPairs == 0
        ? 0.0
        : (completedItems.length / _totalPairs).clamp(0.0, 1.0);

    return Column(
      children: [
        // Banner animado de progreso con gradiente y shimmer
        _buildExecutionBanner(
          context,
          isDark,
          cs,
          progress,
          completedItems.length,
        ),

        // Barra de búsqueda y filtros reactivos en ejecución
        _buildExecutionFiltersBar(
          isDark,
          cs,
          completedItems.length,
          filteredSuccesses.length + filteredErrors.length,
        ),

        // Cuerpo con 2 columnas separadas: Exitosos vs Errores
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Columna izquierda: Transferidos con éxito
                Expanded(
                  child: _buildLogColumn(
                    title: 'Transferidos con éxito',
                    icon: Icons.check_circle_rounded,
                    count: filteredSuccesses.length,
                    totalCount: successes.length,
                    accentColor: const Color(0xFF10B981),
                    isDark: isDark,
                    cs: cs,
                    emptyMessage: _running
                        ? 'Esperando transferencias exitosas...'
                        : (successes.isEmpty
                              ? 'No se transfirió ningún elemento exitosamente'
                              : 'No hay elementos exitosos que coincidan con el filtro'),
                    items: filteredSuccesses,
                    isSuccessColumn: true,
                  ),
                ),
                const SizedBox(width: 12),

                // Columna derecha: Con errores / fallas
                Expanded(
                  child: _buildLogColumn(
                    title: 'Errores / Fallas de compilación',
                    icon: Icons.error_outline_rounded,
                    count: filteredErrors.length,
                    totalCount: errors.length,
                    accentColor: const Color(0xFFEF4444),
                    isDark: isDark,
                    cs: cs,
                    emptyMessage: _running
                        ? 'No se registraron errores hasta el momento'
                        : (errors.isEmpty
                              ? '¡Excelente! No hubo errores en este lote'
                              : 'No hay errores que coincidan con el filtro'),
                    items: filteredErrors,
                    isSuccessColumn: false,
                    onCopyAll: errors.isEmpty
                        ? null
                        : () => _copyErrorsToClipboard(errors),
                    onRetryAll: (errors.isEmpty || _running)
                        ? null
                        : _retryFailedItems,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Barra inferior de ejecución
        _buildExecutionBottomBar(
          context,
          isDark,
          cs,
          successes.length,
          errors.length,
          errors: errors,
        ),
      ],
    );
  }

  Widget _buildExecutionFiltersBar(
    bool isDark,
    ColorScheme cs,
    int totalCount,
    int filteredCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141923) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _executionSearchController,
                style: const TextStyle(fontSize: 12),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1C2230) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  hintText: 'Filtrar resultados por nombre o mensaje...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 15,
                    color: cs.primary,
                  ),
                  suffixIcon: _executionSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 14),
                          onPressed: () {
                            _executionSearchController.clear();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: cs.primary, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          if (_targetAmbientes.length > 1) ...[
            const SizedBox(width: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterPill(
                    label: 'Todos',
                    count: totalCount,
                    isSelected: _executionTargetFilter == 'all',
                    color: cs.primary,
                    onTap: () => setState(() => _executionTargetFilter = 'all'),
                    isDark: isDark,
                  ),
                  for (final target in _targetAmbientes) ...[
                    const SizedBox(width: 6),
                    _filterPill(
                      label: target,
                      count: _results
                          .where(
                            (r) => !r.isRunning && r.targetAmbiente == target,
                          )
                          .length,
                      isSelected: _executionTargetFilter == target,
                      color: AmbienteSelector.colorForAmbiente(target),
                      onTap: () =>
                          setState(() => _executionTargetFilter = target),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExecutionBanner(
    BuildContext context,
    bool isDark,
    ColorScheme cs,
    double progress,
    int completedCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131722) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_running ? cs.primary : Colors.teal).withValues(
                    alpha: 0.15,
                  ),
                ),
                alignment: Alignment.center,
                child: _running
                    ? RotationTransition(
                        turns: _syncIconController,
                        child: Icon(
                          Icons.sync_rounded,
                          size: 15,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: Colors.teal,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _running
                                ? 'Transfiriendo lote a destinos...'
                                : 'Proceso de transferencia finalizado',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$completedCount / $_totalPairs (${(progress * 100).toInt()}%)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _running
                          ? (_currentName.isNotEmpty
                                ? _currentName
                                : 'Iniciando conexión...')
                          : 'Se procesaron todos los elementos seleccionados',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'Consolas',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_running)
                OutlinedButton.icon(
                  onPressed: _cancelRequested ? null : _cancel,
                  icon: const Icon(
                    Icons.stop_rounded,
                    size: 15,
                    color: Colors.red,
                  ),
                  label: Text(
                    _cancelRequested ? 'Cancelando...' : 'Cancelar',
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Track con shimmer
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0C1322) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                        ),
                      ),
                    ),
                  ),
                  if (_running && progress > 0.05)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(
                                    _shimmerController.value * 3.0 - 1.5,
                                    0,
                                  ),
                                  end: Alignment(
                                    _shimmerController.value * 3.0 - 0.5,
                                    0,
                                  ),
                                  colors: [
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.white.withValues(alpha: 0.5),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogColumn({
    required String title,
    required IconData icon,
    required int count,
    required int totalCount,
    required Color accentColor,
    required bool isDark,
    required ColorScheme cs,
    required String emptyMessage,
    required List<BatchTransferResult> items,
    required bool isSuccessColumn,
    VoidCallback? onCopyAll,
    VoidCallback? onRetryAll,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.35 : 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera de la columna
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: accentColor.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count != totalCount ? '$count / $totalCount' : '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
                if (onRetryAll != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message:
                        'Reintentar solo los elementos fallidos ($totalCount)',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onRetryAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.replay_rounded,
                              size: 13,
                              color: accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Reintentar ($totalCount)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (onCopyAll != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Copiar todos los errores al portapapeles',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: onCopyAll,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Lista de resultados
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSuccessColumn
                                ? Icons.done_all_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 28,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final result = items[index];
                      final typeColor = _typeColor(result.item.type);
                      final targetColor = AmbienteSelector.colorForAmbiente(
                        result.targetAmbiente,
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1B2232)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSuccessColumn
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    _typeIcon(result.item.type),
                                    size: 12,
                                    color: typeColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    result.item.name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: targetColor.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '→ ${result.targetAmbiente}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: targetColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (result.message != null &&
                                result.message!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? (isSuccessColumn
                                            ? const Color(0xFF14241B)
                                            : const Color(0xFF2E1518))
                                      : (isSuccessColumn
                                            ? const Color(0xFFE8F5E9)
                                            : const Color(0xFFFFEBEE)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  result.message!,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontFamily: 'Consolas',
                                    color: isSuccessColumn
                                        ? (isDark
                                              ? const Color(0xFF81C784)
                                              : const Color(0xFF2E7D32))
                                        : (isDark
                                              ? const Color(0xFFE57373)
                                              : const Color(0xFFC62828)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _copyErrorsToClipboard(List<BatchTransferResult> errors) {
    final buffer = StringBuffer();
    buffer.writeln(
      '# Errores en transferencia por lote desde $_sourceAmbiente',
    );
    buffer.writeln('Fecha: ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    for (final err in errors) {
      buffer.writeln('- Objeto: ${err.item.name} (${err.item.type})');
      buffer.writeln('  Destino: ${err.targetAmbiente}');
      buffer.writeln('  Detalle: ${err.message ?? "Error desconocido"}');
      buffer.writeln();
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    AppToast.success('Errores copiados al portapapeles');
  }

  Widget _buildExecutionBottomBar(
    BuildContext context,
    bool isDark,
    ColorScheme cs,
    int successCount,
    int errorCount, {
    required List<BatchTransferResult> errors,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141820) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            _running
                ? Icons.hourglass_top_rounded
                : (errorCount == 0
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded),
            size: 16,
            color: _running
                ? cs.primary
                : (errorCount == 0 ? Colors.green : Colors.orange),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _running
                  ? 'Ejecutando transferencia en segundo plano...'
                  : 'Lote finalizado: $successCount exitosos, $errorCount con error',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          if (!_running) ...[
            if (_lastBackupDirectory != null) ...[
              OutlinedButton.icon(
                onPressed: () => unawaited(
                  BackupService.revealInExplorer(_lastBackupDirectory!),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 15),
                label: const Text('Abrir carpeta de respaldo'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (errorCount > 0) ...[
              FilledButton.icon(
                onPressed: _retryFailedItems,
                icon: const Icon(Icons.replay_rounded, size: 15),
                label: Text('Reintentar fallidos ($errorCount)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            PopupMenuButton<String>(
              tooltip: 'Exportar informe de resultados',
              onSelected: (val) {
                switch (val) {
                  case 'md_full':
                    Clipboard.setData(
                      ClipboardData(text: _generateMarkdownReport()),
                    );
                    AppToast.success(
                      'Reporte Markdown copiado al portapapeles',
                    );
                  case 'md_errors':
                    _copyErrorsToClipboard(errors);
                  case 'csv_clip':
                    Clipboard.setData(
                      ClipboardData(text: _generateCsvReport()),
                    );
                    AppToast.success('Reporte CSV copiado al portapapeles');
                  case 'csv_file':
                    unawaited(_saveCsvFile());
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'md_full',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Copiar reporte Markdown (completo)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'md_errors',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: Colors.red,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Copiar solo errores (Markdown)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 1),
                const PopupMenuItem(
                  value: 'csv_clip',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(Icons.table_chart_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Copiar reporte CSV al portapapeles',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'csv_file',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(Icons.file_download_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Guardar como archivo CSV...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ios_share_rounded,
                      size: 14,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Exportar reporte',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _resetToNewTransfer,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Nueva transferencia'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _close,
              icon: const Icon(Icons.close_rounded, size: 15),
              label: const Text('Cerrar ventana'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Diálogo interactivo de pegado con vista previa en vivo ────────────────────

class _PasteNamesDialogContent extends StatefulWidget {
  final String sourceAmbiente;
  final String categoryLabel;
  final String activeCategory;
  final List<BulkBackupItem> activePool;
  final List<BulkBackupItem> allPool;
  final void Function([List<BulkBackupItem>? result]) close;

  const _PasteNamesDialogContent({
    required this.sourceAmbiente,
    required this.categoryLabel,
    required this.activeCategory,
    required this.activePool,
    required this.allPool,
    required this.close,
  });

  @override
  State<_PasteNamesDialogContent> createState() =>
      _PasteNamesDialogContentState();
}

class _PasteNamesDialogContentState extends State<_PasteNamesDialogContent> {
  late final TextEditingController _controller;
  bool _searchInAllCategories = true;
  int _previewTab = 0; // 0 = Coincidentes, 1 = No encontrados

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _cleanToken(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';

    // Quitar caracteres invisibles comunes de portapapeles (Teams, Outlook, Word, web):
    t = t.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    t = t.replaceAll('\u00A0', ' ');
    t = t.trim();

    // Quitar comentarios SQL: "-- ..." y "/* ... */"
    t = t.replaceAll(RegExp(r'--.*$'), '');
    t = t.replaceAll(RegExp(r'/\*.*?\*/'), '');
    t = t.trim();

    // Si viene en formato "CODIGO - DESCRIPCION" o "CODIGO : DESCRIPCION" o "CODIGO | DESCRIPCION"
    if (RegExp(r'\s+[-:–—|]\s+').hasMatch(t)) {
      t = t.split(RegExp(r'\s+[-:–—|]\s+')).first.trim();
    }

    // Quitar viñetas / numeración inicial si aplica: "1. ", "2) ", "- ", "* ", "• "
    t = t.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s+'), '').trim();

    // Quitar prefijos comunes de ejecución o DDL si se copiaron de un script:
    final ddlPrefix = RegExp(
      r'^(?:EXEC(?:UTE)?|CALL|SELECT|FROM|DROP|ALTER|DESCRIBE|DESC|PACKAGE\s+BODY|PACKAGE|PROCEDURE|FUNCTION|VIEW|TYPE\s+BODY|TYPE)\s+',
      caseSensitive: false,
    );
    t = t.replaceFirst(ddlPrefix, '').trim();

    // Quitar paréntesis y argumentos de llamada: "PROC_NAME(P1, P2)" -> "PROC_NAME"
    if (t.contains('(')) {
      t = t.substring(0, t.indexOf('(')).trim();
    }

    // Quitar comillas simples, dobles, backticks, corchetes o puntuación de cierre:
    final stripRegex = RegExp(r"""^['"`\[\]\s]+|['"`\[\];:,.\s]+$""");
    t = t.replaceAll(stripRegex, '').trim();

    return t;
  }

  static List<String> _parseInput(String text) {
    if (text.trim().isEmpty) return const [];

    // Dividir por comas, punto y coma, saltos de línea (\r y \n), tabs y pipes
    final rawTokens = text.split(RegExp(r'[,;\n\r\t|]+'));
    final result = <String>[];

    for (final raw in rawTokens) {
      final cleaned = _cleanToken(raw);
      if (cleaned.isEmpty) continue;

      // Si contiene múltiples nombres separados por espacios en una sola línea
      if (cleaned.contains(RegExp(r'\s+'))) {
        final spaceParts = cleaned.split(RegExp(r'\s+'));
        for (final sp in spaceParts) {
          final sub = _cleanToken(sp);
          if (sub.isNotEmpty) result.add(sub);
        }
      } else {
        result.add(cleaned);
      }
    }
    return result;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = data?.text;
    if (clipText != null && clipText.trim().isNotEmpty) {
      final current = _controller.text.trim();
      if (current.isEmpty) {
        _controller.text = clipText.trim();
      } else {
        _controller.text = '$current\n${clipText.trim()}';
      }
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final pool = _searchInAllCategories ? widget.allPool : widget.activePool;

    // Indexar pool con múltiples claves para máxima tolerancia:
    // 1. item.name (ej: "PR_CALCULAR")
    // 2. OWNER.item.name (ej: "SIRWEB.PR_CALCULAR")
    final poolByName = <String, BulkBackupItem>{};
    for (final item in pool) {
      final nameClean = item.name.trim().toUpperCase();
      if (nameClean.isEmpty) continue;
      poolByName.putIfAbsent(nameClean, () => item);

      if (item.owner.trim().isNotEmpty) {
        final ownerClean = item.owner.trim().toUpperCase();
        poolByName.putIfAbsent('$ownerClean.$nameClean', () => item);
      }
    }

    // Indexar también allPool si estamos en activePool para detectar si existe en otra categoría
    final allPoolByName = <String, BulkBackupItem>{};
    if (!_searchInAllCategories) {
      for (final item in widget.allPool) {
        final nameClean = item.name.trim().toUpperCase();
        if (nameClean.isNotEmpty) {
          allPoolByName.putIfAbsent(nameClean, () => item);
          if (item.owner.trim().isNotEmpty) {
            allPoolByName.putIfAbsent(
              '${item.owner.trim().toUpperCase()}.$nameClean',
              () => item,
            );
          }
        }
      }
    }

    BulkBackupItem? resolveItem(
      String rawToken,
      Map<String, BulkBackupItem> map,
    ) {
      final tUpper = rawToken.trim().toUpperCase();
      if (tUpper.isEmpty) return null;

      // 1. Coincidencia directa exacta
      if (map.containsKey(tUpper)) {
        return map[tUpper];
      }

      // 2. Si el token tiene punto (ej. "SIRWEB.PR_CALCULAR" o "PKG_VENTAS.CALCULAR"):
      if (tUpper.contains('.')) {
        final nameOnly = tUpper.split('.').last.trim();
        if (map.containsKey(nameOnly)) {
          return map[nameOnly];
        }
        final firstPart = tUpper.split('.').first.trim();
        if (map.containsKey(firstPart)) {
          return map[firstPart];
        }
      }

      return null;
    }

    final rawTokens = _parseInput(_controller.text);
    final uniqueTokens = <String>{};
    for (final t in rawTokens) {
      uniqueTokens.add(t);
    }

    final matchedItems = <BulkBackupItem>[];
    final notFoundTokens = <({String token, String? otherCategory})>[];

    for (final token in uniqueTokens) {
      final found = resolveItem(token, poolByName);
      if (found != null) {
        matchedItems.add(found);
      } else {
        String? otherCat;
        if (!_searchInAllCategories) {
          final inAll = resolveItem(token, allPoolByName);
          if (inAll != null) {
            otherCat = inAll.category;
          }
        }
        notFoundTokens.add((token: token, otherCategory: otherCat));
      }
    }

    final hasInput = rawTokens.isNotEmpty;
    final matchedCount = matchedItems.length;
    final notFoundCount = notFoundTokens.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera con constelación
            ConstellationDialogTitle(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.playlist_add_rounded,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pegar lista de nombres',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Origen: ${widget.sourceAmbiente} · ${_searchInAllCategories ? "Todo el catálogo" : widget.categoryLabel}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.close(null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Barra de herramientas superior
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141923)
                    : const Color(0xFFF1F5F9),
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, size: 14),
                    label: const Text('Pegar portapapeles'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  if (_controller.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 14),
                      label: const Text('Limpiar'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() {
                      _searchInAllCategories = !_searchInAllCategories;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchInAllCategories
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 16,
                            color: _searchInAllCategories
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Buscar en todo el catálogo',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: _searchInAllCategories
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _searchInAllCategories
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo principal con caja de texto y vista previa
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 115,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'Consolas',
                        letterSpacing: 0.2,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.all(10),
                        hintText:
                            'Escribe o pega nombres separados por coma o salto de línea...\n'
                            'Ej: PR_CALCULAR_PRIMA, VW_CLIENTES, PKG_EMISION',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'Consolas',
                          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Barra reactiva de métricas
                  Row(
                    children: [
                      _metricBadge(
                        label: 'Total ingresados',
                        count: uniqueTokens.length,
                        color: cs.primary,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _metricBadge(
                        label: 'Coincidentes',
                        count: matchedCount,
                        color: Colors.teal,
                        icon: Icons.check_circle_rounded,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _metricBadge(
                        label: 'No encontrados',
                        count: notFoundCount,
                        color: Colors.amber.shade700,
                        icon: Icons.warning_amber_rounded,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Pestañas de vista previa
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _tabHeader(
                    title: 'Coincidentes',
                    count: matchedCount,
                    isSelected: _previewTab == 0,
                    color: Colors.teal,
                    onTap: () => setState(() => _previewTab = 0),
                  ),
                  const SizedBox(width: 12),
                  _tabHeader(
                    title: 'No encontrados',
                    count: notFoundCount,
                    isSelected: _previewTab == 1,
                    color: Colors.amber.shade700,
                    onTap: () => setState(() => _previewTab = 1),
                  ),
                ],
              ),
            ),

            // Contenedor scrolleable de vista previa
            Flexible(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 90,
                  maxHeight: 150,
                ),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF10141D)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: !hasInput
                    ? Center(
                        child: Text(
                          'Ingresa nombres para ver el análisis de coincidencias en vivo.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    : (_previewTab == 0
                          ? (matchedItems.isEmpty
                                ? Center(
                                    child: Text(
                                      'Ningún nombre coincidió con el catálogo activo.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final m in matchedItems)
                                          _itemChip(m, isDark, cs),
                                      ],
                                    ),
                                  ))
                          : (notFoundTokens.isEmpty
                                ? Center(
                                    child: Text(
                                      '¡Todos los nombres fueron encontrados con éxito!',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.teal.shade400,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final token in notFoundTokens)
                                          _missingChip(token, isDark),
                                      ],
                                    ),
                                  ))),
              ),
            ),

            // Botones de acción inferiores
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141923)
                    : const Color(0xFFF1F5F9),
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => widget.close(null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: matchedCount == 0
                        ? null
                        : () => widget.close(matchedItems),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      matchedCount == 0
                          ? 'Seleccionar'
                          : 'Seleccionar ($matchedCount ${matchedCount == 1 ? "objeto" : "objetos"})',
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

  Widget _metricBadge({
    required String label,
    required int count,
    required Color color,
    IconData? icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabHeader({
    required String title,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? color : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemChip(BulkBackupItem item, bool isDark, ColorScheme cs) {
    final typeColor = item.source == BulkBackupSource.dynamicProcedure
        ? const Color(0xFF9333EA)
        : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2332) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.source == BulkBackupSource.dynamicProcedure
                ? Icons.code_rounded
                : Icons.account_tree_outlined,
            size: 11,
            color: typeColor,
          ),
          const SizedBox(width: 4),
          Text(
            item.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'Consolas',
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              item.source == BulkBackupSource.dynamicProcedure
                  ? 'REGLA'
                  : item.type,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: typeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingChip(
    ({String token, String? otherCategory}) missing,
    bool isDark,
  ) {
    final hasOther = missing.otherCategory != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: hasOther
            ? (isDark ? const Color(0xFF2E2612) : const Color(0xFFFEF3C7))
            : Colors.amber.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasOther
              ? Colors.amber.shade600
              : Colors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasOther ? Icons.info_outline_rounded : Icons.close_rounded,
            size: 11,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            missing.token,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
            ),
          ),
          if (hasOther) ...[
            const SizedBox(width: 4),
            Text(
              '(en ${missing.otherCategory})',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
