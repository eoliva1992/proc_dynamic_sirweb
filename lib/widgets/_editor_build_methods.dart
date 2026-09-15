part of 'code_editor_panel.dart';

// ── Métodos _build* del editor — toolbar, tabs, botones, panel de problemas ──

extension _EditorBuildMethods on _CodeEditorPanelState {
  /// Panel de problemas (sintaxis + compilación Oracle).
  ///
  /// Se monta como capa flotante DENTRO del `Stack` del editor, no como
  /// hermano en el `Column`. Si fuera hermano, al abrirlo el `Expanded` del
  /// editor se encogería y Monaco —que es una textura de WebView2— haría un
  /// relayout visible: el código "salta". Como overlay, el editor conserva
  /// exactamente su tamaño y solo aparece el panel encima.
  Widget _buildProblemsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final procId = _activeProcId ?? '';
    final compileIssues = _compileErrorsPerProc[procId] ?? [];
    final backendIssues = _backendIssuesPerProc[procId] ?? [];
    final allIssues = [...compileIssues, ...backendIssues]
      ..sort((a, b) => a.line.compareTo(b.line));
    final errorCount = allIssues
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final warnCount = allIssues
        .where((e) => e.severity == MarkerSeverity.warning)
        .length;

    // El panel entra deslizándose desde abajo y se funde al salir.
    return SlideUpPanel(
      visible: _showProblemsPanel,
      height: _problemsPanelHeight,
      child: Container(
        height: _problemsPanelHeight,
        decoration: BoxDecoration(
          // Opaco a propósito: el panel flota sobre el editor y el
          // código no debe transparentarse por detrás.
          color: isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          children: [
            // Resize handle + header combined
            GestureDetector(
              onVerticalDragUpdate: (d) {
                setState(() {
                  _problemsPanelHeight = (_problemsPanelHeight - d.delta.dy)
                      .clamp(80.0, 400.0);
                });
              },
              onVerticalDragEnd: (_) => _savePrefs(),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: Container(
                  height: 28,
                  color: isDark
                      ? cs.surfaceContainerHigh
                      : cs.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.list_alt_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Problemas',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (errorCount > 0)
                        _ProblemCount(count: errorCount, isError: true),
                      if (warnCount > 0) ...[
                        const SizedBox(width: 4),
                        _ProblemCount(count: warnCount, isError: false),
                      ],
                      if (_backendChecking) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Spacer(),
                      InkWell(
                        onTap: () => setState(() => _showProblemsPanel = false),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: allIssues.isEmpty
                  ? Center(
                      child: Text(
                        'Sin problemas detectados',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: allIssues.length,
                      itemBuilder: (_, i) {
                        final issue = allIssues[i];
                        final isError = issue.severity == MarkerSeverity.error;
                        return InkWell(
                          onTap: () async {
                            await _withCtrl((ctrl) async {
                              await ctrl.revealLine(issue.line, center: true);
                              await ctrl.setCursorPosition(
                                Position(line: issue.line, column: issue.col),
                              );
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isError
                                      ? Icons.error_outline
                                      : Icons.warning_amber_rounded,
                                  size: 14,
                                  color: isError
                                      ? Colors.red[400]
                                      : Colors.orange[400],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    issue.message,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'Consolas',
                                    ),
                                    softWrap: true,
                                    maxLines: 4,
                                    overflow: TextOverflow.fade,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (issue.line > 1 || issue.col > 1)
                                  Text(
                                    'L${issue.line}:${issue.col}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                      fontFamily: 'Consolas',
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    issue.source,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: issue.source == 'Oracle'
                                          ? Colors.orange[400]
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Copiar mensaje',
                                  child: InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text:
                                              '${issue.source} L${issue.line}:${issue.col} — ${issue.message}',
                                        ),
                                      );
                                      AppToast.info('Copiado al portapapeles');
                                    },
                                    borderRadius: BorderRadius.circular(3),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                        color: cs.onSurfaceVariant.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocTabs(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerLow;
    return Container(
      height: 30,
      color: bgColor,
      child: Stack(
        children: [
          ListView.builder(
            controller: _tabsScrollCtrl,
            scrollDirection: Axis.horizontal,
            itemCount: _openProcs.length,
            itemBuilder: (_, i) {
              final proc = _openProcs[i];
              final active = proc.cdProcedimiento == _activeProcId;
              return Tooltip(
                message: proc.cdProcedimiento,
                waitDuration: _kTooltipWait,
                child: _DocTab(
                  proc: proc,
                  isActive: active,
                  isModified: _modifiedProcs.contains(proc.cdProcedimiento),
                  onTap: () => _switchToProc(proc),
                  onClose: _openProcs.length > 1 ? () => _closeDoc(proc) : null,
                ),
              );
            },
          ),
          if (_tabsCanScrollLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [bgColor, bgColor.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          if (_tabsCanScrollRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [bgColor.withValues(alpha: 0), bgColor],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        spacing: 5,
        children: [
          _ToggleBtn(
            icon: Icons.map_outlined,
            tooltip: 'Minimap',
            active: _minimap,
            onPressed: () => _toggle(() => _minimap = !_minimap),
          ),
          _ToggleBtn(
            icon: Icons.format_list_numbered,
            tooltip: 'Número de líneas',
            active: _lineNumbers,
            onPressed: () => _toggle(() => _lineNumbers = !_lineNumbers),
          ),
          _ToggleBtn(
            icon: _folding ? Icons.unfold_less : Icons.unfold_more,
            tooltip: 'Colapsar bloques',
            active: _folding,
            onPressed: () => _toggle(() => _folding = !_folding),
          ),
          _ToggleBtn(
            icon: _readOnly ? Icons.lock_outline : Icons.lock_open,
            tooltip: 'Solo lectura — bloquear edición',
            active: _readOnly,
            onPressed: () => _toggle(() => _readOnly = !_readOnly),
          ),
          const SizedBox(width: 4),
          Container(
            height: 26,
            decoration: BoxDecoration(
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.7),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Reducir fuente (Ctrl+−)',
                  waitDuration: _kTooltipWait,
                  preferBelow: false,
                  decoration: _kTooltipDecoration,
                  textStyle: _kTooltipTextStyle,
                  child: InkWell(
                    onTap: _fontSize > 10
                        ? () => _toggle(
                            () => _fontSize = (_fontSize - 2).clamp(10, 28),
                          )
                        : null,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(13),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 14,
                        color: _fontSize > 10
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${_fontSize.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Aumentar fuente (Ctrl+=)',
                  waitDuration: _kTooltipWait,
                  preferBelow: false,
                  decoration: _kTooltipDecoration,
                  textStyle: _kTooltipTextStyle,
                  child: InkWell(
                    onTap: _fontSize < 28
                        ? () => _toggle(
                            () => _fontSize = (_fontSize + 2).clamp(10, 28),
                          )
                        : null,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(13),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Icon(
                        Icons.add,
                        size: 14,
                        color: _fontSize < 28
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          _buildThemeToggleBtn(cs),
          _buildOptionsGear(cs),
          _buildVarsButton(cs),
          _ToggleBtn(
            icon: Icons.account_tree_outlined,
            tooltip: 'Outline — estructura del procedimiento',
            active: _showOutline,
            onPressed: _toggleOutline,
          ),
          // _ToggleBtn(
          //   icon: Icons.auto_awesome,
          //   tooltip: 'Chat con GitHub Copilot',
          //   active: _showAiChat,
          //   onPressed: _toggleAiChat,
          // ),
          _ToolBtn(
            icon: Icons.code_rounded,
            tooltip: 'Snippets de usuario',
            onPressed: _openSnippetsManager,
          ),
          _ToolBtn(
            icon: Icons.data_object_rounded,
            tooltip: 'Consultar dato — InfoDato (Alt+D)',
            onPressed: () => unawaited(_openInfoDatoWindow()),
          ),
          _ToolBtn(
            icon: Icons.bolt_rounded,
            tooltip: 'Consultar evento — InfoEvento (Alt+E)',
            onPressed: () => unawaited(_openInfoEventoWindow()),
          ),
          _ToolBtn(
            icon: Icons.verified_user_outlined,
            tooltip: 'Consultar autorizaciones de proceso (Alt+A)',
            onPressed: () => unawaited(_openAutorizacionesWindow()),
          ),
          _ToolBtn(
            icon: Icons.travel_explore_rounded,
            tooltip: 'Usos del procedimiento — tabla y campo (Alt+U)',
            onPressed: () => unawaited(_showUsosProcedimiento()),
          ),
          _ToolBtn(
            icon: Icons.play_circle_outline_rounded,
            tooltip: 'Ejecutar procedimiento dinámico (Alt+R)',
            onPressed: () => unawaited(_ejecutarProcedimiento()),
          ),
          const Spacer(),
          _buildErrorBadge(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          _buildCompileBtn(cs),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: cs.outlineVariant, width: 12),
          ),
          const SizedBox(width: 4),
          _buildSaveBtn(cs),
          _ToolBtn(
            icon: Icons.compare_arrows,
            tooltip: 'Ver diff vs. versión guardada (sin guardar)',
            onPressed: _openDiff,
          ),
          _ToolBtn(
            icon: Icons.format_align_left,
            tooltip: 'Formatear documento (Shift+Alt+F)',
            onPressed: () => unawaited(
              _withCtrl(
                (ctrl) => ctrl.executeAction(MonacoAction.formatDocument),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompileBtn(ColorScheme cs) {
    return switch (_compileStatus) {
      _CompileStatus.compiling => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF569CD6),
          ),
        ),
      ),
      _CompileStatus.ok => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.green[500]),
              const SizedBox(width: 4),
              Text(
                'Compilado',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      _CompileStatus.error => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: Colors.orange[400]),
            const SizedBox(width: 4),
            Text(
              'Errores',
              style: TextStyle(fontSize: 11, color: Colors.orange[400]),
            ),
          ],
        ),
      ),
      _CompileStatus.idle => Tooltip(
        message:
            'Compilar con Oracle — verifica errores sin guardar si falla (F5)',
        waitDuration: _kTooltipWait,
        preferBelow: false,
        decoration: _kTooltipDecoration,
        textStyle: _kTooltipTextStyle,
        child: InkWell(
          onTap: _compileCurrentDocument,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 15,
                  color: const Color(0xFF569CD6),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Compilar',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF569CD6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    };
  }

  Widget _buildSaveBtn(ColorScheme cs) {
    return switch (_saveStatus) {
      _SaveStatus.saving => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF0078D4),
          ),
        ),
      ),
      _SaveStatus.saved => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 250),
        curve: Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: Colors.green[600],
              ),
              const SizedBox(width: 4),
              Text(
                'Guardado',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      _SaveStatus.error => Tooltip(
        message: _lastSaveError ?? 'Error al guardar',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
              const SizedBox(width: 4),
              Text(
                'Error al guardar',
                style: TextStyle(fontSize: 11, color: Colors.red[400]),
              ),
            ],
          ),
        ),
      ),
      _SaveStatus.idle => _buildSaveBtnIdle(cs),
    };
  }

  Widget _buildSaveBtnIdle(ColorScheme cs) {
    final isDirty = _modifiedProcs.contains(_activeProcId);
    final canSave = widget.onSave != null;
    return Tooltip(
      message: 'Guardar (Ctrl+S)',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: canSave ? _saveCurrentDocument : null,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDirty
                ? const Color(0xFF0078D4).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isDirty
                ? Border.all(
                    color: const Color(0xFF0078D4).withValues(alpha: 0.4),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.save_outlined,
                size: 15,
                color: isDirty
                    ? const Color(0xFF0078D4)
                    : cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              if (isDirty) ...[
                const SizedBox(width: 4),
                const Text(
                  'Guardar',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF0078D4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVarsButton(ColorScheme cs) {
    final vars = _filteredVariables();
    if (vars.isEmpty) return const SizedBox();
    return Tooltip(
      message: _varsDocked
          ? 'Variables dinámicas — click derecho para desanclar panel'
          : 'Variables dinámicas (${vars.length}) — click derecho para anclar panel',
      waitDuration: _kTooltipWait,
      preferBelow: true,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: GestureDetector(
        key: _varsButtonKey,
        onSecondaryTap: () {
          setState(() => _varsDocked = !_varsDocked);
          _savePrefs();
        },
        onTap: _varsDocked ? null : () => _showVarsOverlay(vars),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _varsDocked
                ? cs.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Badge(
            label: Text('${vars.length}', style: const TextStyle(fontSize: 10)),
            child: Icon(
              Icons.data_object,
              size: 16,
              color: _varsDocked ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _showVarsOverlay(List<VariableDinamica> vars) {
    final box = _varsButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset(0, box.size.height + 4));
    final screenW = MediaQuery.sizeOf(context).width;
    const panelW = 300.0;
    final left = (anchor.dx + panelW > screenW)
        ? screenW - panelW - 8
        : anchor.dx;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'vars-dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => _VarsMenuOverlay(
        left: left,
        top: anchor.dy,
        width: panelW,
        vars: vars,
        onSelected: (v) async {
          final ctrl = _ctrl;
          if (ctrl == null) return;
          final pos = await ctrl.getCursorPosition();
          if (pos != null) {
            await ctrl.document.insert(pos, ':${v.cdVariable}');
          }
        },
      ),
    );
  }

  void _showThemePickerDialog() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'theme-picker',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, _, _) => _ThemePickerDialog(
        currentThemeId: editorThemeStore.themeId,
        onSelected: (id) async {
          await editorThemeStore.setTheme(id);
          await _withCtrl(
            (ctrl) => ctrl.setTheme(editorThemeStore.monacoTheme),
          );
        },
      ),
    );
  }

  Widget _buildErrorBadge(ColorScheme cs) {
    final procId = _activeProcId ?? '';
    final compileErrors = (_compileErrorsPerProc[procId] ?? [])
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final backendErrors = (_backendIssuesPerProc[procId] ?? [])
        .where((e) => e.severity == MarkerSeverity.error)
        .length;
    final n = compileErrors + backendErrors;
    final badge = Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: n > 0
            ? Colors.red.withValues(alpha: 0.12)
            : Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: n > 0
              ? Colors.red.withValues(alpha: 0.45)
              : Colors.green.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            n > 0 ? Icons.error_outline : Icons.check_circle_outline,
            size: 12,
            color: n > 0 ? Colors.red[400] : Colors.green[600],
          ),
          const SizedBox(width: 4),
          Text(
            n > 0 ? '$n' : 'OK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: n > 0 ? Colors.red[400] : Colors.green[600],
            ),
          ),
        ],
      ),
    );

    if (n == 0) {
      return Tooltip(
        message: 'Sin errores de sintaxis',
        waitDuration: _kTooltipWait,
        preferBelow: false,
        decoration: _kTooltipDecoration,
        textStyle: _kTooltipTextStyle,
        child: badge,
      );
    }

    return Tooltip(
      message: _showProblemsPanel
          ? 'Ocultar panel de problemas'
          : 'Mostrar panel de problemas',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: () => setState(() => _showProblemsPanel = !_showProblemsPanel),
        borderRadius: BorderRadius.circular(10),
        child: badge,
      ),
    );
  }

  Widget _buildThemeToggleBtn(ColorScheme cs) {
    final meta = editorThemeStore.currentMeta;
    final isDarkTheme = meta.isDark;
    return Tooltip(
      message: isDarkTheme ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
      waitDuration: _kTooltipWait,
      preferBelow: false,
      decoration: _kTooltipDecoration,
      textStyle: _kTooltipTextStyle,
      child: InkWell(
        onTap: () async {
          await editorThemeStore.setTheme(editorThemeStore.pairedThemeId);
          await _withCtrl(
            (ctrl) => ctrl.setTheme(editorThemeStore.monacoTheme),
          );
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Icon(
            isDarkTheme ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsGear(ColorScheme cs) {
    final headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      letterSpacing: 0.8,
    );
    return PopupMenuButton<_EditorOption>(
      tooltip: 'Más opciones del editor',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
      onSelected: (_EditorOption opt) {
        if (opt == _EditorOption.resetDefaults) {
          _resetAllOptions();
          return;
        }
        _toggle(() {
          switch (opt) {
            case _EditorOption.wordWrap:
              _wordWrap = !_wordWrap;
            case _EditorOption.renderWhitespace:
              _renderWhitespace = !_renderWhitespace;
            case _EditorOption.bracketColorize:
              _bracketPairColorization = !_bracketPairColorization;
            case _EditorOption.stickyScroll:
              _stickyScroll = !_stickyScroll;
            case _EditorOption.smoothScrolling:
              _smoothScrolling = !_smoothScrolling;
            case _EditorOption.mouseWheelZoom:
              _mouseWheelZoom = !_mouseWheelZoom;
            case _EditorOption.formatOnPaste:
              _formatOnPaste = !_formatOnPaste;
            case _EditorOption.quickSuggestions:
              _quickSuggestions = !_quickSuggestions;
            case _EditorOption.parameterHints:
              _parameterHints = !_parameterHints;
            case _EditorOption.hover:
              _hover = !_hover;
            case _EditorOption.links:
              _links = !_links;
            case _EditorOption.occurrences:
              _occurrencesHighlight = !_occurrencesHighlight;
            case _EditorOption.contextMenu:
              _contextMenu = !_contextMenu;
            case _EditorOption.resetDefaults:
              break;
          }
        });
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('TEMA', style: headerStyle),
        ),
        PopupMenuItem<_EditorOption>(
          onTap: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showThemePickerDialog(),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: editorThemeStore.currentMeta.swatch,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                editorThemeStore.currentMeta.name,
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('VISUALIZACIÓN', style: headerStyle),
        ),
        _optItem(_EditorOption.wordWrap, 'Ajuste de línea', _wordWrap),
        _optItem(
          _EditorOption.renderWhitespace,
          'Mostrar espacios/tabs',
          _renderWhitespace,
        ),
        _optItem(
          _EditorOption.bracketColorize,
          'Colorizar paréntesis',
          _bracketPairColorization,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('SCROLL', style: headerStyle),
        ),
        _optItem(_EditorOption.stickyScroll, 'Scroll pegajoso', _stickyScroll),
        _optItem(
          _EditorOption.smoothScrolling,
          'Scroll suave',
          _smoothScrolling,
        ),
        _optItem(
          _EditorOption.mouseWheelZoom,
          'Zoom con rueda del ratón',
          _mouseWheelZoom,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('EDICIÓN', style: headerStyle),
        ),
        _optItem(
          _EditorOption.formatOnPaste,
          'Formatear al pegar',
          _formatOnPaste,
        ),
        _optItem(
          _EditorOption.quickSuggestions,
          'Sugerencias automáticas',
          _quickSuggestions,
        ),
        _optItem(
          _EditorOption.parameterHints,
          'Hints de parámetros',
          _parameterHints,
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          enabled: false,
          height: 28,
          child: Text('INTERFAZ', style: headerStyle),
        ),
        _optItem(_EditorOption.hover, 'Tooltips hover', _hover),
        _optItem(_EditorOption.links, 'Links clicables', _links),
        _optItem(
          _EditorOption.occurrences,
          'Resaltar ocurrencias',
          _occurrencesHighlight,
        ),
        _optItem(_EditorOption.contextMenu, 'Menú contextual', _contextMenu),
        const PopupMenuDivider(),
        PopupMenuItem<_EditorOption>(
          value: _EditorOption.resetDefaults,
          child: Row(
            children: [
              Icon(
                Icons.refresh,
                size: 14,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              const Text(
                'Restablecer predeterminados',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  CheckedPopupMenuItem<_EditorOption> _optItem(
    _EditorOption value,
    String label,
    bool checked,
  ) {
    return CheckedPopupMenuItem<_EditorOption>(
      value: value,
      checked: checked,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
