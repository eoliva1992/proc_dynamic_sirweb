import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart' show reaction, ReactionDisposer;
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_tab.dart';
import '../widgets/code_editor_panel.dart';
import '../widgets/config_badge.dart';
import '../widgets/_editor_themes.dart';
import '../widgets/new_procedure_dialog.dart';
import '../widgets/schema_browser_modal.dart';
import '../widgets/schema_status_overlay.dart';
import '../widgets/search_tab_view.dart';

part '_usuario_button.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<AppTab> _tabs = [AppTab()];
  int _activeTab = 0;
  int? _loadingTabIndex;
  bool _syncingActiveTab = false;
  late ReactionDisposer _tabReaction;

  // LRU list of tab IDs kept alive in the IndexedStack (search tabs only)
  final List<int> _lruTabIds = [];
  static const _maxLiveSearchTabs = 5;

  void _markTabLive(int index) {
    final id = _tabs[index].tabId;
    _lruTabIds.remove(id);
    _lruTabIds.add(id);
    while (_lruTabIds.length > _maxLiveSearchTabs) {
      _lruTabIds.removeAt(0);
    }
  }

  bool _isLive(AppTab tab) {
    return tab.procedimiento != null ||
        tab.loading ||
        _lruTabIds.contains(tab.tabId);
  }

  @override
  void initState() {
    super.initState();
    _markTabLive(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      procedimientosProvider.cargarConfiguraciones();
    });
    _tabReaction = reaction(
      (_) => (
        procedimientosProvider.procedimientoActual,
        procedimientosProvider.cargandoEditor,
        procedimientosProvider.error,
      ),
      (state) {
        if (_syncingActiveTab) return;
        // Only handle explicit tracked loads (ambiente change, new procedure).
        // onSelect manages its own lifecycle via async/await.
        if (_loadingTabIndex == null) return;
        final proc = state.$1;
        final loading = state.$2;
        final error = state.$3;
        // Use the tab that initiated the load; fall back to the active tab.
        final targetIndex = _loadingTabIndex ?? _activeTab;
        if (targetIndex >= _tabs.length) return;
        // If load failed (null proc, no longer loading) and the tab was waiting, clear it
        if (proc == null &&
            !loading &&
            error != null &&
            _tabs[targetIndex].loading) {
          final procCode = _tabs[targetIndex].procedimiento?.cdProcedimiento;
          final amb = _tabs[targetIndex].ambiente;
          _loadingTabIndex = null;
          setState(() {
            _tabs[targetIndex].procedimiento = null;
            _tabs[targetIndex].loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                procCode != null ? '$procCode no existe en $amb' : error,
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
        if (proc == null) return;
        // Only update the tab when the load finishes, never while it is in progress.
        if (loading) return;
        _loadingTabIndex = null;
        final target = _tabs[targetIndex];
        setState(() {
          target.procedimiento = proc;
          target.loading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _tabReaction();
    for (final tab in _tabs) {
      tab.searchState.dispose();
    }
    super.dispose();
  }

  void _goBackToSearch() {
    final tab = _tabs[_activeTab];
    if (tab.isDirty) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Salir del editor'),
          content: const Text(
            'Hay cambios sin guardar. ¿Salir de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Salir sin guardar'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) _doGoBackToSearch();
      });
      return;
    }
    _doGoBackToSearch();
  }

  void _doGoBackToSearch() {
    setState(() {
      final tab = _tabs[_activeTab];
      tab.procedimiento = null;
      tab.loading = false;
      tab.isDirty = false;
    });
    procedimientosProvider.setProcedimientoActual(null);
  }

  void _activateTab(int index) {
    if (_activeTab == index) return;
    setState(() => _activeTab = index);
    _markTabLive(index);
    final tab = _tabs[index];
    _syncingActiveTab = true;
    procedimientosProvider.setProcedimientoActual(tab.procedimiento);
    procedimientosProvider.setAmbiente(tab.ambiente);
    _syncingActiveTab = false;
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    final inEditor = _tabs[index].procedimiento != null;
    if (_tabs[index].isDirty && inEditor) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cerrar pestaña'),
          content: const Text(
            'Hay cambios sin guardar. ¿Cerrar de todos modos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cerrar sin guardar'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) _doCloseTab(index);
      });
      return;
    }
    _doCloseTab(index);
  }

  void _doCloseTab(int index) {
    _tabs[index].searchState.dispose();
    _lruTabIds.remove(_tabs[index].tabId);
    setState(() {
      _tabs.removeAt(index);
      if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      } else if (_activeTab > index) {
        _activeTab--;
      }
    });
    final now = _tabs[_activeTab];
    procedimientosProvider.setProcedimientoActual(now.procedimiento);
    procedimientosProvider.setAmbiente(now.ambiente);
  }

  void _addSearchTab() {
    setState(() {
      _tabs.add(AppTab());
      _activeTab = _tabs.length - 1;
    });
    _markTabLive(_activeTab);
    procedimientosProvider.setProcedimientoActual(null);
    procedimientosProvider.setAmbiente(_tabs[_activeTab].ambiente);
  }

  void _onTabAmbienteChanged(AppTab tab, String newAmbiente) {
    if (tab.isDirty && tab.procedimiento != null) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambiar ambiente'),
          content: const Text(
            'Hay cambios sin guardar. ¿Cambiar de ambiente de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cambiar sin guardar'),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) {
          tab.isDirty = false;
          _doTabAmbienteChanged(tab, newAmbiente);
        }
      });
      return;
    }
    _doTabAmbienteChanged(tab, newAmbiente);
  }

  void _doTabAmbienteChanged(AppTab tab, String newAmbiente) {
    setState(() => tab.ambiente = newAmbiente);
    if (_tabs[_activeTab].tabId != tab.tabId) return;
    procedimientosProvider.setAmbiente(newAmbiente);
    final proc = tab.procedimiento;
    if (proc != null) {
      // Reload the open procedure from the new environment
      _loadingTabIndex = _tabs.indexOf(tab);
      setState(() => tab.loading = true);
      unawaited(procedimientosProvider.seleccionar(proc));
    } else if (tab.searchState.resultados.isNotEmpty) {
      // Re-run the active search in the new environment
      unawaited(
        tab.searchState.buscar(
          busqueda: tab.searchState.searchText,
          cfg: tab.searchState.config,
          est: tab.searchState.estado,
          ambiente: newAmbiente,
        ),
      );
    }
  }

  void _onTabReorder(int oldIndex, int newIndex) {
    // _tabs already mutated by _MainTabBarState._handleReorder (shared reference).
    int newActive = _activeTab;
    if (_activeTab == oldIndex) {
      newActive = newIndex;
    } else if (_activeTab > oldIndex && _activeTab <= newIndex) {
      newActive = _activeTab - 1;
    } else if (_activeTab < oldIndex && _activeTab >= newIndex) {
      newActive = _activeTab + 1;
    }
    setState(() => _activeTab = newActive);
  }

  void _cycleTab(int direction) {
    if (_tabs.length < 2) return;
    _activateTab((_activeTab + direction + _tabs.length) % _tabs.length);
  }

  Future<void> _showNewProcedureDialog(BuildContext context) async {
    // Require a registered user — open the user dialog first if missing
    if (procedimientosProvider.cdUsuario.isEmpty) {
      _showUsuarioDialog(
        context,
        onSaved: () => _showNewProcedureDialog(context),
      );
      return;
    }
    final ambiente = _tabs[_activeTab].ambiente;
    // Sync provider to the active tab's database before opening the dialog
    procedimientosProvider.setAmbiente(ambiente);
    final result =
        await showDialog<
          ({String cdProcedimiento, String inConfiguracion, String ambiente})?
        >(
          context: context,
          barrierDismissible: false,
          builder: (_) => NewProcedureDialog(ambiente: ambiente),
        );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            procedimientosProvider.mensaje ?? 'Creado correctamente',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
      // Open the new procedure in a fresh tab
      final stub = Procedimiento(
        cdProcedimiento: result.cdProcedimiento,
        deTexto: '',
        inConfiguracion: result.inConfiguracion,
        version: 0,
        stProcedimiento: '1',
      );
      setState(() {
        _tabs.add(AppTab(ambiente: result.ambiente));
        _activeTab = _tabs.length - 1;
        _tabs[_activeTab].loading = true;
      });
      _markTabLive(_activeTab);
      procedimientosProvider.setAmbiente(result.ambiente);
      _loadingTabIndex = _tabs.length - 1;
      unawaited(procedimientosProvider.seleccionar(stub));
    }
  }

  void _showSchemaBrowser(BuildContext context) {
    showSchemaBrowser(context, ambiente: _tabs[_activeTab].ambiente);
  }

  void _showUsuarioDialog(BuildContext context, {VoidCallback? onSaved}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = procedimientosProvider;
    final ctrl = TextEditingController(text: provider.cdUsuario);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'usuario',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, _) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Cabecera con gradiente ──────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0078D4), Color(0xFF005A9E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Identificación',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ingresá tu código de usuario',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Cuerpo ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFD4D4D4)
                            : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (old, val) => val.copyWith(
                            text: val.text.toUpperCase(),
                            selection: val.selection,
                          ),
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: 'Ej: EOLIVA',
                        hintStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF555555)
                              : Colors.black38,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 0,
                        ),
                        prefixIcon: Icon(
                          Icons.badge_outlined,
                          size: 18,
                          color: isDark
                              ? const Color(0xFF0078D4)
                              : const Color(0xFF0078D4),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2D2D2D)
                            : const Color(0xFFF5F7FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF3A3A3A)
                                : const Color(0xFFDDE2EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF0078D4),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onSubmitted: (v) {
                        provider.setCdUsuario(v.trim());
                        Navigator.of(ctx).pop();
                        if (v.trim().isNotEmpty) onSaved?.call();
                      },
                    ),
                  ),

                  // ── Acciones ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF3A3A3A)
                                      : Colors.grey.shade300,
                                ),
                              ),
                            ),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF808080)
                                    : Colors.black45,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              provider.setCdUsuario(ctrl.text.trim());
                              Navigator.of(ctx).pop();
                              if (ctrl.text.trim().isNotEmpty) onSaved?.call();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0078D4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_rounded, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Guardar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
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
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _addSearchTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            _closeTab(_activeTab),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _cycleTab(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            _cycleTab(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(context),
          body: Stack(
            children: [
              Column(
                children: [
                  _MainTabBar(
                    tabs: _tabs,
                    activeTab: _activeTab,
                    onActivate: _activateTab,
                    onClose: _closeTab,
                    onAdd: _addSearchTab,
                    onReorder: _onTabReorder,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _activeTab,
                      children: [
                        for (final tab in _tabs)
                          _TabFadeIn(
                            key: ValueKey(tab.tabId),
                            child: _isLive(tab)
                                ? _buildTabContent(tab)
                                : SizedBox.shrink(
                                    key: ValueKey('dead_${tab.tabId}'),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Positioned(
                left: 12,
                bottom: 12,
                child: SchemaStatusOverlay(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppTab tab) {
    if (tab.inSearchMode) {
      return SearchTabView(
        key: ValueKey('s_${tab.tabId}'),
        state: tab.searchState,
        ambiente: tab.ambiente,
        onAmbienteChanged: (v) => _onTabAmbienteChanged(tab, v),
        onNewProcedure: () => _showNewProcedureDialog(context),
        onOpenInNewTab: (Procedimiento proc) async {
          if (!mounted) return;
          final newTab = AppTab(ambiente: tab.ambiente);
          final newIndex = _tabs.length;
          setState(() {
            _tabs.add(newTab);
            _activeTab = newIndex;
            newTab.procedimiento = proc;
            newTab.loading = true;
          });
          _markTabLive(newIndex);
          procedimientosProvider.setAmbiente(newTab.ambiente);
          await procedimientosProvider.seleccionar(proc);
          if (!mounted) return;
          if (newIndex >= _tabs.length || _tabs[newIndex] != newTab) return;
          final result = procedimientosProvider.procedimientoActual;
          final err = procedimientosProvider.error;
          setState(() {
            newTab.procedimiento = result;
            newTab.loading = false;
          });
          if (result == null && err != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${proc.cdProcedimiento} no existe en ${newTab.ambiente}',
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
        onSelect: (Procedimiento proc) async {
          if (!mounted) return;
          final tabIndex = _tabs.indexOf(tab);
          setState(() {
            tab.procedimiento = proc;
            tab.loading = true;
          });
          await procedimientosProvider.seleccionar(proc);
          if (!mounted) return;
          if (tabIndex >= _tabs.length || _tabs[tabIndex] != tab) return;
          final result = procedimientosProvider.procedimientoActual;
          final err = procedimientosProvider.error;
          setState(() {
            tab.procedimiento = result;
            tab.loading = false;
          });
          if (result == null && err != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${proc.cdProcedimiento} no existe en ${tab.ambiente}',
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
      );
    }
    return Column(
      key: ValueKey('e_${tab.tabId}'),
      children: [
        _buildEditorNav(tab),
        if (tab.ambiente == 'Prod')
          Container(
            width: double.infinity,
            color: Colors.red.shade900.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: Colors.orange.shade300,
                ),
                const SizedBox(width: 6),
                Text(
                  'PRODUCCIÓN — Los cambios afectan datos reales',
                  style: TextStyle(
                    color: Colors.orange.shade200,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        if (tab.loading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF0078D4)),
            ),
          )
        else
          Expanded(
            child: CodeEditorPanel(
              key: ValueKey('editor_${tab.tabId}'),
              procedimiento: tab.procedimiento!,
              onDirtyChanged: (dirty) {
                if (tab.isDirty != dirty) setState(() => tab.isDirty = dirty);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEditorNav(AppTab tab) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = cs.onSurfaceVariant;
    final boldColor = cs.onSurface;
    final borderColor = cs.outlineVariant;
    const newColor = Color(0xFF107C10);

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : cs.surface,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          InkWell(
            onTap: _goBackToSearch,
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios, size: 11, color: mutedColor),
                  const SizedBox(width: 2),
                  Text(
                    'Buscar',
                    style: TextStyle(fontSize: 11, color: mutedColor),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, size: 14, color: mutedColor),
          ),
          if (tab.procedimiento != null) ...[
            ConfigBadge(
              config: tab.procedimiento!.inConfiguracion,
              small: true,
            ),
            const SizedBox(width: 6),
            Text(
              tab.procedimiento!.cdProcedimiento,
              style: TextStyle(
                fontSize: 12,
                color: boldColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          AmbienteSelector(
            value: tab.ambiente,
            onChanged: (v) => _onTabAmbienteChanged(tab, v),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 18,
            child: VerticalDivider(width: 1, color: cs.outlineVariant),
          ),
          const SizedBox(width: 8),
          // Create new procedure for the current tab's database
          InkWell(
            onTap: () => _showNewProcedureDialog(context),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: newColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: newColor.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 13, color: newColor),
                  SizedBox(width: 4),
                  Text(
                    'Nuevo',
                    style: TextStyle(
                      fontSize: 11,
                      color: newColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      title: const Text(
        'Procedimientos Dinámicos',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      actions: [
        Tooltip(
          message: 'Explorador de esquema',
          child: IconButton(
            onPressed: () => _showSchemaBrowser(context),
            icon: const Icon(Icons.storage_rounded),
            color: Colors.white70,
          ),
        ),
        Observer(
          builder: (_) => _UsuarioButton(
            cdUsuario: procedimientosProvider.cdUsuario,
            onTap: () => _showUsuarioDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        ListenableBuilder(
          listenable: editorThemeStore,
          builder: (context, _) {
            final meta = editorThemeStore.currentMeta;
            String? cat;
            final items = <PopupMenuEntry<String>>[];
            for (final t in kEditorThemes) {
              if (t.category != cat) {
                if (cat != null) items.add(const PopupMenuDivider(height: 6));
                items.add(
                  PopupMenuItem<String>(
                    enabled: false,
                    height: 26,
                    child: Text(
                      t.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                );
                cat = t.category;
              }
              final active = editorThemeStore.themeId == t.id;
              items.add(
                PopupMenuItem<String>(
                  value: t.id,
                  height: 36,
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: t.swatch,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.grey, width: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(t.name, style: const TextStyle(fontSize: 13)),
                      if (active) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 14),
                      ],
                    ],
                  ),
                ),
              );
            }
            return Tooltip(
              message: 'Tema: ${meta.name}',
              child: PopupMenuButton<String>(
                tooltip: '',
                offset: const Offset(0, 40),
                onSelected: editorThemeStore.setTheme,
                itemBuilder: (_) => items,
                icon: Stack(
                  children: [
                    const Icon(
                      Icons.palette_outlined,
                      color: Colors.white70,
                      size: 22,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: meta.swatch,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _MainTabBar extends StatefulWidget {
  final List<AppTab> tabs;
  final int activeTab;
  final ValueChanged<int> onActivate;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _MainTabBar({
    required this.tabs,
    required this.activeTab,
    required this.onActivate,
    required this.onClose,
    required this.onAdd,
    required this.onReorder,
  });

  @override
  State<_MainTabBar> createState() => _MainTabBarState();
}

class _MainTabBarState extends State<_MainTabBar> {
  late List<AppTab> _tabs;
  late int _activeTab;

  @override
  void initState() {
    super.initState();
    _tabs = widget.tabs;
    _activeTab = widget.activeTab;
  }

  @override
  void didUpdateWidget(_MainTabBar old) {
    super.didUpdateWidget(old);
    _tabs = widget.tabs;
    _activeTab = widget.activeTab;
  }

  void _handleReorder(int oldIndex, int newIndex) {
    final clamped = newIndex.clamp(0, _tabs.length - 1);
    // Update local state immediately for a seamless visual
    setState(() {
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(clamped, tab);
      if (_activeTab == oldIndex) {
        _activeTab = clamped;
      } else if (_activeTab > oldIndex && _activeTab <= clamped) {
        _activeTab--;
      } else if (_activeTab < oldIndex && _activeTab >= clamped) {
        _activeTab++;
      }
    });
    widget.onReorder(oldIndex, clamped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = cs.outlineVariant;

    return Container(
      height: 35,
      color: cs.surfaceContainer,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        // +1 for the non-draggable add button appended after the last tab
        itemCount: _tabs.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _tabs.length) {
            return InkWell(
              key: const ValueKey('_add_tab_'),
              onTap: widget.onAdd,
              child: SizedBox(
                width: 32,
                height: 35,
                child: Icon(Icons.add, size: 16, color: cs.onSurfaceVariant),
              ),
            );
          }
          return ReorderableDragStartListener(
            key: ValueKey(_tabs[i].tabId),
            index: i,
            child: _buildTabItem(i, isDark, divider, cs),
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex >= _tabs.length) return;
          _handleReorder(oldIndex, newIndex);
        },
      ),
    );
  }

  Widget _buildTabItem(int index, bool isDark, Color divider, ColorScheme cs) {
    final tab = _tabs[index];
    final isActive = index == _activeTab;
    final activeBg = isDark ? cs.surfaceContainerLow : cs.surface;
    final inactiveBg = cs.surfaceContainerHigh;
    final activeText = cs.onSurface;
    final inactiveText = cs.onSurfaceVariant;
    const accent = Color(0xFF0078D4);

    final inEditor = tab.loading || tab.procedimiento != null;
    final icon = inEditor
        ? (tab.procedimiento?.inConfiguracion == 'J'
              ? Icons.code
              : Icons.storage)
        : Icons.search;
    final label = tab.procedimiento?.cdProcedimiento ?? 'Buscar';

    return Container(
      height: 35,
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 180),
      decoration: BoxDecoration(
        color: isActive ? activeBg : inactiveBg,
        border: Border(
          top: BorderSide(
            color: isActive ? accent : Colors.transparent,
            width: 2,
          ),
          right: BorderSide(color: divider),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InkWell(
              onTap: () => widget.onActivate(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                child: Row(
                  children: [
                    if (tab.loading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF0078D4),
                        ),
                      )
                    else
                      Icon(
                        icon,
                        size: 14,
                        color: isActive ? activeText : inactiveText,
                      ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive ? activeText : inactiveText,
                        ),
                      ),
                    ),
                    if (tab.isDirty && tab.procedimiento != null)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildAmbienteBadge(tab),
          if (_tabs.length > 1)
            InkWell(
              onTap: () => widget.onClose(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 11,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isActive ? activeText : inactiveText,
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAmbienteBadge(AppTab tab) {
    final color = AmbienteSelector.colorForAmbiente(tab.ambiente);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        tab.ambiente,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// Fades in a tab when it becomes active; subsequent activations start at 0.7
// to avoid the "content cleared" visual artifact on returning to a known tab.
class _TabFadeIn extends StatefulWidget {
  final Widget child;
  const _TabFadeIn({required super.key, required this.child});

  @override
  State<_TabFadeIn> createState() => _TabFadeInState();
}

class _TabFadeInState extends State<_TabFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _wasTickerEnabled = false;
  bool _hasBeenActiveOnce = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled && !_wasTickerEnabled) {
      _ctrl.forward(from: _hasBeenActiveOnce ? 0.7 : 0.0);
      _hasBeenActiveOnce = true;
    }
    _wasTickerEnabled = enabled;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _ctrl, child: widget.child);
  }
}
