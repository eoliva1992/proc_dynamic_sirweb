/// Vista en árbol del plan de ejecución (`EXPLAIN PLAN`), estilo Oracle SQL
/// Developer: árbol jerárquico con alertas cromáticas de rendimiento (Full Table Scans,
/// accesos por índice, joins) y métricas de costo, cardinalidad y bytes.
library;

import 'package:flutter/material.dart';
import '../../models/sql_execution.dart';

class SqlExplainPlanView extends StatefulWidget {
  const SqlExplainPlanView({super.key, required this.nodes, this.textPlan});

  final List<SqlExplainPlanNode>? nodes;
  final List<String>? textPlan;

  @override
  State<SqlExplainPlanView> createState() => _SqlExplainPlanViewState();
}

class _SqlExplainPlanViewState extends State<SqlExplainPlanView> {
  bool _showRawText = false;

  bool _isFullScan(SqlExplainPlanNode node) {
    final op = node.operation.toUpperCase();
    final opt = (node.options ?? '').toUpperCase();
    return (op.contains('TABLE ACCESS') && opt.contains('FULL')) ||
        op.contains('CARTESIAN');
  }

  bool _isIndexScan(SqlExplainPlanNode node) {
    final op = node.operation.toUpperCase();
    return op.contains('INDEX');
  }

  bool _isJoin(SqlExplainPlanNode node) {
    final op = node.operation.toUpperCase();
    return op.contains('JOIN') || op.contains('NESTED LOOPS');
  }

  Color _opColor(SqlExplainPlanNode node, bool isDark) {
    if (_isFullScan(node)) {
      return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    }
    if (_isIndexScan(node)) {
      return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    }
    if (_isJoin(node)) {
      return isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    }
    return isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
  }

  IconData _opIcon(SqlExplainPlanNode node) {
    if (_isFullScan(node)) return Icons.warning_amber_rounded;
    if (_isIndexScan(node)) return Icons.bolt_rounded;
    if (_isJoin(node)) return Icons.hub_outlined;
    return Icons.subdirectory_arrow_right_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final list = widget.nodes;
    final rawText = widget.textPlan;

    if ((list == null || list.isEmpty) &&
        (rawText == null || rawText.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Usá "Explain Plan" sobre un SELECT para ver el plan de ejecución',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ubicá el cursor en la consulta y presioná el botón de árbol en la barra',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final safeList = list ?? const [];
    final rootCost = safeList.isEmpty
        ? 0
        : (safeList.first.cost ??
              safeList.fold<int>(
                0,
                (max, n) => (n.cost ?? 0) > max ? (n.cost ?? 0) : max,
              ));
    final fullScanCount = safeList.where(_isFullScan).length;
    final indexScanCount = safeList.where(_isIndexScan).length;

    return Column(
      children: [
        _buildMetricHeader(
          cs,
          isDark,
          safeList.length,
          rootCost,
          fullScanCount,
          indexScanCount,
          hasRawText: rawText != null && rawText.isNotEmpty,
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: _showRawText && rawText != null && rawText.isNotEmpty
              ? _buildRawTextView(rawText, cs, isDark)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  itemCount: safeList.length,
                  itemBuilder: (context, i) {
                    final node = safeList[i];
                    return _buildNodeRow(node, cs, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRawTextView(List<String> rawText, ColorScheme cs, bool isDark) {
    return Container(
      color: isDark ? cs.surfaceContainerLowest : cs.surface,
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        rawText.join('\n'),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildMetricHeader(
    ColorScheme cs,
    bool isDark,
    int totalNodes,
    int rootCost,
    int fullScans,
    int indexScans, {
    required bool hasRawText,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: isDark ? cs.surfaceContainerLow : cs.surface,
      child: Row(
        children: [
          _buildPillBadge(
            'Costo total: $rootCost',
            cs.primary,
            Icons.speed_rounded,
          ),
          const SizedBox(width: 6),
          _buildPillBadge(
            '$totalNodes operaciones',
            cs.onSurfaceVariant,
            Icons.format_list_numbered_rounded,
          ),
          if (fullScans > 0) ...[
            const SizedBox(width: 6),
            _buildPillBadge(
              '$fullScans Full Scan${fullScans > 1 ? 's' : ''}',
              Colors.red,
              Icons.warning_amber_rounded,
            ),
          ],
          if (indexScans > 0) ...[
            const SizedBox(width: 6),
            _buildPillBadge(
              '$indexScans Índice${indexScans > 1 ? 's' : ''}',
              Colors.green,
              Icons.bolt_rounded,
            ),
          ],
          const Spacer(),
          if (hasRawText) ...[
            InkWell(
              onTap: () => setState(() => _showRawText = !_showRawText),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _showRawText
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _showRawText
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.5),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showRawText
                          ? Icons.account_tree_outlined
                          : Icons.text_snippet_outlined,
                      size: 12,
                      color: _showRawText ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showRawText ? 'Ver árbol' : 'Ver texto plano',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _showRawText ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            'Jerarquía de operaciones Oracle',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeRow(SqlExplainPlanNode node, ColorScheme cs, bool isDark) {
    final color = _opColor(node, isDark);
    final isFull = _isFullScan(node);
    final isIndex = _isIndexScan(node);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: EdgeInsets.only(
        left: 8.0 + (14.0 * node.depth),
        right: 8,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: isFull
            ? Colors.red.withValues(alpha: isDark ? 0.12 : 0.06)
            : (node.depth % 2 == 1
                  ? (isDark
                        ? cs.surfaceContainerHigh.withValues(alpha: 0.25)
                        : cs.surfaceContainerLowest)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(4),
        border: isFull
            ? Border.all(
                color: Colors.red.withValues(alpha: isDark ? 0.4 : 0.3),
                width: 0.8,
              )
            : null,
      ),
      child: Row(
        children: [
          if (node.depth > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '└─',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.outlineVariant,
                ),
              ),
            ),
          Icon(_opIcon(node), size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  node.operation,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: isFull || isIndex
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
                if (node.options != null && node.options!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      node.options!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                if (node.objectName != null && node.objectName!.isNotEmpty)
                  Text(
                    'on ${node.objectOwner != null && node.objectOwner!.isNotEmpty ? '${node.objectOwner}.' : ''}${node.objectName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                if (node.objectType != null && node.objectType!.isNotEmpty)
                  Text(
                    '(${node.objectType})',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          if (node.cost != null) ...[
            _buildMetricPill('cost: ${node.cost}', cs.onSurfaceVariant, cs),
            const SizedBox(width: 4),
          ],
          if (node.cardinality != null) ...[
            _buildMetricPill(
              'rows: ${node.cardinality}',
              cs.onSurfaceVariant,
              cs,
            ),
            const SizedBox(width: 4),
          ],
          if (node.bytes != null) ...[
            _buildMetricPill('bytes: ${node.bytes}', cs.onSurfaceVariant, cs),
          ],
          if (node.accessPredicate != null &&
              node.accessPredicate!.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildMetricPill('access: ${node.accessPredicate}', cs.primary, cs),
          ],
          if (node.filterPredicate != null &&
              node.filterPredicate!.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildMetricPill(
              'filter: ${node.filterPredicate}',
              Colors.orange,
              cs,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricPill(String text, Color textColor, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontFamily: 'monospace',
          color: textColor,
        ),
      ),
    );
  }
}
