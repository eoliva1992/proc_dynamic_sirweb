import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';

/// Selector de sub-pestañas para múltiples resultados de SELECT dentro de la
/// pestaña "Resultados" (solo se usa cuando hay más de un resultado).
class SqlResultsTabStrip extends StatelessWidget {
  const SqlResultsTabStrip({
    super.key,
    required this.results,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<SqlNamedResult> results;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final borderColor = isDark
        ? const Color(0xFF30363D)
        : cs.outlineVariant.withValues(alpha: 0.8);
    final stripBg = isDark ? const Color(0xFF13171D) : const Color(0xFFF1F3F5);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: stripBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: results.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark
                          ? cs.primary.withValues(alpha: 0.22)
                          : cs.primary.withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.6)
                      : borderColor.withValues(alpha: 0.5),
                  width: selected ? 1.0 : 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.table_chart_rounded,
                    size: 12,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'SELECT ${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withValues(alpha: isDark ? 0.3 : 0.15)
                          : cs.onSurfaceVariant.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${results[i].result.returnedRows}',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
