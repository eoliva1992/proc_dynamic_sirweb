part of 'object_source_page.dart';

extension _ObjectSourceProblemsPanel on _ObjectSourcePageState {
  /// Panel de problemas. Se monta como capa flotante dentro del `Stack` del
  /// editor: si fuera hermano en el `Column`, abrirlo encogería el editor y
  /// Monaco (textura de WebView2) haría un relayout visible.
  Widget _buildProblemsPanel(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final issues = _allActiveIssues;
    final errCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.error)
        .length;
    final warnCount = issues
        .where((e) => e.severity == fm.MarkerSeverity.warning)
        .length;
    const panelHeight = 200.0;
    return SlideUpPanel(
      visible: _showProblems,
      height: panelHeight,
      child: Container(
        height: panelHeight,
        decoration: BoxDecoration(
          // Opaco: flota sobre el código, que no debe transparentarse.
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
            Container(
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
                  if (errCount > 0)
                    _ProblemBadge(count: errCount, isError: true),
                  if (warnCount > 0) ...[
                    const SizedBox(width: 4),
                    _ProblemBadge(count: warnCount, isError: false),
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
                    onTap: () => setState(() => _showProblems = false),
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
            Expanded(
              child: issues.isEmpty
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
                      itemCount: issues.length,
                      itemBuilder: (_, i) {
                        final issue = issues[i];
                        final isError =
                            issue.severity == fm.MarkerSeverity.error;
                        return InkWell(
                          onTap: () =>
                              _specCtrl?.revealLine(issue.line, center: true),
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
                                    maxLines: 3,
                                    overflow: TextOverflow.fade,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'L${issue.line}:${issue.col}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                                const SizedBox(width: 4),
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
                                      color: switch (issue.source) {
                                        'Oracle' ||
                                        'Oracle-DDL' => Colors.orange[400],
                                        'PL/SQL' => cs.primary,
                                        _ => cs.onSurfaceVariant,
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
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
                                      size: 12,
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.5,
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
}
