part of 'code_editor_panel.dart';

// ── Guardar & Compilar ───────────────────────────────────────────────────────

extension _EditorSaveCompileMethods on _CodeEditorPanelState {
  Future<void> _saveCurrentDocument() async {
    final onSave = widget.onSave;
    if (onSave == null || _saveStatus == _SaveStatus.saving) return;
    final code = await _withCtrl((ctrl) => ctrl.document.getText());
    if (code == null || !mounted) return;
    setState(() => _saveStatus = _SaveStatus.saving);
    _saveTimer?.cancel();
    try {
      await onSave(code);
      if (!mounted) return;
      final id = _activeProcId;
      if (id != null) {
        final idx = _openProcs.indexWhere((p) => p.cdProcedimiento == id);
        if (idx != -1) {
          setState(
            () => _openProcs[idx] = _openProcs[idx].copyWith(deTexto: code),
          );
        }
        setState(() {
          _modifiedProcs.remove(id);
          _draftVisible.remove(id);
        });
        _draftDebounce?.cancel();
        unawaited(EditorDraftService.clear(id, widget.ambiente));
      }
      widget.onDirtyChanged?.call(false);
      final rawCompileErrors = procedimientosProvider.lastCompileErrors;
      final procId = _activeProcId ?? '';
      if (rawCompileErrors.isNotEmpty && mounted) {
        final compileIssues = parseOracleCompileErrors(rawCompileErrors);
        setState(() {
          _compileErrorsPerProc[procId] = compileIssues;
          _errorCounts[procId] =
              (compileIssues + (_backendIssuesPerProc[procId] ?? []))
                  .where((e) => e.severity == MarkerSeverity.error)
                  .length;
        });
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [
              ...compileIssues,
              ...(_backendIssuesPerProc[procId] ?? []),
            ])
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker'),
        );
        AppToast.warning(
          '${compileIssues.length} error${compileIssues.length == 1 ? '' : 'es'} de compilación Oracle',
        );
        if (mounted) setState(() => _showProblemsPanel = true);
      } else if (mounted && _compileErrorsPerProc.containsKey(procId)) {
        setState(() => _compileErrorsPerProc.remove(procId));
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [...(_backendIssuesPerProc[procId] ?? [])])
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker'),
        );
      }
      if (!mounted) return;
      setState(() => _saveStatus = _SaveStatus.saved);
      _saveTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[CodeEditorPanel] Error al guardar: $msg');
      if (!mounted) return;
      final procId = _activeProcId ?? '';
      final parsed = parseOracleCompileErrors(msg);
      final serverErrors = parsed.isNotEmpty
          ? parsed
          : [
              PlSqlIssue(
                line: 1,
                col: 1,
                endCol: 2,
                message: msg,
                source: 'Oracle',
              ),
            ];
      setState(() {
        _saveStatus = _SaveStatus.error;
        _lastSaveError = msg;
        _compileErrorsPerProc[procId] = serverErrors;
        _errorCounts[procId] =
            (serverErrors + (_backendIssuesPerProc[procId] ?? []))
                .where((e) => e.severity == MarkerSeverity.error)
                .length;
        _showProblemsPanel = true;
      });
      final editorCtrl = _ctrl;
      if (editorCtrl != null) {
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [
              ...serverErrors,
              ...(_backendIssuesPerProc[procId] ?? []),
            ])
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker'),
        );
        await _withErrorDecos(
          (decos) => decos.set([
            for (final e in serverErrors)
              DecorationOptions.line(
                range: Range.lines(e.line, e.line),
                className: 'plsql-error-line',
                additionalOptions: {
                  'overviewRuler': {'color': '#FF4444', 'position': 4},
                  'minimap': {'color': '#FF4444', 'position': 1},
                },
              ),
          ]),
        );
      }
      _saveTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saveStatus = _SaveStatus.idle);
      });
    }
  }

  // ── Compilar (usa el ANTLR4/Oracle del servidor) ──────────────────────────

  Future<void> _compileCurrentDocument() async {
    final onCompile = widget.onCompile;
    if (onCompile == null || _compileStatus == _CompileStatus.compiling) return;
    final code = await _withCtrl((ctrl) => ctrl.document.getText());
    if (code == null || !mounted) return;
    setState(() => _compileStatus = _CompileStatus.compiling);
    try {
      await onCompile(code);
      if (!mounted) return;
      final rawCompileErrors = procedimientosProvider.lastCompileErrors;
      final procId = _activeProcId ?? '';
      if (rawCompileErrors.isNotEmpty) {
        final compileIssues = parseOracleCompileErrors(rawCompileErrors);
        setState(() {
          _compileErrorsPerProc[procId] = compileIssues;
          _errorCounts[procId] = ([
            ...compileIssues,
            ...(_backendIssuesPerProc[procId] ?? []),
          ]).where((e) => e.severity == MarkerSeverity.error).length;
          _compileStatus = _CompileStatus.error;
          _showProblemsPanel = true;
        });
        await _withCtrl(
          (ctrl) => ctrl.document.setMarkers([
            for (final e in [
              ...compileIssues,
              ...(_backendIssuesPerProc[procId] ?? []),
            ])
              MarkerData(
                range: Range(
                  startLine: e.line,
                  startColumn: e.col,
                  endLine: e.line,
                  endColumn: e.endCol,
                ),
                message: e.message,
                severity: e.severity,
                source: e.source,
              ),
          ], owner: 'plsql-checker'),
        );
        await _withErrorDecos(
          (decos) => decos.set([
            for (final e in compileIssues)
              DecorationOptions.line(
                range: Range.lines(e.line, e.line),
                className: 'plsql-error-line',
                additionalOptions: {
                  'overviewRuler': {'color': '#FF4444', 'position': 4},
                  'minimap': {'color': '#FF4444', 'position': 1},
                },
              ),
          ]),
        );
      } else {
        if (_compileErrorsPerProc.containsKey(procId)) {
          setState(() => _compileErrorsPerProc.remove(procId));
        }
        setState(() => _compileStatus = _CompileStatus.ok);
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[CodeEditorPanel] Error al compilar: $msg');
      if (!mounted) return;
      final procId = _activeProcId ?? '';
      final parsed = parseOracleCompileErrors(msg);
      final errors = parsed.isNotEmpty
          ? parsed
          : [
              PlSqlIssue(
                line: 1,
                col: 1,
                endCol: 2,
                message: msg,
                source: 'Oracle',
              ),
            ];
      setState(() {
        _compileStatus = _CompileStatus.error;
        _compileErrorsPerProc[procId] = errors;
        _errorCounts[procId] = errors
            .where((e) => e.severity == MarkerSeverity.error)
            .length;
        _showProblemsPanel = true;
      });
    }
    Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _compileStatus = _CompileStatus.idle);
    });
  }
}
