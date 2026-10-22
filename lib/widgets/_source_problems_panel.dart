part of 'object_source_page.dart';

extension _ObjectSourceProblemsPanel on _ObjectSourcePageState {
  /// Panel de resultados (Mensajes/Salida de compilación y Trazas HTTP).
  /// Se monta como capa inferior deslizable dentro del `Stack` del editor,
  /// con la misma experiencia que `SqlExecutorResultsPanel`.
  Widget _buildProblemsPanel(bool isDark) {
    return SlideUpPanel(
      visible: _showProblems,
      height: _resultsPanelHeight,
      child: SizedBox(
        height: _resultsPanelHeight,
        child: TapRegion(
          groupId: 'object_source_results_panel',
          onTapOutside: (_) => _onAutoHideResultsPanel(),
          child: ObjectSourceResultsPanel(
            tabController: _resultsTabCtrl,
            visible: _showProblems,
            height: _resultsPanelHeight,
            onHeightChanged: _onResultsPanelHeightChanged,
            onToggleVisible: _onToggleResultsPanel,
            onClose: _onCloseResultsPanel,
            isPinned: _panelPinned,
            onTogglePinned: _onTogglePanelPinned,
            issues: _allActiveIssues,
            checking: _backendChecking,
            onJumpTo: (issue) {
              _specCtrl?.revealLine(issue.line, center: true);
              _specCtrl?.setCursorPosition(
                fm.Position(line: issue.line, column: issue.col),
              );
            },
            httpTraces: _httpTraces,
            onClearHttpTraces: _onClearHttpTraces,
            onClearIssues: _onClearIssues,
            lastCompilation: _lastCompilation,
          ),
        ),
      ),
    );
  }
}
